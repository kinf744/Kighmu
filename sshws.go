// ================================================================
// sshws.go — TCP RAW + WebSocket → SSH (MULTI-PORT STABLE)
// Ubuntu 18.04 → 24.04 | Go 1.13+ | systemd OK
// Auteur : @kighmu (corrigé définitivement)
// Licence : MIT
// ================================================================

package main

import (
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

// =====================
// Constantes
// =====================
const (
	wsGUID      = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	binPath     = "/usr/local/bin/sshws"
	servicePath = "/etc/systemd/system/sshws.service"
	logFile     = "/var/log/sshws.log"
)

// =====================
// Utils
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

[Install]
WantedBy=multi-user.target
`, binPath, listen, host, port)

	_ = os.WriteFile(servicePath, []byte(unit), 0644)
	exec.Command("systemctl", "daemon-reload").Run()
	exec.Command("systemctl", "enable", "sshws").Run()
	exec.Command("systemctl", "restart", "sshws").Run()
}

// =====================
// WebSocket Handler
// =====================
func handleWebSocket(c net.Conn, first []byte, target string) {
	req := string(first)
	key := ""

	for _, line := range strings.Split(req, "\n") {
		if strings.HasPrefix(strings.ToLower(line), "sec-websocket-key") {
			key = strings.TrimSpace(strings.SplitN(line, ":", 2)[1])
		}
	}

	if key == "" {
		c.Close()
		return
	}

	resp := fmt.Sprintf(
		"HTTP/1.1 101 Switching Protocols\r\n"+
			"Upgrade: websocket\r\n"+
			"Connection: Upgrade\r\n"+
			"Sec-WebSocket-Accept: %s\r\n\r\n",
		acceptKey(key),
	)

	c.Write([]byte(resp))

	remote, err := net.Dial("tcp", target)
	if err != nil {
		c.Close()
		return
	}

	go io.Copy(remote, c)
	go io.Copy(c, remote)
}

// =====================
// TCP RAW Handler (STABLE)
// =====================
func handleTCP(c net.Conn, target string) {
	remote, err := net.Dial("tcp", target)
	if err != nil {
		c.Close()
		return
	}

	go io.Copy(remote, c)
	go io.Copy(c, remote)
}

// =====================
// Listener
// =====================
func startListener(port, target string) {
	ln, err := net.Listen("tcp", ":"+port)
	if err != nil {
		log.Println("❌ Port", port, ":", err)
		return
	}

	log.Println("✅ Écoute sur port", port)

	for {
		c, err := ln.Accept()
		if err != nil {
			continue
		}

		go func(conn net.Conn) {
			buf := make([]byte, 2048)
			n, _ := conn.Read(buf)
			data := strings.ToLower(string(buf[:n]))

			if strings.Contains(data, "upgrade: websocket") {
				log.Println("[WS]", conn.RemoteAddr(), "→", port)
				handleWebSocket(conn, buf[:n], target)
			} else {
				log.Println("[TCP]", conn.RemoteAddr(), "→", port)
				handleTCP(conn, target)
			}
		}(c)
	}
}

// =====================
// MAIN
// =====================
func main() {
	listen := flag.String("listen", "80,8880,2052,2086", "Ports")
	targetHost := flag.String("target-host", "127.0.0.1", "SSH host")
	targetPort := flag.String("target-port", "22", "SSH port")
	flag.Parse()

	setupLogging()
	ensureSystemd(*listen, *targetHost, *targetPort)

	target := net.JoinHostPort(*targetHost, *targetPort)
	ports := strings.Split(*listen, ",")

	log.Println("🚀 SSHWS actif sur ports :", ports)

	for _, p := range ports {
		go startListener(strings.TrimSpace(p), target)
	}

	select {}
}
