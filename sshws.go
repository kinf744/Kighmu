// ================================================================
// sshws.go — TCP RAW Injector + WebSocket → SSH
// Listener TCP brut (HTTP Injector + WS même port)
// Ubuntu 18.04 → 24.04 | Go 1.13+ | systemd intégré
// Auteur : @kighmu
// Licence : MIT
// ================================================================

package main

import (
	"bufio"
	"crypto/sha1"
	"encoding/base64"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strings"
)

// =====================
// Constantes
// =====================
const (
	wsGUID      = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	infoFile    = ".kighmu_info"
	binPath     = "/usr/local/bin/sshws"
	servicePath = "/etc/systemd/system/sshws.service"

	logDir  = "/var/log/sshws"
	logFile = "/var/log/sshws/sshws.log"
)

// =====================
// Utils
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

func acceptKey(key string) string {
	h := sha1.New()
	h.Write([]byte(key + wsGUID))
	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}

func allowedDomain() string {
	u, err := user.Current()
	if err != nil {
		return ""
	}
	f, err := os.Open(filepath.Join(u.HomeDir, infoFile))
	if err != nil {
		return ""
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if strings.HasPrefix(line, "DOMAIN=") {
			return strings.Trim(strings.SplitN(line, "=", 2)[1], `"`)
		}
	}
	return ""
}

// =====================
// Logging
// =====================
func setupLogging() {
	_ = os.MkdirAll(logDir, 0755)
	f, _ := os.OpenFile(logFile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	log.SetOutput(io.MultiWriter(os.Stdout, f))
	log.SetFlags(log.LstdFlags)
}

// =====================
// systemd
// =====================
func ensureSystemd(port string) {
	if _, err := os.Stat(servicePath); err == nil {
		return
	}

	unit := fmt.Sprintf(`[Unit]
Description=SSH WS + TCP RAW Injector
After=network.target

[Service]
Type=simple
ExecStart=%s %s
Restart=always
RestartSec=1
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
`, binPath, port)

	_ = writeFile(servicePath, []byte(unit), 0644)
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

	client.Write([]byte(resp))

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
func handleTCP(client net.Conn, first []byte, target string) {
	client.Write([]byte(
		"HTTP/1.1 200 OK\r\n"+
			"Connection: keep-alive\r\n\r\n",
	))

	remote, err := net.Dial("tcp", target)
	if err != nil {
		client.Close()
		return
	}

	remote.Write(first)

	go io.Copy(remote, client)
	go io.Copy(client, remote)
}

// =====================
// MAIN
// =====================
func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: sshws <port>")
		return
	}

	port := os.Args[1]
	target := "127.0.0.1:22"

	setupLogging()
	ensureSystemd(port)

	ln, err := net.Listen("tcp", ":"+port)
	if err != nil {
		log.Fatal(err)
	}

	log.Println("🚀 SSHWS WS + TCP RAW actif sur le port", port)

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
				log.Println("[WS]", c.RemoteAddr())
				handleWebSocket(c, buf[:n], target)
			} else {
				log.Println("[TCP]", c.RemoteAddr())
				handleTCP(c, buf[:n], target)
			}
		}(client)
	}
}
