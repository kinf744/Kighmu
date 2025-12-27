// ================================================================
// sshws.go — WebSocket → SSH (TCP) Proxy
// Compatible HTTP Custom + GOST
// Auteur : @kighmu
// Patch & validation : tunnel TCP + WS (Slipstream-like)
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
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strings"
	"time"
)

const (
	wsGUID      = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	kighmuInfo  = ".kighmu_info"
	logDir      = "/var/log/sshws"
	logFile     = "/var/log/sshws/sshws.log"
	maxLogSize  = 5 * 1024 * 1024
)

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
		if strings.HasPrefix(sc.Text(), "DOMAIN=") {
			return strings.Trim(strings.SplitN(sc.Text(), "=", 2)[1], `"`)
		}
	}
	return ""
}

func setupLogging() {
	_ = os.MkdirAll(logDir, 0755)
	if i, e := os.Stat(logFile); e == nil && i.Size() > maxLogSize {
		_ = os.Rename(logFile, logFile+"."+fmt.Sprint(time.Now().Unix()))
	}
	f, _ := os.OpenFile(logFile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	log.SetOutput(io.MultiWriter(os.Stdout, f))
	log.SetFlags(log.LstdFlags)
}

func openFirewallPort(port string) {
	if exec.Command("iptables", "-C", "INPUT", "-p", "tcp", "--dport", port, "-j", "ACCEPT").Run() == nil {
		return
	}
	exec.Command("iptables", "-I", "INPUT", "-p", "tcp", "--dport", port, "-j", "ACCEPT").Run()
	exec.Command("netfilter-persistent", "save").Run()
}

func main() {
	listen := flag.String("listen", "80", "")
	targetHost := flag.String("target-host", "127.0.0.1", "")
	targetPort := flag.String("target-port", "22", "")
	payload := flag.String("payload", "", "")
	payloadAlt := flag.String("payload-alt", "", "")
	domainOnly := flag.Bool("domain-only", false, "")
	flag.Parse()

	setupLogging()
	openFirewallPort(*listen)

	target := net.JoinHostPort(*targetHost, *targetPort)
	ln, err := net.Listen("tcp", ":"+*listen)
	if err != nil {
		log.Fatal(err)
	}

	log.Println("SSHWS v2 Slipstream démarré sur le port", *listen)

	for {
		c, _ := ln.Accept()
		go dispatch(c, target, *payload, *payloadAlt, *domainOnly)
	}
}

func dispatch(c net.Conn, target, p1, p2 string, domainOnly bool) {
	defer c.Close()
	br := bufio.NewReader(c)

	peek, err := br.Peek(2048)
	if err != nil {
		return
	}

	s := strings.ToLower(string(peek))

	if strings.Contains(s, "upgrade: websocket") {
		handleWS(br, c, target, domainOnly)
		return
	}

	if strings.HasPrefix(s, "get ") || strings.HasPrefix(s, "connect ") {
		handleTCP(br, c, target, p1, p2)
		return
	}

	handleRaw(br, c, target)
}

func handleWS(br *bufio.Reader, c net.Conn, target string, domainOnly bool) {
	req := ""
	for {
		l, _ := br.ReadString('\n')
		req += l
		if l == "\r\n" {
			break
		}
	}

	if domainOnly {
		d := getKighmuDomain()
		if d != "" && !strings.Contains(strings.ToLower(req), "host: "+strings.ToLower(d)) {
			return
		}
	}

	key := "dGhlIHNhbXBsZSBub25jZQ=="
	for _, l := range strings.Split(req, "\r\n") {
		if strings.HasPrefix(strings.ToLower(l), "sec-websocket-key:") {
			key = strings.TrimSpace(strings.SplitN(l, ":", 2)[1])
		}
	}

	resp := fmt.Sprintf(
		"HTTP/1.1 101 Switching Protocols\r\n"+
			"Upgrade: websocket\r\n"+
			"Connection: Upgrade\r\n"+
			"Sec-WebSocket-Accept: %s\r\n\r\n",
		acceptKey(key),
	)

	c.Write([]byte(resp))

	r, _ := net.Dial("tcp", target)
	go io.Copy(r, br)
	io.Copy(c, r)
}

func handleTCP(br *bufio.Reader, c net.Conn, target, p1, p2 string) {
	r, err := net.Dial("tcp", target)
	if err != nil {
		return
	}

	payload := p1
	if payload == "" && p2 != "" {
		payload = p2
	}

	if payload != "" {
		c.Write([]byte(strings.ReplaceAll(payload, "[crlf]", "\r\n")))
	}

	go io.Copy(r, br)
	io.Copy(c, r)
}

func handleRaw(br *bufio.Reader, c net.Conn, target string) {
	r, err := net.Dial("tcp", target)
	if err != nil {
		return
	}
	go io.Copy(r, br)
	io.Copy(c, r)
}
