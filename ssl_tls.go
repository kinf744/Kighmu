// ================================================================
// ssl_tls.go — Tunnel SSL/TLS + TCP RAW
// Compatible Go 1.13+ | Ubuntu 18.04 → 24.04
// Auteur : @kighmu
// Licence : MIT
// ================================================================

package main

import (
	"bufio"
	"crypto/tls"
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
	infoFile    = ".kighmu_info"
	binPath     = "/usr/local/bin/ssl_tls"
	servicePath = "/etc/systemd/system/ssl_tls.service"

	certDir  = "/etc/ssl/ssl_tls"
	certFile = "/etc/ssl/ssl_tls/cert.pem"
	keyFile  = "/etc/ssl/ssl_tls/key.pem"

	logDir  = "/var/log/ssl_tls"
	logFile = "/var/log/ssl_tls/ssl_tls.log"
)

// =====================
// Utils fichiers compatibles Go 1.13
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
// Lecture domaine depuis kighmu_info
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
// Génération certificats auto-signés
// =====================
func ensureCerts() {
	if _, err := os.Stat(certFile); err == nil {
		return
	}
	os.MkdirAll(certDir, 0700)
	cmd := exec.Command("openssl", "req", "-x509", "-newkey", "rsa:2048",
		"-keyout", keyFile,
		"-out", certFile,
		"-days", "365",
		"-nodes",
		"-subj", "/CN=ssl_tls",
	)
	cmd.Run()
}

// =====================
// systemd
// =====================
func ensureSystemd(listen, host, port string) {
	if _, err := os.Stat(servicePath); err == nil {
		return
	}

	unit := fmt.Sprintf(`[Unit]
Description=SSL TLS Tunnel (ssl_tls.go)
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
	exec.Command("systemctl", "enable", "ssl_tls").Run()
	exec.Command("systemctl", "restart", "ssl_tls").Run()
}

// =====================
// Handler SSL/TLS
// =====================
func handleTLS(conn net.Conn, target string, config *tls.Config) {
	tlsConn := tls.Server(conn, config)
	err := tlsConn.Handshake()
	if err != nil {
		conn.Close()
		return
	}

	r, err := net.Dial("tcp", target)
	if err != nil {
		conn.Close()
		return
	}

	go io.Copy(r, tlsConn)
	go io.Copy(tlsConn, r)
}

// =====================
// MAIN
// =====================
func main() {
	listen := flag.String("listen", "444", "Listen port SSL/TLS")
	targetHost := flag.String("target-host", "127.0.0.1", "SSH host")
	targetPort := flag.String("target-port", "22", "SSH port")
	flag.Parse()

	setupLogging()
	ensureCerts()
	ensureSystemd(*listen, *targetHost, *targetPort)

	// Ouverture port 444 dans iptables
	exec.Command("iptables", "-I", "INPUT", "-p", "tcp", "--dport", *listen, "-j", "ACCEPT").Run()
	exec.Command("iptables", "-I", "OUTPUT", "-p", "tcp", "--sport", *listen, "-j", "ACCEPT").Run()

	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		log.Fatal(err)
	}
	config := &tls.Config{
		Certificates: []tls.Certificate{cert},
	}

	ln, err := net.Listen("tcp", ":"+*listen)
	if err != nil {
		log.Fatal(err)
	}
	log.Println("🚀 SSL/TLS Tunnel actif sur le port", *listen)

	for {
		c, err := ln.Accept()
		if err != nil {
			continue
		}
		go handleTLS(c, net.JoinHostPort(*targetHost, *targetPort), config)
	}
}
