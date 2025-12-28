// ================================================================
// sshws.go — TCP RAW Injector + WebSocket → SSH
// Compatible HTTP (ALL methods) + WS
// Ubuntu 18.04 → 24.04 | Go 1.13+ | systemd OK
// Auteur : @kighmu (corrigé définitivement)
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
// Utils fichiers (Go 1.13 compatible)
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
// Lecture domaine WS
// =====================
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
	if _, err := os.Stat(servicePath); err == nil {
		return
	}

	unit := fmt.Sprintf(`[Unit]
Description=SSHWS Slipstream Tunnel
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
		log.Fatal(err)
	}

	exec.Command("systemctl", "daemon-reload").Run()
	exec.Command("systemctl", "enable", "sshws").Run()
	exec.Command("systemctl", "restart", "sshws").Run()
}

// =====================
// WebSocket handler
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
		key = "dGhlIHNhbXBsZSBub25jZQ=="
	}

	resp := fmt.Sprintf(
		"HTTP/1.1 101 Switching Protocols\r\n"+
			"Upgrade: websocket\r\n"+
			"Connection: Upgrade\r\n"+
			"Sec-WebSocket-Accept: %s\r\n\r\n",
		acceptKey(key),
	)

	c.Write([]byte(resp))

	r, err := net.Dial("tcp", target)
	if err != nil {
		c.Close()
		return
	}

	go io.Copy(r, c)
	go io.Copy(c, r)
}

// =====================
// TCP RAW Injector (ALL HTTP METHODS)
// =====================
func handleTCP(c net.Conn, target string) {
	// Réponse générique HTTP valable pour GET/POST/PUT/DELETE/HEAD/OPTIONS/TRACE/PATCH/CONNECT
	c.Write([]byte(
		"HTTP/1.1 200 OK\r\n" +
			"Connection: keep-alive\r\n\r\n",
	))

	r, err := net.Dial("tcp", target)
	if err != nil {
		c.Close()
		return
	}

	// TCP brut
	go io.Copy(r, c)
	go io.Copy(c, r)
}

// =====================
// MAIN
// =====================
func main() {
	listen := flag.String("listen", "80", "Listen port")
	targetHost := flag.String("target-host", "127.0.0.1", "SSH host")
	targetPort := flag.String("target-port", "22", "SSH port")
	flag.Parse()

	setupLogging()
	ensureSystemd(*listen, *targetHost, *targetPort)

	target := net.JoinHostPort(*targetHost, *targetPort)

	ln, err := net.Listen("tcp", ":"+*listen)
	if err != nil {
		log.Fatal(err)
	}

	log.Println("🚀 SSHWS actif sur le port", *listen)

	for {
		c, err := ln.Accept()
		if err != nil {
			continue
		}

		go func(conn net.Conn) {
			buf := make([]byte, 4096)
			n, err := conn.Read(buf)
			if err != nil {
				conn.Close()
				return
			}

			data := strings.ToLower(string(buf[:n]))

			if strings.Contains(data, "upgrade: websocket") {
				log.Println("[WS]", conn.RemoteAddr())
				handleWebSocket(conn, buf[:n], target)
			} else {
				log.Println("[TCP]", conn.RemoteAddr())
				handleTCP(conn, target)
			}
		}(c)
	}
}
