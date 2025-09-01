#!/usr/bin/env python
# encoding: utf-8
import socket, threading, select, sys, time

LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = 80  # Port fixe 80 pour le tunnel WS SSH
DEFAULT_SSH_HOST = '127.0.0.1'
DEFAULT_SSH_PORT = 22
BUFLEN = 4096 * 4
TIMEOUT = 60
STATUS_RESP = '101'
MSG = 'Switching Protocols'
FTAG = '\r\nContent-length: 0\r\n\r\nHTTP/1.1 200 WS By Proxy\r\n\r\n'
RESPONSE = "HTTP/1.1 " + str(STATUS_RESP) + ' ' +  str(MSG) + ' ' +  str(FTAG)

class Server(threading.Thread):
    def __init__(self, host, port):
        threading.Thread.__init__(self)
        self.running = False
        self.host = host
        self.port = port
        self.threads = []
        self.threadsLock = threading.Lock()

    def run(self):
        self.soc = socket.socket(socket.AF_INET)
        self.soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.soc.bind((self.host, self.port))
        self.soc.listen(5)
        self.running = True
        print(f"Listening on {self.host}:{self.port} for WebSocket SSH tunnels...")

        try:
            while self.running:
                c, addr = self.soc.accept()
                c.setblocking(1)
                conn = ConnectionHandler(c, self, addr)
                conn.start()
                with self.threadsLock:
                    self.threads.append(conn)
        finally:
            self.soc.close()

    def removeConn(self, conn):
        with self.threadsLock:
            if conn in self.threads:
                self.threads.remove(conn)

    def close(self):
        self.running = False
        with self.threadsLock:
            for conn in self.threads:
                conn.close()

class ConnectionHandler(threading.Thread):
    def __init__(self, client, server, addr):
        threading.Thread.__init__(self)
        self.client = client
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
        except:
            pass
        self.clientClosed = True

        try:
            if self.target and not self.targetClosed:
                self.target.shutdown(socket.SHUT_RDWR)
                self.target.close()
        except:
            pass
        self.targetClosed = True

    def run(self):
        try:
            # Receive client handshake/request
            data = self.client.recv(BUFLEN).decode('utf-8', errors='ignore')

            # Simple check for WebSocket handshake containing "Upgrade: websocket"
            if "Upgrade: websocket" not in data.lower():
                self.client.send(b"HTTP/1.1 400 Bad Request\r\n\r\n")
                self.close()
                self.server.removeConn(self)
                return

            # Reply with WebSocket switching protocol response
            self.client.send(RESPONSE.encode())

            # Connect to local SSH server
            self.target = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.target.connect((DEFAULT_SSH_HOST, DEFAULT_SSH_PORT))
            self.targetClosed = False

            # Start forwarding data between client and SSH server
            self.do_tunnel()

        except Exception as e:
            print(f"Connection error from {self.addr}: {e}")
        finally:
            self.close()
            self.server.removeConn(self)

    def do_tunnel(self):
        sockets = [self.client, self.target]
        cyclic_timeout_counter = 0
        while True:
            cyclic_timeout_counter += 1
            readable, _, exceptional = select.select(sockets, [], sockets, 1)
            if exceptional:
                break
            if readable:
                for s in readable:
                    other = self.target if s is self.client else self.client
                    try:
                        data = s.recv(BUFLEN)
                        if data:
                            other.sendall(data)
                        else:
                            return
                    except:
                        return
            if cyclic_timeout_counter > TIMEOUT:
                break

if __name__ == "__main__":
    try:
        server = Server(LISTENING_ADDR, LISTENING_PORT)
        server.start()
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("Stopping server...")
        server.close()
        sys.exit(0)
        
