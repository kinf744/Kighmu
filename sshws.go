// ================================================================
// sshws.go — WebSocket → SSH (TCP) Proxy
// Auto-install systemd | Ubuntu 18.04 → 24.04 | Go 1.13+
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

// =====================
// Constantes
// =====================

const (
	wsGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

	infoFile    = ".kighmu_info"
	binPath     = "/usr/local/bin/sshws"
	servicePath = "/etc/systemd/system/sshws.service"

	logDir  = "/var/log/sshws"
	logFile = "/var/log/sshws/sshws.log"
	maxLog  = 5 * 1024 * 1024
)

// =====================
// Fonction writeFile compatible Go 1.13+
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
// Utils WebSocket
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
Description=SSH WebSocket Tunnel (SSHWS)
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=%s -listen %s -target-host %s -target-port %s
Restart=always
RestartSec=1
TimeoutStopSec=5
KillMode=process
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
`, binPath, listen, host, port)

	if err := writeFile(servicePath, []byte(unit), 0644); err != nil {
		log.Fatal("Impossible d’écrire le service systemd :", err)
	}

	exec.Command("systemctl", "daemon-reload").Run()
	exec.Command("systemctl", "enable", "sshws").Run()
	exec.Command("systemctl", "restart", "sshws").Run()
}

// =====================
// WebSocket → SSH
// =====================

func handleWS(target string, w http.ResponseWriter, r *http.Request) {
	ad := allowedDomain()

	host := r.Host
	if strings.Contains(host, ":") {
		host, _, _ = net.SplitHostPort(host)
	}
	if ad != "" && !strings.EqualFold(host, ad) {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	if !strings.EqualFold(r.Header.Get("Upgrade"), "websocket") {
		http.Error(w, "Upgrade Required", http.StatusBadRequest)
		return
	}

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
		"HTTP/1.1 101 Switching Protocols\r\n"+
			"Upgrade: websocket\r\n"+
			"Connection: Upgrade\r\n"+
			"Sec-WebSocket-Accept: %s\r\n\r\n",
		acceptKey(key),
	)

	buf.WriteString(resp)
	buf.Flush()

	remote, err := net.DialTimeout("tcp", target, 10*time.Second)
	if err != nil {
		client.Close()
		return
	}

	if tcp, ok := remote.(*net.TCPConn); ok {
		tcp.SetKeepAlive(true)
		tcp.SetKeepAlivePeriod(30 * time.Second)
	}

	go func() {
		defer client.Close()
		defer remote.Close()
		io.Copy(remote, client)
	}()
	go func() {
		defer client.Close()
		defer remote.Close()
		io.Copy(client, remote)
	}()
}

// =====================
// MAIN
// =====================

func main() {
	listen := flag.String("listen", "80", "Port WebSocket")
	targetHost := flag.String("target-host", "127.0.0.1", "Hôte SSH")
	targetPort := flag.String("target-port", "22", "Port SSH")
	flag.Parse()

	setupLogging()

	ensureSystemd(*listen, *targetHost, *targetPort)

	// Watchdog interne
	go func() {
		for {
			time.Sleep(30 * time.Second)
			log.Println("watchdog alive")
		}
	}()

	target := net.JoinHostPort(*targetHost, *targetPort)

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if strings.EqualFold(r.Header.Get("Upgrade"), "websocket") {
			handleWS(target, w, r)
			return
		}
		w.Write([]byte("SSHWS OK\n"))
	})

	log.Println("SSHWS actif sur le port", *listen)
	log.Fatal(http.ListenAndServe(":"+*listen, nil))
}
