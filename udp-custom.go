// ================================================================
// udp-custom.go — UDP Custom Tunnel + HTTP Custom
// Ubuntu 20.04 | Go 1.13
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
)

// =====================
// Constantes et chemins
// =====================
const (
	logDir      = "/var/log/udp-http-tunnel"
	logFile     = "/var/log/udp-http-tunnel/udp-http-tunnel.log"
	servicePath = "/etc/systemd/system/udp-http-tunnel.service"
	binPath     = "/usr/local/bin/udp-http-tunnel"
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
// Service systemd compatible Go 1.13
// =====================
func ensureSystemd(httpPort, udpPort string) {
	if _, err := os.Stat(servicePath); err == nil {
		return
	}

	unit := fmt.Sprintf(`[Unit]
Description=UDP-over-HTTP Custom Tunnel
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=%s -http %s -udp %s
Restart=always
RestartSec=2
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
`, binPath, httpPort, udpPort)

	// Compatible Go 1.13 : écriture manuelle du fichier
	f, err := os.OpenFile(servicePath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if err != nil {
		log.Printf("[SYSTEMD] Erreur écriture fichier service: %v", err)
		return
	}
	defer f.Close()

	_, err = f.Write([]byte(unit))
	if err != nil {
		log.Printf("[SYSTEMD] Erreur écriture contenu service: %v", err)
		return
	}

	exec.Command("systemctl", "daemon-reload").Run()
	exec.Command("systemctl", "enable", "udp-http-tunnel").Run()
	exec.Command("systemctl", "restart", "udp-http-tunnel").Run()
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
// HTTP custom + WebSocket
// =====================
func startHTTPServer(httpPort, udpPort string) {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "GET" && r.Header.Get("Upgrade") == "websocket" {
			handleWebSocket(w, r, udpPort)
			return
		}
		w.Header().Set("Content-Type", "text/html")
		w.WriteHeader(200)
		fmt.Fprintf(w, "<html><body><h2>UDP Tunnel Actif</h2></body></html>")
	})

	log.Printf("[HTTP] HTTP custom actif sur %s", httpPort)
	err := http.ListenAndServe(":"+httpPort, nil)
	if err != nil {
		log.Fatalf("[HTTP] Erreur serveur HTTP: %v", err)
	}
}

// =====================
// WebSocket pour UDP-over-TCP
// =====================
func handleWebSocket(w http.ResponseWriter, r *http.Request, udpPort string) {
	hijacker, ok := w.(http.Hijacker)
	if !ok {
		log.Println("[WS] Hijacking non supporté")
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
		log.Println("[WS] Pas de clé WebSocket fournie, valeur par défaut utilisée")
	}

	acceptKey := base64.StdEncoding.EncodeToString([]byte(key))
	resp := "HTTP/1.1 101 Switching Protocols\r\n" +
		"Upgrade: websocket\r\n" +
		"Connection: Upgrade\r\n" +
		"Sec-WebSocket-Accept: " + acceptKey + "\r\n\r\n"

	_, err = conn.Write([]byte(resp))
	if err != nil {
		log.Printf("[WS] Erreur réponse WS: %v", err)
		return
	}

	udpAddr, err := net.ResolveUDPAddr("udp", "127.0.0.1:"+udpPort)
	if err != nil {
		log.Printf("[WS] Erreur résolution UDP: %v", err)
		return
	}

	udpConn, err := net.DialUDP("udp", nil, udpAddr)
	if err != nil {
		log.Printf("[WS] Erreur dial UDP: %v", err)
		return
	}

	go func() {
		_, err := io.Copy(udpConn, conn)
		if err != nil {
			log.Printf("[WS->UDP] Erreur copie: %v", err)
		}
	}()

	go func() {
		_, err := io.Copy(conn, udpConn)
		if err != nil {
			log.Printf("[UDP->WS] Erreur copie: %v", err)
		}
	}()
}

// =====================
// MAIN
// =====================
func main() {
	udpPort := flag.String("udp", "54000", "UDP Tunnel port")
	httpPort := flag.String("http", "85", "HTTP custom port")
	flag.Parse()

	setupLogging()
	ensureSystemd(*httpPort, *udpPort)

	go startUDPTunnel(*udpPort)
	startHTTPServer(*httpPort, *udpPort)
}
