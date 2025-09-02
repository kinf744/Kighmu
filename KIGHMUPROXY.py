#!/usr/bin/env python3
import subprocess
import socket
import threading
import select
import sys
import time
import signal

IP = '0.0.0.0'
try:
    PORT = int(sys.argv[1])
except Exception:
    PORT = 8080

PASS = ''
BUFLEN = 8196 * 8
TIMEOUT = 60
MSG = 'KIGHMUPROXY'
DEFAULT_HOST = '0.0.0.0:22'
RESPONSE = f"HTTP/1.1 200 {MSG}\r\n\r\n"

SSH_USER = "user"           # Modifier avec ton utilisateur SSH
SSH_HOST = "remotehost"     # Modifier avec ton serveur SSH distant
SSH_PORT = 22               # Port SSH distant, généralement 22
SSH_SOCKS_PORT = 1080       # Port local pour le tunnel SSH SOCKS

class SSHTunnel:
    def __init__(self, user, host, ssh_port=22, socks_port=1080):
        self.user = user
        self.host = host
        self.ssh_port = ssh_port
        self.socks_port = socks_port
        self.process = None

    def start(self):
        cmd = [
            "ssh",
            "-N",
            "-D", str(self.socks_port),
            "-C",
            "-q",
            "-p", str(self.ssh_port),
            f"{self.user}@{self.host}"
        ]
        self.process = subprocess.Popen(cmd)
        print(f"Tunnel SSH SOCKS lancé sur le port {self.socks_port}")

    def stop(self):
        if self.process:
            self.process.terminate()
            self.process.wait()
            print("Tunnel SSH SOCKS arrêté")

class Server(threading.Thread):
    def __init__(self, host, port):
        super().__init__()
        self.running = False
        self.host = host
        self.port = port
        self.threads = []
        self.threadsLock = threading.Lock()
        self.logLock = threading.Lock()

    def run(self):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as soc:
            soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            soc.settimeout(2)
            soc.bind((self.host, self.port))
            soc.listen()
            self.running = True
            self.log(f"KIGHMUPROXY démarré sur {self.host}:{self.port}")

            while self.running:
                try:
                    c, addr = soc.accept()
                    c.setblocking(True)
                    conn = ConnectionHandler(c, self, addr)
                    conn.start()
                    self.addConn(conn)
                except socket.timeout:
                    continue
                except Exception as e:
                    self.log(f"Erreur accept: {e}")

    def log(self, msg):
        with self.logLock:
            print(msg)

    def addConn(self, conn):
        with self.threadsLock:
            if self.running:
                self.threads.append(conn)

    def removeConn(self, conn):
        with self.threadsLock:
            if conn in self.threads:
                self.threads.remove(conn)

    def close(self):
        self.running = False
        with self.threadsLock:
            threads_copy = list(self.threads)
        for conn in threads_copy:
            conn.close()

class ConnectionHandler(threading.Thread):
    def __init__(self, client_socket, server, addr):
        super().__init__()
        self.client = client_socket
        self.server = server
        self.addr = addr
        self.clientClosed = False
        self.targetClosed = True
        self.target = None

    def close(self):
        try:
            if not self.clientClosed:
                self.client.shutdown(socket.SHUT_RDWR)
                self.client.close()
        except Exception:
            pass
        finally:
            self.clientClosed = True

        try:
            if not self.targetClosed and self.target:
                self.target.shutdown(socket.SHUT_RDWR)
                self.target.close()
        except Exception:
            pass
        finally:
            self.targetClosed = True

    def run(self):
        try:
            data = self.client.recv(BUFLEN)
            host_port = self.findHeader(data, 'X-Real-Host') or DEFAULT_HOST

            passwd = self.findHeader(data, 'X-Pass')
            if PASS and passwd != PASS:
                self.client.send(b"HTTP/1.1 400 WrongPass!\r\n\r\n")
                return

            if host_port.startswith(IP) or not PASS:
                self.method_CONNECT(host_port)
            else:
                self.client.send(b"HTTP/1.1 403 Forbidden!\r\n\r\n")
        except Exception as e:
            self.server.log(f"[{self.addr}] Erreur: {e}")
        finally:
            self.close()
            self.server.removeConn(self)

    def findHeader(self, data, header):
        try:
            data_str = data.decode(errors='ignore')
            start = data_str.find(header + ": ")
            if start == -1:
                return ''
            start += len(header) + 2
            end = data_str.find('\r\n', start)
            return data_str[start:end].strip() if end != -1 else ''
        except Exception:
            return ''

    def connect_target(self, host_port):
        i = host_port.find(':')
        if i != -1:
            port = int(host_port[i + 1:])
            host = host_port[:i]
        else:
            port = 22
            host = host_port

        info = socket.getaddrinfo(host, port)[0]
        soc_family, soc_type, proto, _, addr = info

        self.target = socket.socket(soc_family, soc_type, proto)
        self.targetClosed = False
        self.target.connect(addr)

    def method_CONNECT(self, host_port):
        self.server.log(f"[{self.addr}] CONNECT vers {host_port}")
        self.connect_target(host_port)
        self.client.sendall(RESPONSE.encode())
        self.do_CONNECT()

    def do_CONNECT(self):
        socks = [self.client, self.target]
        count = 0
        error = False

        while True:
            try:
                recv, _, err = select.select(socks, [], socks, 3)
                if err:
                    error = True
                if recv:
                    for s in recv:
                        try:
                            data = s.recv(BUFLEN)
                            if data:
                                if s is self.target:
                                    self.client.send(data)
                                else:
                                    while data:
                                        sent = self.target.send(data)
                                        data = data[sent:]
                                count = 0
                            else:
                                error = True
                        except:
                            error = True
                            break
            except Exception:
                error = True
            count += 1
            if count >= TIMEOUT or error:
                break

def main():
    ssh_tunnel = SSHTunnel(SSH_USER, SSH_HOST, ssh_port=SSH_PORT, socks_port=SSH_SOCKS_PORT)
    ssh_tunnel.start()

    server = Server(IP, PORT)
    server.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("Arrêt du proxy et du tunnel SSH")
        server.close()
        ssh_tunnel.stop()

if __name__ == "__main__":
    main()
        
