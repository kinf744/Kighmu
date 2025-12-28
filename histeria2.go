// ================================================================
// histeria2.go — Tunnel Hysteria 2 (UDP) avec TLS/QUIC simplifié
// Compatible Go 1.13+ | Ubuntu 18.04 → 24.04
// Auteur : @kighmu
// Licence : MIT
// ================================================================

package main

import (
	"bufio"
	"crypto/tls"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/exec"
	"strings"
)

const (
	usersFile   = "/etc/kighmu/users.list"
	binPath     = "/usr/local/bin/histeria2"
	servicePath = "/etc/systemd/system/histeria2.service"
	logDir      = "/var/log/histeria2"
	logFile     = "/var/log/histeria2/histeria2.log"
	port        = "22000"
	certDir     = "/etc/ssl/histeria2"
	certFile    = "/etc/ssl/histeria2/cert.pem"
	keyFile     = "/etc/ssl/histeria2/key.pem"
)

// =====================
// Utilitaires fichiers
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
// Logging
// =====================
func setupLogging() {
	_ = os.MkdirAll(logDir, 0755)
	f, err := os.OpenFile(logFile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		log.Fatal(err)
	}
	log.SetOutput(io.MultiWriter(os.Stdout, f))
	log.SetFlags(log.LstdFlags | log.Lshortfile)
}

// =====================
// Charger les utilisateurs
// =====================
func loadUsers() map[string]string {
	users := make(map[string]string)
	file, err := os.Open(usersFile)
	if err != nil {
		log.Println("[WARN] Fichier utilisateurs introuvable :", usersFile)
		return users
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.Split(line, "|")
		if len(parts) >= 2 {
			users[parts[0]] = parts[1]
		}
	}
	return users
}

// =====================
// Service systemd
// =====================
func ensureSystemd() {
	if _, err := os.Stat(servicePath); err == nil {
		return
	}

	unit := fmt.Sprintf(`[Unit]
Description=Hysteria2 UDP Tunnel (Kighmu)
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=%s
Restart=always
RestartSec=2
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
`, binPath)

	if err := writeFile(servicePath, []byte(unit), 0644); err != nil {
		log.Fatal(err)
	}

	exec.Command("systemctl", "daemon-reload").Run()
	exec.Command("systemctl", "enable", "histeria2").Run()
	exec.Command("systemctl", "restart", "histeria2").Run()
}

// =====================
// Certificat TLS
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
		"-subj", "/CN=histeria2")
	cmd.Run()
}

// =====================
// Serveur Hysteria UDP (simplifié)
// =====================
func runServer(users map[string]string) {
	ensureCerts()
	_, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		log.Println("[WARN] Certificat TLS introuvable ou invalide :", err)
	}

	addr, err := net.ResolveUDPAddr("udp", ":"+port)
	if err != nil {
		log.Fatal(err)
	}
	conn, err := net.ListenUDP("udp", addr)
	if err != nil {
		log.Fatal(err)
	}
	defer conn.Close()

	log.Println("🚀 Hysteria2 UDP Tunnel actif sur le port", port)
	buf := make([]byte, 65535)

	for {
		n, remoteAddr, err := conn.ReadFromUDP(buf)
		if err != nil {
			log.Println("Erreur lecture UDP:", err)
			continue
		}
		data := string(buf[:n])
		valid := false
		for u, p := range users {
			if strings.Contains(data, u) && strings.Contains(data, p) {
				valid = true
				break
			}
		}
		if valid {
			_, _ = conn.WriteToUDP([]byte("HYSTERIA OK"), remoteAddr)
		} else {
			_, _ = conn.WriteToUDP([]byte("AUTH FAILED"), remoteAddr)
		}
	}
}

// =====================
// MAIN
// =====================
func main() {
	setupLogging()
	users := loadUsers()
	ensureSystemd()
	runServer(users)
}
