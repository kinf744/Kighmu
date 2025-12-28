// ================================================================
// histeria2.go — Tunnel Hysteria 2 (UDP) avec TLS + Obfuscation
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
	"path/filepath"
	"strings"
)

// =====================
// Constantes
// =====================
const (
	usersFile   = "/etc/kighmu/users.list"
	infoFile    = ".kighmu_info"

	binPath     = "/usr/local/bin/histeria2"
	servicePath = "/etc/systemd/system/histeria2.service"

	logDir  = "/var/log/histeria2"
	logFile = "/var/log/histeria2/histeria2.log"

	certDir  = "/etc/ssl/histeria2"
	certFile = "/etc/ssl/histeria2/cert.pem"
	keyFile  = "/etc/ssl/histeria2/key.pem"

	port = "22000"
)

// =====================
// Utils fichiers
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
// Charger DOMAIN depuis ~/.kighmu_info
// =====================
func loadDomain() string {
	home, _ := os.UserHomeDir()
	path := filepath.Join(home, infoFile)

	file, err := os.Open(path)
	if err != nil {
		log.Fatal("[ERREUR] Fichier ~/.kighmu_info introuvable")
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.HasPrefix(line, "DOMAIN=") {
			return strings.Trim(strings.SplitN(line, "=", 2)[1], "\"")
		}
	}

	log.Fatal("[ERREUR] DOMAIN non défini dans ~/.kighmu_info")
	return ""
}

// =====================
// Charger utilisateurs
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
			users[parts[0]] = parts[1] // username | password
		}
	}
	return users
}

// =====================
// Obfuscation XOR (username)
// =====================
func xorObfuscate(data []byte, key string) []byte {
	k := []byte(key)
	out := make([]byte, len(data))
	for i := range data {
		out[i] = data[i] ^ k[i%len(k)]
	}
	return out
}

// =====================
// Certificat TLS lié au DOMAINE
// =====================
func ensureCerts(domain string) {
	if _, err := os.Stat(certFile); err == nil {
		return
	}

	_ = os.MkdirAll(certDir, 0700)

	cmd := exec.Command(
		"openssl", "req",
		"-x509", "-newkey", "rsa:2048",
		"-keyout", keyFile,
		"-out", certFile,
		"-days", "365",
		"-nodes",
		"-subj", "/CN="+domain,
		"-addext", "subjectAltName=DNS:"+domain,
	)
	cmd.Run()
}

// =====================
// Service systemd
// =====================
func ensureSystemd() {
	if _, err := os.Stat(servicePath); err == nil {
		return
	}

	unit := fmt.Sprintf(`[Unit]
Description=Hysteria 2 UDP Tunnel (Kighmu)
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
// Serveur Hysteria 2 UDP
// =====================
func runServer(users map[string]string, domain string) {
	ensureCerts(domain)

	_, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		log.Fatal("Certificat TLS invalide :", err)
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

	log.Println("🚀 Hysteria 2 UDP actif sur", domain+":"+port)

	buf := make([]byte, 65535)

	for {
		n, remoteAddr, err := conn.ReadFromUDP(buf)
		if err != nil {
			log.Println("Erreur UDP:", err)
			continue
		}

		raw := buf[:n]
		authorized := false

		for user, pass := range users {
			payload := string(xorObfuscate(raw, user))
			if strings.Contains(payload, pass) {
				authorized = true
				break
			}
		}

		if authorized {
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
	domain := loadDomain()
	users := loadUsers()
	ensureSystemd()
	runServer(users, domain)
}
