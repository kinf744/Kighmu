// ================================================================
// sshws.go — TCP RAW Injector + WebSocket → SSH (MULTI-PORT)
// Go 1.13+ compatible | Ubuntu 18.04 → 24.04
// Domaine WS lu depuis ~/.kighmu_info
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

/* ===================== Constantes ===================== */

const (
	wsGUID      = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	infoFile    = ".kighmu_info"
	binPath     = "/usr/local/bin/sshws"
	servicePath = "/etc/systemd/system/sshws.service"

	logDir  = "/var/log/sshws"
	logFile = "/var/log/sshws/sshws.log"
)

/* ===================== Utils ===================== */

func writeFile(path string, data []byte, perm os.FileMode) error {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, perm)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = f.Write(data)
	return err
}

/* ===================== WebSocket Accept Key ===================== */

func acceptKey(key string) string {
	h := sha1.New()
	h.Write([]byte(key + wsGUID))
	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}

/* ===================== Domaine autorisé ===================== */

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

/* ===================== Logging ===================== */

func setupLogging() {
	_ = os.MkdirAll(logDir, 0755)
	f, err := os.OpenFile(logFile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		log.Fatal(err)
	}
	log.SetOutput(io.MultiWriter(os.Stdout, f))
	log.SetFlags(log.LstdFlags)
}

/* ===================== systemd ===================== */

func ensureSystemd(ports, host, port string) {
	unit := fmt.Sprintf(`[Unit]
Description=SSHWS WS + TCP RAW Tunnel (Multi-Port)
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=%s -listen %s -target-host %s -target-port %s
Restart=always
RestartSec=1
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
`, binPath, ports, host, port)

	_ = writeFile(servicePath, []byte(unit), 0644)
	exec.Command("systemctl", "daemon-reload").Run()
	exec.Command("systemctl", "enable", "sshws").Run()
	exec.Command("systemctl", "restart", "sshws").Run()
}

/* ===================== WebSocket ===================== */

func handleWebSocket(c net.Conn, first []byte, target string) {
	req := string(first)

	// Vérification domaine
	ad := allowedDomain()
	if ad != "" {
		for _, line := range strings.Split(req, "\n") {
			if strings.HasPrefix(strings.ToLower(line), "host:") {
				host := strings.TrimSpace(strings.SplitN(line, ":", 2)[1])
				if strings.Contains(host, ":") {
					host = strings.SplitN(host, ":", 2)[0]
				}
				if !strings.EqualFold(host, ad) {
					c.Write([]byte("HTTP/1.1 403 Forbidden\r\n\r\n"))
					c.Close()
					return
				}
			}
		}
	}

	// Récupération clé WS
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

	remote, err := net.Dial("tcp", target)
	if err != nil {
		c.Close()
		return
	}

	go io.Copy(remote, c)
	go io.Copy(c, remote)
}

/* ===================== TCP RAW ===================== */

func handleTCP(c net.Conn, target string) {
	c.Write([]byte("HTTP/1.1 200 OK\r\nConnection: keep-alive\r\n\r\n"))

	remote, err := net.Dial("tcp", target)
	if err != nil {
		c.Close()
		return
	}

	go io.Copy(remote, c)
	go io.Copy(c, remote)
}

/* ===================== Listener ===================== */

func startListener(port string, target string) {
	ln, err := net.Listen("tcp", ":"+port)
	if err != nil {
		log.Println("❌ Port", port, ":", err)
		return
	}
	log.Println("✅ Écoute sur le port", port)

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
				handleWebSocket(conn, buf[:n], target)
			} else {
				handleTCP(conn, target)
			}
		}(c)
	}
}

/* ===================== MAIN ===================== */

func main() {
	listen := flag.String("listen", "80,8880,2052,2086", "Ports d'écoute")
	targetHost := flag.String("target-host", "127.0.0.1", "SSH host")
	targetPort := flag.String("target-port", "22", "SSH port")
	flag.Parse()

	setupLogging()
	ensureSystemd(*listen, *targetHost, *targetPort)

	target := net.JoinHostPort(*targetHost, *targetPort)
	ports := strings.Split(*listen, ",")

	for _, p := range ports {
		go startListener(strings.TrimSpace(p), target)
	}

	select {}
}
