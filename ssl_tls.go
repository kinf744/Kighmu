// ================================================================
// ssl_tls.go — Tunnel SSL/TLS SNI → TCP (SSH/VPN)
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
	"path/filepath"
	"strings"
)

// =====================
// CONSTANTES
// =====================
const (
	binPath     = "/usr/local/bin/ssl_tls"
	servicePath = "/etc/systemd/system/ssl_tls.service"

	logDir  = "/var/log/ssl_tls"
	logFile = "/var/log/ssl_tls/ssl_tls.log"

	infoFile = ".kighmu_info"
	listenIP = "0.0.0.0"
)

// =====================
// UTILS
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
// DOMAINE SERVEUR (kighmu_info)
// =====================
func serverDomain() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}

	f, err := os.Open(filepath.Join(home, infoFile))
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
// LOGGING
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
// IPTABLES
// =====================
func openFirewall(port string) {
	exec.Command("iptables", "-C", "INPUT", "-p", "tcp", "--dport", port, "-j", "ACCEPT").Run()
	exec.Command("iptables", "-I", "INPUT", "-p", "tcp", "--dport", port, "-j", "ACCEPT").Run()
	exec.Command("netfilter-persistent", "save").Run()
}

// =====================
// SYSTEMD
// =====================
func ensureSystemd(port, host, targetPort string) {
	if _, err := os.Stat(servicePath); err == nil {
		return
	}

	unit := fmt.Sprintf(`[Unit]
Description=SSL TLS SNI Tunnel
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
`, binPath, port, host, targetPort)

	writeFile(servicePath, []byte(unit), 0644)
	exec.Command("systemctl", "daemon-reload").Run()
	exec.Command("systemctl", "enable", "ssl_tls").Run()
	exec.Command("systemctl", "restart", "ssl_tls").Run()
}

// =====================
// TLS CONFIG (SNI)
// =====================
func tlsConfig() *tls.Config {
	return &tls.Config{
		MinVersion: tls.VersionTLS12,
		GetConfigForClient: func(chi *tls.ClientHelloInfo) (*tls.Config, error) {
			srvDom := serverDomain()

			log.Println("🌐 Domaine serveur :", srvDom)
			log.Println("📡 SNI client :", chi.ServerName)

			// Certificat générique auto (pas bloquant)
			cert, err := tls.X509KeyPair(localCert, localKey)
			if err != nil {
				return nil, err
			}

			return &tls.Config{
				Certificates: []tls.Certificate{cert},
			}, nil
		},
	}
}

// =====================
// HANDLER
// =====================
func handleTLS(c net.Conn, target string) {
	r, err := net.Dial("tcp", target)
	if err != nil {
		c.Close()
		return
	}

	go io.Copy(r, c)
	go io.Copy(c, r)
}

// =====================
// MAIN
// =====================
func main() {
	listen := flag.String("listen", "444", "Listen port")
	targetHost := flag.String("target-host", "127.0.0.1", "Target host")
	targetPort := flag.String("target-port", "22", "Target port")
	flag.Parse()

	setupLogging()
	openFirewall(*listen)
	ensureSystemd(*listen, *targetHost, *targetPort)

	target := net.JoinHostPort(*targetHost, *targetPort)

	ln, err := net.Listen("tcp", listenIP+":"+*listen)
	if err != nil {
		log.Fatal(err)
	}

	tlsLn := tls.NewListener(ln, tlsConfig())

	log.Println("🚀 Tunnel SSL/TLS actif sur le port", *listen)

	for {
		c, err := tlsLn.Accept()
		if err != nil {
			continue
		}
		go handleTLS(c, target)
	}
}
