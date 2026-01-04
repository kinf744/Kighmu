// ================================================================
// udp-only.go — Tunnel UDP Custom
// Ubuntu 20.04 | Go 1.13
// Auteur : @kighmu
// Licence : MIT
// ================================================================

package main

import (
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/exec"
)

// =====================
// Constantes
// =====================
const (
	logDir     = "/var/log/udp-custom"
	logFile    = "/var/log/udp-custom/udp-custom.log"
	servicePath = "/etc/systemd/system/udp-custom.service"
	binPath     = "/usr/local/bin/udp-custom"
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
	log.SetFlags(log.LstdFlags | log.Lshortfile)
}

// =====================
// Service systemd
// =====================
func ensureSystemd(udpPort string) {
	if _, err := os.Stat(servicePath); err == nil {
		return
	}

	unit := fmt.Sprintf(`[Unit]
Description=UDP Custom Tunnel
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=%s -udp %s
Restart=always
RestartSec=2
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
`, binPath, udpPort)

	f, err := os.OpenFile(servicePath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if err != nil {
		log.Printf("[SYSTEMD] Erreur écriture fichier service: %v", err)
		return
	}
	defer f.Close()
	_, _ = f.Write([]byte(unit))

	exec.Command("systemctl", "daemon-reload").Run()
	exec.Command("systemctl", "enable", "udp-custom").Run()
	exec.Command("systemctl", "restart", "udp-custom").Run()
	log.Println("[SYSTEMD] Service systemd créé et lancé")
}

// =====================
// Tunnel UDP
// =====================
func startUDPTunnel(udpPort string) {
	addr, err := net.ResolveUDPAddr("udp", ":"+udpPort)
	if err != nil {
		log.Fatalf("[UDP] Erreur résolution adresse: %v", err)
	}

	conn, err := net.ListenUDP("udp", addr)
	if err != nil {
		log.Fatalf("[UDP] Impossible d'écouter le port %s: %v", udpPort, err)
	}
	defer conn.Close()
	log.Printf("[UDP] Tunnel actif sur %s", udpPort)

	buf := make([]byte, 4096)
	for {
		n, remoteAddr, err := conn.ReadFromUDP(buf)
		if err != nil {
			log.Printf("[UDP] Erreur lecture depuis %s: %v", remoteAddr, err)
			continue
		}
		log.Printf("[UDP] Paquet reçu de %s, %d bytes", remoteAddr, n)

		_, err = conn.WriteToUDP(buf[:n], remoteAddr)
		if err != nil {
			log.Printf("[UDP] Erreur écriture vers %s: %v", remoteAddr, err)
		}
	}
}

// =====================
// MAIN
// =====================
func main() {
	udpPort := flag.String("udp", "54000", "UDP Tunnel port")
	flag.Parse()

	setupLogging()
	ensureSystemd(*udpPort)
	startUDPTunnel(*udpPort)
}
