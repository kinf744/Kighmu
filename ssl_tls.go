// ================================================================
// ssl_tls.go — Tunnel SSL/TLS + TCP RAW → SSH
// Ubuntu 18.04 → 24.04 | Go 1.13+ | systemd OK
// Auteur : @kighmu (corrigé)
// Licence : MIT
// ================================================================

package main

import (
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

const (
	binPath     = "/usr/local/bin/ssl_tls"
	servicePath = "/etc/systemd/system/ssl_tls.service"
	logDir      = "/var/log/ssl_tls"
	logFile     = "/var/log/ssl_tls/ssl_tls.log"

	certDir  = "/etc/ssl/ssl_tls"
	certFile = certDir + "/server.crt"
	keyFile  = certDir + "/server.key"
	infoFile = ".kighmu_info"
)

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
// Lecture domaine SNI
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

	sc := io.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if strings.HasPrefix(line, "DOMAIN=") {
			return strings.Trim(strings.SplitN(line, "=", 2)[1], `"`)
		}
	}
	return ""
}

// =====================
// Certificats SSL/TLS
// =====================
func ensureCerts() {
	if _, err := os.Stat(certFile); os.IsNotExist(err) {
		os.MkdirAll(certDir, 0700)
		cmd := exec.Command("openssl", "req", "-x509", "-newkey", "rsa:2048",
			"-keyout", keyFile,
			"-out", certFile,
			"-days", "365",
			"-nodes",
			"-subj", "/CN=ssl_tls")
		cmd.Run()
		log.Println("[INFO] Certificats SSL/TLS créés automatiquement")
	}
}

// =====================
// systemd
// =====================
func ensureSystemd(port, targetHost, targetPort string) {
	if _, err := os.Stat(servicePath); err == nil {
		return
	}

	unit := fmt.Sprintf(`[Unit]
Description=SSL/TLS Tunnel (ssl_tls)
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=%s -port %s -target-host %s -target-port %s
Restart=always
RestartSec=2
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
`, binPath, port, targetHost, targetPort)

	if err := os.WriteFile(servicePath, []byte(unit), 0644); err != nil {
		log.Fatal(err)
	}

	exec.Command("systemctl", "daemon-reload").Run()
	exec.Command("systemctl", "enable", "ssl_tls").Run()
	exec.Command("systemctl", "restart", "ssl_tls").Run()
}

// =====================
// Tunnel SSL/TLS
// =====================
func handleSSL(client net.Conn, target string) {
	targetConn, err := net.Dial("tcp", target)
	if err != nil {
		client.Close()
		return
	}

	go io.Copy(targetConn, client)
	go io.Copy(client, targetConn)
}

// =====================
// MAIN
// =====================
func main() {
	port := flag.String("port", "444", "Port SSL/TLS")
	targetHost := flag.String("target-host", "127.0.0.1", "SSH host")
	targetPort := flag.String("target-port", "22", "SSH port")
	flag.Parse()

	setupLogging()
	ensureCerts()
	ensureSystemd(*port, *targetHost, *targetPort)

	target := fmt.Sprintf("%s:%s", *targetHost, *targetPort)

	cer, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		log.Fatal(err)
	}

	config := &tls.Config{
		Certificates: []tls.Certificate{cer},
		ServerName:   allowedDomain(), // SNI du tunnel
	}

	ln, err := tls.Listen("tcp", ":"+*port, config)
	if err != nil {
		log.Fatal(err)
	}

	// Ouverture port dans iptables
	exec.Command("iptables", "-I", "INPUT", "-p", "tcp", "--dport", *port, "-j", "ACCEPT").Run()
	exec.Command("iptables", "-I", "OUTPUT", "-p", "tcp", "--sport", *port, "-j", "ACCEPT").Run()

	log.Println("🚀 SSL/TLS tunnel actif sur port", *port)

	for {
		conn, err := ln.Accept()
		if err != nil {
			continue
		}

		go handleSSL(conn, target)
	}
}
