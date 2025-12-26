// ================================================================
// sshws.go — WebSocket → SSH (TCP) Proxy complet et sécurisé
// Auteur : @mahboub, adapté par @vpsplus71
// Licence : MIT
// Version : 1.4.2 (fix DOMAIN parsing conforme à la doc Go)
// ================================================================

package main

import (
\t"bufio"
\t"crypto/sha1"
\t"encoding/base64"
\t"flag"
\t"fmt"
\t"io"
\t"log"
\t"net"
\t"net/http"
\t"os"
\t"os/exec"
\t"os/user"
\t"path/filepath"
\t"strings"
\t"time"
)

// Constantes globales
const (
\twsGUID       = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
\tkighmuInfo   = ".kighmu_info"
\tsystemdPath  = "/etc/systemd/system/sshws.service"
\tlogDir       = "/var/log/sshws"
\tlogFile      = "/var/log/sshws/sshws.log"
\tmaxLogSize   = 5 * 1024 * 1024 // 5 Mo
)

// =====================================================================
// 🔐 Fonctions utilitaires
// =====================================================================

// acceptKey : calcule Sec-WebSocket-Accept pour le handshake WebSocket
func acceptKey(key string) string {
\th := sha1.New()
\th.Write([]byte(key + wsGUID))
\treturn base64.StdEncoding.EncodeToString(h.Sum(nil))
}

// getKighmuDomain : récupère DOMAIN depuis ~/.kighmu_info
func getKighmuDomain() string {
\tusr, err := user.Current()
\tif err != nil {
\t\treturn ""
\t}
\tfile := fmt.Sprintf("%s/%s", usr.HomeDir, kighmuInfo)
\tf, err := os.Open(file)
\tif err != nil {
\t\treturn ""
\t}
\tdefer f.Close()

\tscanner := bufio.NewScanner(f)
\tfor scanner.Scan() {
\t\tline := strings.TrimSpace(scanner.Text())
\t\tif strings.HasPrefix(line, "DOMAIN=") {
\t\t\t// ✅ Version correcte et recommandée
\t\t\treturn strings.Trim(strings.SplitN(line, "=", 2)[1], "" ")
\t\t}
\t}
\treturn ""
}

// setupLogging : crée ou fait pivoter le fichier de log
func setupLogging() {
\t_ = os.MkdirAll(logDir, 0755)
\tif info, err := os.Stat(logFile); err == nil && info.Size() > maxLogSize {
\t\trotated := fmt.Sprintf("%s.%d", logFile, time.Now().Unix())
\t\t_ = os.Rename(logFile, rotated)
\t}
\tf, err := os.OpenFile(logFile, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
\tif err != nil {
\t\tlog.Fatalf("Erreur ouverture log : %v", err)
\t}
\tmw := io.MultiWriter(os.Stdout, f)
\tlog.SetOutput(mw)
\tlog.SetFlags(log.Ldate | log.Ltime | log.Lshortfile)
}

// openFirewallPort : autorise un port via iptables, avec persistance
func openFirewallPort(port string) {
\tlog.Printf("🔐 Application des règles iptables sur le port %s ...", port)
\tcheck := exec.Command("iptables", "-C", "INPUT", "-p", "tcp", "--dport", port, "-j", "ACCEPT")
\tif err := check.Run(); err != nil {
\t\tadd := exec.Command("iptables", "-I", "INPUT", "-p", "tcp", "--dport", port, "-j", "ACCEPT")
\t\tif e := add.Run(); e == nil {
\t\t\tlog.Printf("✅ Port %s ouvert via iptables", port)
\t\t\tif _, err := exec.LookPath("netfilter-persistent"); err == nil {
\t\t\t\texec.Command("netfilter-persistent", "save").Run()
\t\t\t\tlog.Println("💾 Règles iptables sauvegardées (netfilter-persistent).")
\t\t\t}
\t\t} else {
\t\t\tlog.Printf("⚠️ Impossible d'ajouter la règle iptables : %v", e)
\t\t}
\t} else {
\t\tlog.Printf("ℹ️ Règle iptables déjà existante sur le port %s", port)
\t}
}

// =====================================================================
// 🧩 Gestion du handshake et proxy
// =====================================================================

func handleUpgrade(targetAddr string, w http.ResponseWriter, r *http.Request) {
\tdomain := getKighmuDomain()

\t// Vérifie que le Host correspond au domaine autorisé
\tif domain != "" && !strings.EqualFold(r.Host, domain) {
\t\tlog.Printf("🚫 Connexion refusée : Host (%s) ≠ Domaine (%s)", r.Host, domain)
\t\thttp.Error(w, "Forbidden", http.StatusForbidden)
\t\treturn
\t}

\tif !strings.Contains(strings.ToLower(r.Header.Get("Connection")), "upgrade") ||
\t\t!strings.EqualFold(r.Header.Get("Upgrade"), "websocket") {
\t\thttp.Error(w, "upgrade required", http.StatusBadRequest)
\t\treturn
\t}

\thj, ok := w.(http.Hijacker)
\tif !ok {
\t\thttp.Error(w, "hijacking non supporté", http.StatusInternalServerError)
\t\treturn
\t}
\tconn, buf, err := hj.Hijack()
\tif err != nil {
\t\tlog.Printf("Erreur hijack : %v", err)
\t\treturn
\t}
\tdefer buf.Flush()

\tkey := r.Header.Get("Sec-WebSocket-Key")
\tresp := fmt.Sprintf("HTTP/1.1 101 Switching Protocols
"+
\t\t"Upgrade: websocket
"+
\t\t"Connection: Upgrade
")
\tif key != "" {
\t\tresp += fmt.Sprintf("Sec-WebSocket-Accept: %s
", acceptKey(key))
\t}
\tresp += "X-Powered-By: sshws-proxy

"

\tif _, err := buf.WriteString(resp); err != nil {
\t\tconn.Close()
\t\treturn
\t}
\t_ = buf.Flush()

\tremote, err := net.DialTimeout("tcp", targetAddr, 10*time.Second)
\tif err != nil {
\t\tlog.Printf("Erreur SSH (%s) : %v", targetAddr, err)
\t\tconn.Close()
\t\treturn
\t}

\tgo func() {
\t\tdefer conn.Close()
\t\tdefer remote.Close()
\t\t_, _ = io.Copy(remote, conn)
\t}()
\tgo func() {
\t\tdefer conn.Close()
\t\tdefer remote.Close()
\t\t_, _ = io.Copy(conn, remote)
\t}()

\tlog.Printf("✅ Connexion WS validée (%s → %s)", r.Host, targetAddr)
}

// =====================================================================
// ⚙️ Création du service systemd
// =====================================================================

func createSystemdFile(listen, targetHost, targetPort string) {
\tif _, err := os.Stat(systemdPath); err == nil {
\t\treturn
\t}
\tcontent := fmt.Sprintf(`[Unit]
Description=SSH WebSocket Tunnel Service
After=network.target

[Service]
ExecStart=/usr/local/bin/sshws -listen %s -target-host %s -target-port %s
Restart=always
User=root

[Install]
WantedBy=multi-user.target
`, listen, targetHost, targetPort)

\tdir := filepath.Dir(systemdPath)
\t_ = os.MkdirAll(dir, 0755)
\tif err := os.WriteFile(systemdPath, []byte(content), 0644); err != nil {
\t\tlog.Printf("Erreur création service systemd : %v", err)
\t\treturn
\t}
\tlog.Printf("✅ Service systemd créé : %s", systemdPath)
\tlog.Println("Active-le via : systemctl enable sshws && systemctl start sshws")
}

// =====================================================================
// 🚀 MAIN
// =====================================================================

func main() {
\tlisten := flag.String("listen", "80", "Port d'écoute WS (ex : 80)")
\ttargetHost := flag.String("target-host", "127.0.0.1", "Hôte SSH cible")
\ttargetPort := flag.String("target-port", "22", "Port SSH cible")
\tflag.Parse()

\tsetupLogging()

\tdomain := getKighmuDomain()
\ttargetAddr := net.JoinHostPort(*targetHost, *targetPort)

\tlog.Println("==============================================")
\tlog.Println("🚀 Démarrage du Tunnel SSH WebSocket (SSHWS)")
\tif domain != "" {
\t\tlog.Printf("🌐 Domaine autorisé : %s", domain)
\t}
\tlog.Printf("🎯 Cible SSH : %s", targetAddr)
\tlog.Printf("🌀 Port WebSocket : %s", *listen)
\tlog.Println("==============================================")

\topenFirewallPort(*listen)
\tcreateSystemdFile(*listen, *targetHost, *targetPort)

\thttp.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
\t\tif strings.EqualFold(r.Header.Get("Upgrade"), "websocket") {
\t\t\thandleUpgrade(targetAddr, w, r)
\t\t\treturn
\t\t}
\t\tw.Header().Set("Content-Type", "text/plain")
\t\t_, _ = w.Write([]byte("SSHWS Proxy actif.
"))
\t})

\tserver := &http.Server{
\t\tAddr:         ":" + *listen,
\t\tReadTimeout:  10 * time.Second,
\t\tWriteTimeout: 10 * time.Second,
\t\tIdleTimeout:  90 * time.Second,
\t}

\tif err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
\t\tlog.Fatalf("Erreur serveur : %v", err)
\t}
}
