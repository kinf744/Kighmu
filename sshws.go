// ================================================================
// sshws.go — WebSocket + TCP/HTTP Injector → SSH
// WS + TCP tunnel on same port
// systemd auto-install
// Ubuntu 18.04 → 24.04 | Go 1.13+
// Auteur : @kighmu
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

const (
	wsGUID      = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	infoFile    = ".kighmu_info"
	binPath     = "/usr/local/bin/sshws"
	servicePath = "/etc/systemd/system/sshws.service"

	logDir  = "/var/log/sshws"
	logFile = "/var/log/sshws/sshws.log"
	maxLog  = 5 * 1024 * 1024
)

// =====================
// writeFile (Go 1.13+)
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
// WebSocket accept key
// =====================
func acceptKey(key string) string {
	h := sha1.New()
	h.Write([]byte(key + wsGUID))
	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}

// =====================
// Domaine autorisé (optionnel)
// =====================
func allowedDomain() string {
	u, err := user.Current()
	if err != nil {
		return ""
	}
	f, err := os.Open(filepath.Join(u.HomeDir, infoFile))
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
// Logging robuste
// =====================
func setupLogging() {
	_ = os.MkdirAll(logDir, 0755)

	if st, err := os.Stat(logFile); err == nil && st.Size() > maxLog {
		_ = os.Rename(logFile, logFile+"."+fmt.Sprint(time.Now().Unix()))
	}

	f, err := os.OpenFile(logFile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		log.Fatal(err)
	}

	log.SetOutput(io.MultiWriter(os.Stdout, f))
	log.SetFlags(log.LstdFlags)
}

// =====================
// systemd auto-install
// =====================
func ensureSystemd(listen, host, port string) {
	if _, err := os.Stat(servicePath); err == nil {
		return
	}

	unit := fmt.Sprintf(`[Unit]
Description=SSH WebSocket + TCP Tunnel
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=%s -listen %s -target-host %s -target-port %s
Restart=always
RestartSec=1
KillMode=process
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
`, binPath, listen, host, port)

	if err := writeFile(servicePath, []byte(unit), 0644); err != nil {
		log.Fatal(err)
	}

	exec.Command("systemctl", "daemon-reload").Run()
	exec.Command("systemctl", "enable", "sshws").Run()
	exec.Command("systemctl", "restart", "sshws").Run()
}

// =====================
// Réponse HTTP Injector
// =====================
func injectorResponse(method string) string {
	m := strings.ToUpper(method)

	if strings.Contains(m, "CONNECT") || strings.Contains(m, "HTTP/2.0") {
		return `HTTP/2.0 200 OK
Connection: keep-alive

`
	}

	return `HTTP/1.1 200 OK
Connection: keep-alive

`
}

// =====================
// Tunnel TCP / HTTP Injector
// =====================
func handleTCPTunnel(target string, w http.ResponseWriter, r *http.Request) {
	log.Printf("[TCP] %s %s Host=%s XOH=%s",
		r.RemoteAddr, r.Method, r.Host, r.Header.Get("X-Online-Host"))

	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "Hijack not supported", 500)
		return
	}

	client, buf, err := hj.Hijack()
	if err != nil {
		return
	}

	buf.WriteString(injectorResponse(r.Method))
	buf.Flush()

	remote, err := net.DialTimeout("tcp", target, 10*time.Second)
	if err != nil {
		client.Close()
		return
	}

	go io.Copy(remote, client)
	go io.Copy(client, remote)
}

// =====================
// Tunnel WebSocket
// =====================
func handleWebSocket(target string, w http.ResponseWriter, r *http.Request) {
	log.Printf("[WS] %s", r.RemoteAddr)

	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "Hijack not supported", 500)
		return
	}

	client, buf, err := hj.Hijack()
	if err != nil {
		return
	}

	key := r.Header.Get("Sec-WebSocket-Key")
	if key == "" {
		key = "dGhlIHNhbXBsZSBub25jZQ=="
	}

	resp := fmt.Sprintf(
		`HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: %s

`, acceptKey(key))

	buf.WriteString(resp)
	buf.Flush()

	remote, err := net.DialTimeout("tcp", target, 10*time.Second)
	if err != nil {
		client.Close()
		return
	}

	go io.Copy(remote, client)
	go io.Copy(client, remote)
}

// =====================
// Handler principal WS + TCP
// =====================
func handleConnection(target string, w http.ResponseWriter, r *http.Request) {
	ad := allowedDomain()
	if ad != "" {
		host := r.Host
		if strings.Contains(host, ":") {
			host, _, _ = net.SplitHostPort(host)
		}
		if !strings.EqualFold(host, ad) {
			http.Error(w, "Forbidden", 403)
			return
		}
	}

	if strings.EqualFold(r.Header.Get("Upgrade"), "websocket") ||
		strings.Contains(strings.ToLower(r.Header.Get("Connection")), "upgrade") {
		handleWebSocket(target, w, r)
		return
	}

	handleTCPTunnel(target, w, r)
}

// =====================
// MAIN
// =====================
func main() {
	listen := flag.String("listen", "80", "Port WS + TCP")
	targetHost := flag.String("target-host", "127.0.0.1", "SSH host")
	targetPort := flag.String("target-port", "22", "SSH port")
	flag.Parse()

	setupLogging()
	ensureSystemd(*listen, *targetHost, *targetPort)

	go func() {
		for {
			time.Sleep(30 * time.Second)
			log.Println("watchdog alive")
		}
	}()

	target := net.JoinHostPort(*targetHost, *targetPort)

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		handleConnection(target, w, r)
	})

	log.Printf("🚀 SSHWS actif sur :%s → %s", *listen, target)
	log.Fatal(http.ListenAndServe(":"+*listen, nil))
}
