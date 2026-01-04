// ================================================================
// udp-custom.go — Tunnel UDP Custom (HTTP Custom compatible)
// Ubuntu 20.04 | Go 1.13+
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
	"time"
)

const (
	logDir      = "/var/log/udp-custom"
	logFile     = "/var/log/udp-custom/udp-custom.log"
	servicePath = "/etc/systemd/system/udp-custom.service"
	binPath     = "/usr/local/bin/udp-custom"
	defaultUDP  = "54000"
	maxLogSize  = 10 * 1024 * 1024 // 10 MB
)

// =====================
// Logging avec rotation simple
// =====================
func setupLogging() {
	_ = os.MkdirAll(logDir, 0755)

	// Rotation simple : renommer si trop grand
	if fi, err := os.Stat(logFile); err == nil && fi.Size() > maxLogSize {
		os.Rename(logFile, logFile+"."+time.Now().Format("20060102-150405"))
	}

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
Description=UDP Custom Tunnel compatible HTTP Custom
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

	if err := os.WriteFile(servicePath, []byte(unit), 0644); err != nil {
		log.Printf("[SYSTEMD] Erreur écriture fichier service: %v", err)
		return
	}

	// Reload et activation systemd
	exec.Command("systemctl", "daemon-reload").Run()
	exec.Command("systemctl", "enable", "udp-custom").Run()
	exec.Command("systemctl", "restart", "udp-custom").Run()
	log.Println("[SYSTEMD] Service systemd créé et lancé")
}

// =====================
// Ouverture port UDP avec gestion du verrou iptables
// =====================
func setupIptables(udpPort string) {
	runIptables := func(args ...string) error {
		cmd := exec.Command("iptables", args...)
		return cmd.Run()
	}

	// INPUT
	if err := runIptables("-C", "INPUT", "-p", "udp", "--dport", udpPort, "-j", "ACCEPT"); err != nil {
		runIptables("-I", "INPUT", "-p", "udp", "--dport", udpPort, "-j", "ACCEPT")
	}
	// OUTPUT
	if err := runIptables("-C", "OUTPUT", "-p", "udp", "--sport", udpPort, "-j", "ACCEPT"); err != nil {
		runIptables("-I", "OUTPUT", "-p", "udp", "--sport", udpPort, "-j", "ACCEPT")
	}

	// Sauvegarde iptables (avec -w pour éviter les verrous)
	exec.Command("sh", "-c", fmt.Sprintf("iptables-save -w > /etc/iptables/rules.v4")).Run()
	log.Printf("[IPTABLES] Port UDP %s ouvert et règles sauvegardées", udpPort)
}

// =====================
// Tunnel UDP pur
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
	log.Printf("[UDP] Tunnel UDP actif sur %s (HTTP Custom compatible)", udpPort)

	buf := make([]byte, 65535)
	for {
		n, remoteAddr, err := conn.ReadFromUDP(buf)
		if err != nil {
			log.Printf("[UDP][ERREUR] Lecture depuis %s échouée: %v", remoteAddr, err)
			continue
		}

		log.Printf("[UDP] Paquet reçu de %s:%d, %d bytes", remoteAddr.IP, remoteAddr.Port, n)
		log.Printf("[SESSION] %s:%d traité à %s", remoteAddr.IP, remoteAddr.Port, time.Now().Format(time.RFC3339))

		_, err = conn.WriteToUDP(buf[:n], remoteAddr)
		if err != nil {
			log.Printf("[UDP][ERREUR] Écriture vers %s:%d échouée: %v", remoteAddr.IP, remoteAddr.Port, err)
		}
	}
}

// =====================
// MAIN
// =====================
func main() {
	udpPort := flag.String("udp", defaultUDP, "UDP Tunnel port")
	flag.Parse()

	setupLogging()
	setupIptables(*udpPort)
	ensureSystemd(*udpPort)
	startUDPTunnel(*udpPort)
}
