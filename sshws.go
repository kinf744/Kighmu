// ================================================================
// sshws.go — WebSocket → SSH (TCP) Proxy complet et sécurisé
// Auteur : @mahboub, adapté par @vpsplus71
// Licence : MIT
// Version : 1.4.3
// ================================================================

package main

import (
	"bufio"
	"crypto/sha1"
	"encoding/base64"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strings"
	"time"
)

// Constantes globales
const (
	wsGUID      = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	kighmuInfo  = ".kighmu_info"
	systemdPath = "/etc/systemd/system/sshws.service"
	logDir      = "/var/log/sshws"
	logFile     = "/var/log/sshws/sshws.log"
	maxLogSize  = 5 * 1024 * 1024 // 5 Mo
)

// ================================================================
// 🔐 Fonctions utilitaires
// ================================================================

// acceptKey : calcule Sec-WebSocket-Accept pour le handshake WebSocket
func acceptKey(key string) string {
	h := sha1.New()
	h.Write([]byte(key + wsGUID))
	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}

// getKighmuDomain : récupère DOMAIN depuis ~/.kighmu_info
func getKighmuDomain() string {
	usr, err := user.Current()
	if err != nil {
		return ""
	}
	file := fmt.Sprintf("%s/%s", usr.HomeDir, kighmuInfo)
	f, err := os.Open(file)
	if err != nil {
		return ""
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.HasPrefix(line, "DOMAIN=") {
			return strings.Trim(strings.SplitN(line, "=", 2)[1], `"`)
		}
	}
	return ""
}

// setupLogging : crée ou fait pivoter le fichier de log
func setupLogging() {
	_ = os.MkdirAll(logDir, 0755)
	if info, err := os.Stat(logFile); err == nil && info.Size() > maxLogSize {
		rotated := fmt.Sprintf("%s.%d", logFile, time.Now().Unix())
		_ = os.Rename(logFile, rotated)
	}
	f, err := os.OpenFile(logFile, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		log.Fatalf("Erreur ouverture log : %v", err)
	}
	mw := io.MultiWriter(os.Stdout, f)
	log.SetOutput(mw)
	log.SetFlags(log.Ldate | log.Ltime | log.Lshortfile)
}

// openFirewallPort : autorise le port via iptables, avec persistance
func openFirewallPort(port string) {
	log.Printf("🔐 Application des règles iptables sur le port %s ...", port)
	check := exec.Command("iptables", "-C", "INPUT", "-p", "tcp", "--dport", port, "-j", "ACCEPT")
	if err := check.Run(); err != nil {
		add := exec.Command("iptables", "-I", "INPUT", "-p", "tcp", "--dport", port, "-j", "ACCEPT")
		if e := add.Run(); e == nil {
			log.Printf("✅ Port %s ouvert via iptables", port)
			if _, err := exec.LookPath("netfilter-persistent"); err == nil {
				exec.Command("netfilter-persistent", "save").Run()
				log.Println("💾 Règles iptables sauvegardées (netfilter-persistent).")
			}
		} else {
			log.Printf("⚠️ Impossible d'ajouter la règle iptables : %v", e)
		}
	} else {
		log.Printf("ℹ️ Règle iptables déjà existante sur le port %s", port)
	}
}

// ================================================================
// 🧩 Gestion du handshake et proxy
// ================================================================

func handleUpgrade(targetAddr string, w http.ResponseWriter, r *http.Request) {
	domain := getKighmuDomain()

	// Vérifie que le Host correspond au domaine autorisé
	if domain != "" && !strings.EqualFold(r.Host, domain) {
		log.Printf("🚫 Connexion refusée : Host (%s) ≠ Domaine (%s)", r.Host, domain)
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	if !strings.Contains(strings.ToLower(r.Header.Get("Connection")), "upgrade") ||
		!strings.EqualFold(r.Header.Get("Upgrade"), "websocket") {
		http.Error(w, "upgrade required", http.StatusBadRequest)
		return
	}

	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "hijacking non supporté", http.StatusInternalServerError)
		return
	}
	conn, buf, err := hj.Hijack()
	if err != nil {
		log.Printf("Erreur hijack : %v", err)
		return
	}
	defer buf.Flush()

	key := r.Header.Get("Sec-WebSocket-Key")
	resp := fmt.Sprintf(`HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: %s
X-Powered-By: sshws-proxy
`, acceptKey(key))

	if _, err := buf.WriteString(resp); err != nil {
		conn.Close()
		return
	}
	buf.Flush()

	remote, err := net.DialTimeout("tcp", targetAddr, 10*time.Second)
	if err != nil {
		log.Printf("Erreur SSH (%s) : %v", targetAddr, err)
		conn.Close()
		return
	}

	go func() {
		defer conn.Close()
		defer remote.Close()
		_, _ = io.Copy(remote, conn)
	}()
	go func() {
		defer conn.Close()
		defer remote.Close()
		_, _ = io.Copy(conn, remote)
	}()

	log.Printf("✅ Connexion WS validée (%s → %s)", r.Host, targetAddr)
}

// ================================================================
// ⚙️ Création du service systemd
// ================================================================

func createSystemdFile(listen, targetHost, targetPort string) {
	if _, err := os.Stat(systemdPath); err == nil {
		return
	}
	content := fmt.Sprintf(`[Unit]
Description=SSH WebSocket Tunnel Service
After=network.target

[Service]
ExecStart=/usr/local/bin/sshws -listen %s -target-host %s -target-port %s
Restart=always
User=root

[Install]
WantedBy=multi-user.target
`, listen, targetHost, targetPort)

	dir := filepath.Dir(systemdPath)
	_ = os.MkdirAll(dir, 0755)
	if err := os.WriteFile(systemdPath, []byte(content), 0644); err != nil {
		log.Printf("Erreur création service systemd : %v", err)
		return
	}
	log.Printf("✅ Service systemd créé : %s", systemdPath)
	log.Println("Active-le via : systemctl enable sshws && systemctl start sshws")
}

// ================================================================
// 🚀 MAIN
// ================================================================

func main() {
	listen := flag.String("listen", "80", "Port d'écoute WS (ex : 80)")
	targetHost := flag.String("target-host", "127.0.0.1", "Hôte SSH cible")
	targetPort := flag.String("target-port", "22", "Port SSH cible")
	flag.Parse()

	setupLogging()

	domain := getKighmuDomain()
	targetAddr := net.JoinHostPort(*targetHost, *targetPort)

	log.Println("==============================================")
	log.Println("🚀 Démarrage du Tunnel SSH WebSocket (SSHWS)")
	if domain != "" {
		log.Printf("🌐 Domaine autorisé : %s", domain)
	}
	log.Printf("🎯 Cible SSH : %s", targetAddr)
	log.Printf("🌀 Port WebSocket : %s", *listen)
	log.Println("==============================================")

	openFirewallPort(*listen)
	createSystemdFile(*listen, *targetHost, *targetPort)

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if strings.EqualFold(r.Header.Get("Upgrade"), "websocket") {
			handleUpgrade(targetAddr, w, r)
			return
		}
		w.Header().Set("Content-Type", "text/plain")
		_, _ = w.Write([]byte("SSHWS Proxy actif.\n"))
	})

	server := &http.Server{
		Addr:         ":" + *listen,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  90 * time.Second,
	}

	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Erreur serveur : %v", err)
	}
}
