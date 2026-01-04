// ================================================================
// udp-http-custom.go — Tunnel UDP Custom compatible HTTP Custom
// Ubuntu 20.04 | Go 1.13+
// Auteur : @kighmu
// Licence : MIT
// ================================================================

package main

import (
	"encoding/base64"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"time"
)

const (
	logDir      = "/var/log/udp-http-custom"
	logFile     = "/var/log/udp-http-custom/udp-http-custom.log"
	servicePath = "/etc/systemd/system/udp-http-custom.service"
	binPath     = "/usr/local/bin/udp-http-custom"
	defaultUDP  = "54000"
	defaultHTTP = "85"
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
func ensureSystemd(udpPort, httpPort string) {
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
ExecStart=%s -udp %s -http %s
Restart=always
RestartSec=2
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
`, binPath, udpPort, httpPort)

	f, err := os.OpenFile(servicePath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if err != nil {
		log.Printf("[SYSTEMD] Erreur écriture fichier service: %v", err)
		return
	}
	defer f.Close()
	_, _ = f.Write([]byte(unit))

	exec.Command("systemctl", "daemon-reload").Run()
	exec.Command("systemctl", "enable", "udp-http-custom").Run()
	exec.Command("systemctl", "restart", "udp-http-custom").Run()
	log.Println("[SYSTEMD] Service systemd créé et lancé")
}

// =====================
// Ouverture port UDP/TCP via iptables
// =====================
func setupIptables(udpPort, httpPort string) {
	exec.Command("iptables", "-I", "INPUT", "-p", "udp", "--dport", udpPort, "-j", "ACCEPT").Run()
	exec.Command("iptables", "-I", "OUTPUT", "-p", "udp", "--sport", udpPort, "-j", "ACCEPT").Run()
	exec.Command("iptables", "-I", "INPUT", "-p", "tcp", "--dport", httpPort, "-j", "ACCEPT").Run()
	exec.Command("iptables", "-I", "OUTPUT", "-p", "tcp", "--sport", httpPort, "-j", "ACCEPT").Run()

	// Sauvegarde iptables
	os.MkdirAll("/etc/iptables", 0755)
	exec.Command("sh", "-c", "iptables-save > /etc/iptables/rules.v4").Run()
	log.Printf("[IPTABLES] Ports UDP %s et TCP %s ouverts", udpPort, httpPort)
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
	log.Printf("[UDP] Tunnel UDP actif sur %s", udpPort)

	buf := make([]byte, 65535)
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

		log.Printf("[SESSION] %s:%d traité à %s", remoteAddr.IP, remoteAddr.Port, time.Now().Format(time.RFC3339))
	}
}

// =====================
// Serveur HTTP Custom + WebSocket
// =====================
func startHTTPServer(httpPort, udpPort string) {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "GET" && r.Header.Get("Upgrade") == "websocket" {
			handleWebSocket(w, r, udpPort)
			return
		}
		w.Header().Set("Content-Type", "text/html")
		w.WriteHeader(200)
		fmt.Fprintf(w, "<html><body><h2>UDP Custom Tunnel Actif</h2></body></html>")
	})

	log.Printf("[HTTP] Serveur HTTP Custom actif sur %s", httpPort)
	if err := http.ListenAndServe(":"+httpPort, nil); err != nil {
		log.Fatalf("[HTTP] Erreur serveur HTTP: %v", err)
	}
}

// =====================
// WebSocket → UDP
// =====================
func handleWebSocket(w http.ResponseWriter, r *http.Request, udpPort string) {
	hijacker, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "Hijacking non supporté", http.StatusInternalServerError)
		return
	}

	conn, _, err := hijacker.Hijack()
	if err != nil {
		log.Printf("[WS] Erreur hijack: %v", err)
		return
	}

	key := r.Header.Get("Sec-WebSocket-Key")
	if key == "" {
		key = "dGhlIHNhbXBsZSBub25jZQ=="
	}
	acceptKey := base64.StdEncoding.EncodeToString([]byte(key))
	resp := "HTTP/1.1 101 Switching Protocols\r\n" +
		"Upgrade: websocket\r\n" +
		"Connection: Upgrade\r\n" +
		"Sec-WebSocket-Accept: " + acceptKey + "\r\n\r\n"
	_, _ = conn.Write([]byte(resp))

	udpAddr, _ := net.ResolveUDPAddr("udp", "127.0.0.1:"+udpPort)
	udpConn, _ := net.DialUDP("udp", nil, udpAddr)

	go func() { _, _ = io.Copy(udpConn, conn) }()
	go func() { _, _ = io.Copy(conn, udpConn) }()
}

// =====================
// MAIN
// =====================
func main() {
	udpPort := flag.String("udp", defaultUDP, "UDP Tunnel port")
	httpPort := flag.String("http", defaultHTTP, "HTTP Custom port")
	flag.Parse()

	setupLogging()
	setupIptables(*udpPort, *httpPort)
	ensureSystemd(*udpPort, *httpPort)

	go startUDPTunnel(*udpPort)
	startHTTPServer(*httpPort, *udpPort)
}
