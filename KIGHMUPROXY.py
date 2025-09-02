#!/usr/bin/env python3
import socket
import threading
import select
import sys
import time
import subprocess

# Configuration écoute proxy SOCKS
LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080

# Mot de passe vide désactive la vérification
PASS = ''

# Paramètres tunnel SSH SOCKS (à adapter)
SSH_USER = "user"
SSH_HOST = "ssh.remote.host"
SSH_PORT = 22
SOCKS_LOCAL_PORT = 1080

BUFLEN = 4096 * 4
TIMEOUT = 60
DEFAULT_HOST = '127.0.0.1:22'
RESPONSE = ('HTTP/1.1 200 <strong>(<span style="color: #ff0000;"><strong>'
            '<span style="color: #ff9900;">By</span>-'
            '<span style="color: #008000;">KHALED</span>AGN</strong></span>)</strong>\r\n'
            'Content-length: 0\r\n\r\nHTTP/1.1 200 successful connection\r\n\r\n')

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
            "-N",             # Pas de commande distante
            "-C",             # Compression
            "-q",             # Mode silencieux
            "-D", str(self.socks_port),  # Port local SOCKS
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
        self.soc = socket.socket(socket.AF_INET)
        self.soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.soc.settimeout(2)
        self.soc.bind((self.host, self.port))
        self.soc.listen(0)
        self.running = True
        print(f"Proxy SOCKS AGN démarré sur {self.host}:{self.port}")
        try:
            while self.running:
                try:
                    c, addr = self.soc.accept()
                    c.setblocking(1)
                except socket.timeout:
                    continue

                conn = ConnectionHandler(c, self, addr)
                conn.start()
                self.addConn(conn)
        finally:
            self.running = False
            self.soc.close()

    def printLog(self, log):
        with self.logLock:
            print(log)

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
            threads = list(self.threads)
        for c in threads:
            c.close()

class ConnectionHandler(threading.Thread):
    def __init__(self, socClient, server, addr):
        super().__init__()
        self.clientClosed = False
        self.targetClosed = True
        self.client = socClient
        self.client_buffer = ''
        self.server = server
        self.log = f'Connection: {addr}'

    def close(self):
        try:
            if not self.clientClosed:
                self.client.shutdown(socket.SHUT_RDWR)
                self.client.close()
        except:
            pass
        finally:
            self.clientClosed = True

        try:
            if not self.targetClosed:
                self.target.shutdown(socket.SHUT_RDWR)
                self.target.close()
        except:
            pass
        finally:
            self.targetClosed = True

    def run(self):
        try:
            self.client_buffer = self.client.recv(BUFLEN)
            hostPort = self.findHeader(self.client_buffer, 'X-Real-Host')

            if hostPort == '':
                hostPort = DEFAULT_HOST

            split = self.findHeader(self.client_buffer, 'X-Split')

            if split != '':
                self.client.recv(BUFLEN)

            if hostPort != '':
                passwd = self.findHeader(self.client_buffer, 'X-Pass')

                if len(PASS) != 0 and passwd != PASS:
                    self.client.send(b'HTTP/1.1 400 WrongPass!\r\n\r\n')
                elif hostPort.startswith('127.0.0.1') or hostPort.startswith('localhost'):
                    self.method_CONNECT(hostPort)
                else:
                    self.client.send(b'HTTP/1.1 403 Forbidden!\r\n\r\n')
            else:
                self.server.printLog('- No X-Real-Host!')
                self.client.send(b'HTTP/1.1 400 NoXRealHost!\r\n\r\n')

        except Exception as e:
            self.log += f' - error: {e}'
            self.server.printLog(self.log)
        finally:
            self.close()
            self.server.removeConn(self)

    def findHeader(self, head, header):
        aux = head.find(header.encode() + b': ')
        if aux == -1:
            return ''
        aux = head.find(b':', aux)
        head = head[aux+2:]
        aux = head.find(b'\r\n')
        if aux == -1:
            return ''
        return head[:aux].decode()

    def connect_target(self, host):
        i = host.find(':')
        if i != -1:
            port = int(host[i+1:])
            host = host[:i]
        else:
            port = 22

        (soc_family, soc_type, proto, _, address) = socket.getaddrinfo(host, port)[0]
        self.target = socket.socket(soc_family, soc_type, proto)
        self.targetClosed = False
        self.target.connect(address)

    def method_CONNECT(self, path):
        self.log += f' - CONNECT {path}'
        self.connect_target(path)
        self.client.sendall(RESPONSE.encode())
        self.client_buffer = ''
        self.server.printLog(self.log)
        self.doCONNECT()

    def doCONNECT(self):
        socs = [self.client, self.target]
        count = 0
        error = False
        while True:
            count += 1
            (recv, _, err) = select.select(socs, [], socs, 3)
            if err:
                error = True
            if recv:
                for in_ in recv:
                    try:
                        data = in_.recv(BUFLEN)
                        if data:
                            if in_ is self.target:
                                self.client.send(data)
                            else:
                                while data:
                                    byte = self.target.send(data)
                                    data = data[byte:]
                            count = 0
                        else:
                            break
                    except:
                        error = True
                        break
            if count == TIMEOUT:
                error = True
            if error:
                break

def main():
    ssh_tunnel = SSHTunnel(SSH_USER, SSH_HOST, ssh_port=SSH_PORT, socks_port=SOCKS_LOCAL_PORT)
    ssh_tunnel.start()

    server = Server(LISTENING_ADDR, LISTENING_PORT)
    server.start()

    try:
        while True:
            time.sleep(2)
    except KeyboardInterrupt:
        print('\nStopping...')
        server.close()
        ssh_tunnel.stop()

if __name__ == '__main__':
    main()
        
