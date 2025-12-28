// ================================================================
// sshws.go — TCP RAW Injector + WebSocket → SSH (MULTI-PORT)
// Ubuntu 18.04 → 24.04 | Go 1.13+ | systemd intégré
// Auteur : @kighmu (corrigé Go 1.13+)
// Licence : MIT
// ================================================================

package main

import (
	"bufio"
	"crypto/sha1"
	"encoding/base64"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/exec"
	"strings"
)

const (
	wsGUID      = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	binPath     = "/usr/local/bin/sshws"
	servicePath = "/etc/systemd/system/sshws.service"

	logDir  = "/var/log/sshws"
	logFile = "/var/log/sshws/sshws.log"
)

// =====================
// writeFile compatible Go 1.13
// =====================
func writeFile(path string, data []byte, perm os.FileMode) error {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, perm)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = f.Write(data)
	return err
}

// =====================
// WebSocket accept key
// =====================
func acceptKey(key string) string {
	h := sha1.New()
	h.Write([]byte(key + wsGUID))
	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}

// =====================
// Logging
// =====================
func setupLogging() {
	_ = os.MkdirAll(logDir, 0755)
	f, err := os.OpenFile(logFile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		log.Fatal(err)
	}
	log.SetOutput(io.MultiWriter(os.Stdout, f))
	log.SetFlags(log.LstdFlags)
}

// =====================
// systemd
// =====================
func ensureSystemd(listen, host, port string) {
	unit := fmt.Sprintf(`[Unit]
Description=SSHWS TCP RAW + WebSocket Tunnel
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=%s -listen %s -target-host %s -target-port %s
Restart=always
RestartSec=1
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
`, binPath, listen, host, port)

	if err := writeFile(servicePath, []byte(unit), 0644); err != nil {
		log.Fatal("Impossible d'écrire le service systemd :", err)
	}

	exec.Command("systemctl", "daemon-reload").Run()
	exec.Command("systemctl", "enable", "sshws").Run()
	exec.Command("systemctl", "restart", "sshws").Run()
}

// =====================
// WebSocket RAW
// =====================
func handleWebSocket(client net.Conn, first []byte, target string) {
	req := string(first)
	key := ""
	for _, line := range strings.Split(req, "\n") {
		if strings.HasPrefix(strings.ToLower(line), "sec-websocket-key") {
			key = strings.TrimSpace(strings.SplitN(line, ":", 2)[1])
		}
	}
	if key == "" {
		key = "dGhlIHNhbXBsZSBub25jZQ=="
	}

	resp := fmt.Sprintf(
		"HTTP/1.1 101 Switching Protocols\r\n"+
			"Upgrade: websocket\r\n"+
			"Connection: Upgrade\r\n"+
			"Sec-WebSocket-Accept: %s\r\n\r\n",
		acceptKey(key),
	)
	_, _ = client.Write([]byte(resp))

	remote, err := net.Dial("tcp", target)
	if err != nil {
		client.Close()
		return
	}

	go io.Copy(remote, client)
	go io.Copy(client, remote)
}

// =====================
// TCP RAW Injector
// =====================
func handleTCP(client net.Conn, target string) {
	_, _ = client.Write([]byte(
		"HTTP/1.1 200 OK\r\n" +
			"Connection: keep-alive\r\n\r\n",
	))

	remote, err := net.Dial("tcp", target)
	if err != nil {
		client.Close()
		return
	}

	go io.Copy(remote, client)
	go io.Copy(client, remote)
}

// =====================
// Listener par port
// =====================
func startListener(port string, target string) {
	ln, err := net.Listen("tcp", ":"+port)
	if err != nil {
		log.Println("❌ Port", port, ":", err)
		return
	}
	log.Println("✅ Écoute active sur le port", port)

	for {
		client, err := ln.Accept()
		if err != nil {
			continue
		}

		go func(c net.Conn) {
			buf := make([]byte, 4096)
			n, err := c.Read(buf)
			if err != nil {
				c.Close()
				return
			}

			data := strings.ToLower(string(buf[:n]))
			if strings.Contains(data, "upgrade: websocket") {
				log.Println("[WS]", c.RemoteAddr(), "→", port)
				handleWebSocket(c, buf[:n], target)
			} else {
				log.Println("[TCP]", c.RemoteAddr(), "→", port)
				handleTCP(c, target)
			}
		}(client)
	}
}

// =====================
// MAIN
// =====================
func main() {
	listen := flag.String("listen", "80,8880,2052,2086", "Listen ports (comma separated)")
	targetHost := flag.String("target-host", "127.0.0.1", "SSH host")
	targetPort := flag.String("target-port", "22", "SSH port")
	flag.Parse()

	setupLogging()
	ensureSystemd(*listen, *targetHost, *targetPort)

	target := net.JoinHostPort(*targetHost, *targetPort)
	ports := strings.Split(*listen, ",")

	log.Println("🚀 SSHWS multi-port actif sur :", ports)

	for _, p := range ports {
		go startListener(strings.TrimSpace(p), target)
	}

	select {} // bloque le main
}
