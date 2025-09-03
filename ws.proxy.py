#!/usr/bin/python3
import socket
import threading
import select
import sys
import time
import getopt
import base64
import hashlib

LISTENING_ADDR = '127.0.0.1'
LISTENING_PORT = 7000
PASS = ''
BUFLEN = 4096 * 4
TIMEOUT = 60
DEFAULT_HOST = '127.0.0.1:69'

class Server(threading.Thread):
    def __init__(self, host, port):
        threading.Thread.__init__(self)
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
        self.soc.listen(5)
        self.running = True

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
            for c in list(self.threads):
                c.close()

def create_websocket_accept(key):
    GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
    accept_key = base64.b64encode(hashlib.sha1((key + GUID).encode('utf-8')).digest()).decode('utf-8')
    return accept_key

class ConnectionHandler(threading.Thread):
    def __init__(self, client_sock, server, addr):
        threading.Thread.__init__(self)
        self.client_sock = client_sock
        self.server = server
        self.addr = addr
        self.clientClosed = False
        self.targetClosed = True
        self.target_sock = None

    def close(self):
        if not self.clientClosed:
            try:
                self.client_sock.shutdown(socket.SHUT_RDWR)
                self.client_sock.close()
            except:
                pass
            self.clientClosed = True

        if not self.targetClosed:
            try:
                self.target_sock.shutdown(socket.SHUT_RDWR)
                self.target_sock.close()
            except:
                pass
            self.targetClosed = True

    def run(self):
        try:
            handshake = self.client_sock.recv(BUFLEN).decode('utf-8', errors='ignore')
            headers = self.parse_headers(handshake)

            if 'Sec-WebSocket-Key' not in headers:
                self.client_sock.send(b"HTTP/1.1 400 Bad Request\r\n\r\n")
                self.close()
                self.server.removeConn(self)
                return

            ws_key = headers['Sec-WebSocket-Key']
            accept_key = create_websocket_accept(ws_key)
            response = (
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Accept: {accept_key}\r\n"
                "\r\n"
            )
            self.client_sock.send(response.encode('utf-8'))

            # Determine backend host:port
            backend_hostport = headers.get('X-Real-Host', DEFAULT_HOST)
            if ':' in backend_hostport:
                host, port = backend_hostport.split(':')
                port = int(port)
            else:
                host = backend_hostport
                port = 69

            # Connect to target backend
            self.target_sock = socket.create_connection((host, port))
            self.targetClosed = False

            self.server.printLog(f"WebSocket proxy connected {self.addr} => {host}:{port}")

            self.relay_loop()

        except Exception as e:
            self.server.printLog(f"Error: {e}")
        finally:
            self.close()
            self.server.removeConn(self)

    def parse_headers(self, data):
        headers = {}
        lines = data.split('\r\n')
        for line in lines[1:]:
            if ': ' in line:
                key, value = line.split(': ', 1)
                headers[key.strip()] = value.strip()
        return headers

    def relay_loop(self):
        inputs = [self.client_sock, self.target_sock]
        while True:
            rlist, _, _ = select.select(inputs, [], [], TIMEOUT)
            if not rlist:
                break

            for r in rlist:
                data = None
                try:
                    data = r.recv(BUFLEN)
                except:
                    pass

                if not data:
                    return

                if r is self.client_sock:
                    self.target_sock.sendall(data)
                else:
                    self.client_sock.sendall(data)

def print_usage():
    print("Usage: proxy.py -p <port> [-b <bindAddr>]")
    print("Example: proxy.py -b 0.0.0.0 -p 80")

def parse_args(argv):
    global LISTENING_ADDR, LISTENING_PORT
    try:
        opts, args = getopt.getopt(argv, "hb:p:", ["bind=", "port="])
    except getopt.GetoptError:
        print_usage()
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print_usage()
            sys.exit()
        elif opt in ("-b", "--bind"):
            LISTENING_ADDR = arg
        elif opt in ("-p", "--port"):
            LISTENING_PORT = int(arg)

def main():
    parse_args(sys.argv[1:])
    print(f"\n:-------Python WebSocket Proxy-------:\nListening addr: {LISTENING_ADDR}\nListening port: {LISTENING_PORT}\n")
    server = Server(LISTENING_ADDR, LISTENING_PORT)
    server.start()
    try:
        while True:
            time.sleep(2)
    except KeyboardInterrupt:
        print('Stopping...')
        server.close()

if __name__ == '__main__':
    main()
      
