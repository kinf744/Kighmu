// ================================================================
// udp-custom.go — UDP Custom Tunnel + HTTP Custom
// Ubuntu 20.04 | Go 1.13
// Auteur : @kighmu
// Licence : MIT
// ================================================================

package main

import (
	"bufio"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"net"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"
)

const (
	binPath     = "/usr/local/bin/udp-custom"
	servicePath = "/etc/systemd/system/udp-custom.service"
)

// ===================== SYSTEMD =====================

func ensureSystemd(httpPort, udpPort, target string) {
	if _, err := os.Stat(servicePath); err == nil {
		return
	}

	unit := fmt.Sprintf(`[Unit]
Description=UDP Custom Tunnel + HTTP Custom
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=%s -http %s -udp %s -target %s
Restart=always
RestartSec=1
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
`, binPath, httpPort, udpPort, target)

	// Compatible Go 1.13
	_ = ioutil.WriteFile(servicePath, []byte(unit), 0644)

	exec.Command("systemctl", "daemon-reload").Run()
	exec.Command("systemctl", "enable", "udp-custom").Run()
	exec.Command("systemctl", "restart", "udp-custom").Run()
}

// ===================== UDP SESSION =====================

type session struct {
	udpAddr  *net.UDPAddr
	tcpConn  net.Conn
	lastSeen time.Time
}

var (
	sessions = make(map[string]*session)
	mutex    sync.Mutex
)

// ===================== MAIN =====================

func main() {
	httpPort := flag.String("http", "85", "HTTP custom port par défaut")
	udpPort := flag.String("udp", "54000", "UDP custom port")
	target := flag.String("target", "127.0.0.1:22", "SSH backend")
	flag.Parse()

	ensureSystemd(*httpPort, *udpPort, *target)

	go startUDPTunnel(*udpPort, *target)
	startHTTPFake(*httpPort)
}

// ================= HTTP CUSTOM (FAKE) =================

func startHTTPFake(port string) {
	ln, err := net.Listen("tcp", ":"+port)
	if err != nil {
		log.Fatal(err)
	}
	log.Println("[HTTP CUSTOM] Actif sur", port)

	for {
		c, _ := ln.Accept()
		go handleHTTP(c)
	}
}

func handleHTTP(c net.Conn) {
	defer c.Close()
	r := bufio.NewReader(c)
	line, _ := r.ReadString('\n')

	if !strings.Contains(strings.ToLower(line), "http") {
		return
	}

	resp := "HTTP/1.1 200 OK\r\nConnection: keep-alive\r\n\r\n"
	c.Write([]byte(resp))
}

// ================= UDP CUSTOM =================

func startUDPTunnel(port, target string) {
	addr, _ := net.ResolveUDPAddr("udp", ":"+port)
	udpConn, err := net.ListenUDP("udp", addr)
	if err != nil {
		log.Fatal(err)
	}
	log.Println("[UDP CUSTOM] Tunnel actif sur", port)

	buf := make([]byte, 2048)

	for {
		n, clientAddr, err := udpConn.ReadFromUDP(buf)
		if err != nil {
			continue
		}

		key := clientAddr.String()

		mutex.Lock()
		sess, ok := sessions[key]
		if !ok {
			tcp, err := net.Dial("tcp", target)
			if err != nil {
				mutex.Unlock()
				continue
			}
			sess = &session{
				udpAddr:  clientAddr,
				tcpConn:  tcp,
				lastSeen: time.Now(),
			}
			sessions[key] = sess
			go tcpToUDP(udpConn, sess)
			log.Println("[SESSION]", key)
		}
		sess.lastSeen = time.Now()
		mutex.Unlock()

		sess.tcpConn.Write(buf[:n])
	}
}

func tcpToUDP(udp *net.UDPConn, sess *session) {
	buf := make([]byte, 2048)
	for {
		n, err := sess.tcpConn.Read(buf)
		if err != nil {
			mutex.Lock()
			delete(sessions, sess.udpAddr.String())
			mutex.Unlock()
			sess.tcpConn.Close()
			return
		}
		udp.WriteToUDP(buf[:n], sess.udpAddr)
	}
}
