// ================================================================
// udp-custom.go — Tunnel UDP Custom (HTTP Custom compatible)
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
	"time"
)

const (
	logDir      = "/var/log/udp-custom"
	logFile     = "/var/log/udp-custom/udp-custom.log"
	servicePath = "/etc/systemd/system/udp-custom.service"
	binPath     = "/usr/local/bin/udp-custom"
	defaultUDP  = "54000"
)

// Logging avec création automatique du dossier
func setupLogging() {
	_ = os.MkdirAll(logDir, 0755)
	f, err := os.OpenFile(logFile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		log.Fatal(err)
	}
	log.SetOutput(io.MultiWriter(os.Stdout, f))
	log.SetFlags(log.LstdFlags | log.Lshortfile)
}

// Création et lancement service systemd
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

	f, err := os.OpenFile(servicePath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if err != nil {
		log.Printf("[SYSTEMD] Erreur écriture fichier service: %v", err)
		return
	}
	defer f.Close()
	_, _ = f.Write([]byte(unit))

	// Reload et activation systemd
	exec.Command("systemctl", "daemon-reload").Run()
	exec.Command("systemctl", "enable", "udp-custom").Run()
	exec.Command("systemctl", "restart", "udp-custom").Run()
	log.Println("[SYSTEMD] Service systemd créé et lancé")
}

// Ouverture du port UDP via iptables
func setupIptables(udpPort string) {
	// Vérifie si la règle existe déjà
	checkInput := exec.Command("iptables", "-C", "INPUT", "-p", "udp", "--dport", udpPort, "-j", "ACCEPT")
	if checkInput.Run() != nil {
		exec.Command("iptables", "-I", "INPUT", "-p", "udp", "--dport", udpPort, "-j", "ACCEPT").Run()
	}

	checkOutput := exec.Command("iptables", "-C", "OUTPUT", "-p", "udp", "--sport", udpPort, "-j", "ACCEPT")
	if checkOutput.Run() != nil {
		exec.Command("iptables", "-I", "OUTPUT", "-p", "udp", "--sport", udpPort, "-j", "ACCEPT").Run()
	}

	// Sauvegarde iptables
	if _, err := os.Stat("/etc/iptables/rules.v4"); err == nil {
		exec.Command("sh", "-c", "iptables-save > /etc/iptables/rules.v4").Run()
	} else {
		os.MkdirAll("/etc/iptables", 0755)
		exec.Command("sh", "-c", "iptables-save > /etc/iptables/rules.v4").Run()
	}

	log.Printf("[IPTABLES] Port UDP %s ouvert et règles sauvegardées", udpPort)
}

// Tunnel UDP pur
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
			log.Printf("[UDP] Erreur lecture depuis %s: %v", remoteAddr, err)
			continue
		}
		log.Printf("[UDP] Paquet reçu de %s, %d bytes", remoteAddr, n)

		// Echo pour compatibilité test client
		_, err = conn.WriteToUDP(buf[:n], remoteAddr)
		if err != nil {
			log.Printf("[UDP] Erreur écriture vers %s: %v", remoteAddr, err)
		}

		// Session log
		log.Printf("[SESSION] %s:%d traité à %s", remoteAddr.IP, remoteAddr.Port, time.Now().Format(time.RFC3339))
	}
}

func main() {
	udpPort := flag.String("udp", defaultUDP, "UDP Tunnel port")
	flag.Parse()

	setupLogging()
	setupIptables(*udpPort)
	ensureSystemd(*udpPort)
	startUDPTunnel(*udpPort)
}
