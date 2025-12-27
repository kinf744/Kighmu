// ================================================================
// sshws.go — WebSocket → SSH (TCP) Proxy (HTTP Custom compatible)
// Auteur : @kighmu
// Patch : compatibilité SSH Custom /
// Licence : MIT
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

// =====================
// Constantes
// =====================

const (
	wsGUID      = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	kighmuInfo  = ".kighmu_info"
	systemdPath = "/etc/systemd/system/sshws.service"
	logDir      = "/var/log/sshws"
	logFile     = "/var/log/sshws/sshws.log"
	maxLogSize  = 5 * 1024 * 1024
)

// =====================
// Utils
// =====================

func acceptKey(key string) string {
	h := sha1.New()
	h.Write([]byte(key + wsGUID))
	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}

func getKighmuDomain() string {
	usr, err := user.Current()
	if err != nil {
		return ""
	}
	f, err := os.Open(filepath.Join(usr.HomeDir, kighmuInfo))
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
// Logging
// =====================

func setupLogging() {
	_ = os.MkdirAll(logDir, 0755)

	if info, err := os.Stat(logFile); err == nil && info.Size() > maxLogSize {
		_ = os.Rename(logFile, logFile+"."+fmt.Sprint(time.Now().Unix()))
	}

	f, err := os.OpenFile(logFile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		log.Fatal(err)
	}
	log.SetOutput(io.MultiWriter(os.Stdout, f))
	log.SetFlags(log.LstdFlags | log.Lshortfile)
}

// =====================
// Firewall
// =====================

func openFirewallPort(port string) {
	cmd := exec.Command("iptables", "-C", "INPUT", "-p", "tcp", "--dport", port, "-j", "ACCEPT")
	if cmd.Run() == nil {
		return
	}
	exec.Command("iptables", "-I", "INPUT", "-p", "tcp", "--dport", port, "-j", "ACCEPT").Run()
	exec.Command("netfilter-persistent", "save").Run()
}

// =====================
// WebSocket Handler
// =====================

func handleUpgrade(targetAddr string, w http.ResponseWriter, r *http.Request) {

	// --- Vérification Host tolérante ---
	domain := getKighmuDomain()
	host := r.Host
	if strings.Contains(host, ":") {
		host, _, _ = net.SplitHostPort(host)
	}

	if domain != "" && !strings.EqualFold(host, domain) {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	// --- Vérification Upgrade tolérante ---
	connHeader := strings.ToLower(
		r.Header.Get("Connection") + r.Header.Get("Proxy-Connection"),
	)

	if !strings.Contains(connHeader, "upgrade") ||
		!strings.EqualFold(r.Header.Get("Upgrade"), "websocket") {
		http.Error(w, "Upgrade Required", http.StatusBadRequest)
		return
	}

	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "Hijack not supported", 500)
		return
	}

	conn, buf, err := hj.Hijack()
	if err != nil {
		return
	}

	// --- Sec-WebSocket-Key fallback ---
	key := r.Header.Get("Sec-WebSocket-Key")
	if key == "" {
		key = "dGhlIHNhbXBsZSBub25jZQ=="
	}

	resp := fmt.Sprintf(
		"HTTP/1.1 101 Switching Protocols\r\n"+
			"Upgrade: websocket\r\n"+
			"Connection: Upgrade\r\n"+
			"Sec-WebSocket-Accept: %s\r\n"+
			"\r\n",
		acceptKey(key),
	)

	buf.WriteString(resp)
	buf.Flush()

	remote, err := net.Dial("tcp", targetAddr)
	if err != nil {
		conn.Close()
		return
	}

	go func() {
		defer conn.Close()
		defer remote.Close()
		io.Copy(remote, conn)
	}()
	go func() {
		defer conn.Close()
		defer remote.Close()
		io.Copy(conn, remote)
	}()
}

// =====================
// systemd
// =====================

func createSystemdFile(listen, host, port string) {
	if _, err := os.Stat(systemdPath); err == nil {
		return
	}

	content := fmt.Sprintf(`[Unit]
Description=SSH WebSocket Tunnel
After=network.target

[Service]
ExecStart=/usr/local/bin/sshws -listen %s -target-host %s -target-port %s
Restart=always

[Install]
WantedBy=multi-user.target
`, listen, host, port)

	os.WriteFile(systemdPath, []byte(content), 0644)
}

// =====================
// MAIN
// =====================

func main() {
	listen := flag.String("listen", "80", "WS listen port")
	targetHost := flag.String("target-host", "127.0.0.1", "SSH host")
	targetPort := flag.String("target-port", "22", "SSH port")
	flag.Parse()

	setupLogging()
	openFirewallPort(*listen)
	createSystemdFile(*listen, *targetHost, *targetPort)

	targetAddr := net.JoinHostPort(*targetHost, *targetPort)

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if strings.EqualFold(r.Header.Get("Upgrade"), "websocket") {
			handleUpgrade(targetAddr, w, r)
			return
		}
		w.Write([]byte("SSHWS OK\n"))
	})

	log.Println("SSHWS HTTP Custom compatible démarré sur le port", *listen)
	http.ListenAndServe(":"+*listen, nil)
}
