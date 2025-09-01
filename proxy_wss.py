#!/usr/bin/env python
# encoding: utf-8
import socket, threading, select, sys, time, base64, hashlib
import getopt

# Listen settings
LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = 8090
PASS = ''

# CONST
BUFLEN = 4096 * 4
TIMEOUT = 60
DEFAULT_HOST = '127.0.0.1:22'


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
        self.soc.listen(0)
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
            threads = list(self.threads)
            for c in threads:
                c.close()


def generate_accept_key(sec_websocket_key):
    magic_string = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    accept_key = base64.b64encode(hashlib.sha1((sec_websocket_key + magic_string).encode()).digest()).decode()
    return accept_key


class ConnectionHandler(threading.Thread):
    def __init__(self, socClient, server, addr):
        threading.Thread.__init__(self)
        self.clientClosed = False
        self.targetClosed = True
        self.client = socClient
        self.client_buffer = b''
        self.server = server
        self.log = 'Connection: ' + str(addr)

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
            if not self.targetClosed and hasattr(self, 'target'):
                self.target.shutdown(socket.SHUT_RDWR)
                self.target.close()
        except:
            pass
        finally:
            self.targetClosed = True

    def run(self):
        try:
            request = self.client.recv(BUFLEN).decode(errors='ignore')

            if "Upgrade: websocket" in request:
                # WebSocket handshake processing
                lines = request.split("\r\n")
                key = None
                for line in lines:
                    if line.lower().startswith("sec-websocket-key:"):
                        key = line.split(":")[1].strip()
                        break
                if not key:
                    self.client.send(b'HTTP/1.1 400 Bad Request\r\n\r\nMissing Sec-WebSocket-Key')
                    self.close()
                    return

                accept_key = generate_accept_key(key)
                response = (
                    "HTTP/1.1 101 Switching Protocols\r\n"
                    "Upgrade: websocket\r\n"
                    "Connection: Upgrade\r\n"
                    f"Sec-WebSocket-Accept: {accept_key}\r\n\r\n"
                )
                self.client.send(response.encode())
                self.server.printLog(f"Handshake completed with {self.log}")

                # Connect to target and start relaying data
                hostPort = self.findHeader(request, 'X-Real-Host')
                if not hostPort:
                    hostPort = DEFAULT_HOST

                self.connect_target(hostPort)
                self.doCONNECT()

            else:
                # Not a WebSocket, handle normally
                hostPort = self.findHeader(request, 'X-Real-Host')

                if hostPort == '':
                    hostPort = DEFAULT_HOST

                split = self.findHeader(request, 'X-Split')

                if split != '':
                    self.client.recv(BUFLEN)

                if hostPort != '':
                    passwd = self.findHeader(request, 'X-Pass')

                    if len(PASS) != 0 and passwd == PASS:
                        self.method_CONNECT(hostPort)
                    elif len(PASS) != 0 and passwd != PASS:
                        self.client.send(b'HTTP/1.1 400 WrongPass!\r\n\r\n')
                    elif hostPort.startswith('127.0.0.1') or hostPort.startswith('localhost'):
                        self.method_CONNECT(hostPort)
                    else:
                        self.client.send(b'HTTP/1.1 403 Forbidden!\r\n\r\n')
                else:
                    self.server.printLog('- No X-Real-Host!')
                    self.client.send(b'HTTP/1.1 400 NoXRealHost!\r\n\r\n')

        except Exception as e:
            self.log += ' - error: ' + str(e)
            self.server.printLog(self.log)
        finally:
            self.close()
            self.server.removeConn(self)

    def findHeader(self, head, header):
        aux = head.find(header + ': ')

        if aux == -1:
            return ''

        aux = head.find(':', aux)
        head = head[aux + 2:]
        aux = head.find('\r\n')

        if aux == -1:
            return ''

        return head[:aux]

    def connect_target(self, host):
        i = host.find(':')
        if i != -1:
            port = int(host[i + 1:])
            host = host[:i]
        else:
            port = 22

        (soc_family, soc_type, proto, _, address) = socket.getaddrinfo(host, port)[0]

        self.target = socket.socket(soc_family, soc_type, proto)
        self.targetClosed = False
        self.target.connect(address)

    def method_CONNECT(self, path):
        self.server.printLog(self.log + ' - CONNECT ' + path)

        self.connect_target(path)
        response = "HTTP/1.1 101 Switching Protocols\r\n" \
                   "Upgrade: websocket\r\n" \
                   "Connection: Upgrade\r\n\r\n"
        self.client.sendall(response.encode())
        self.client_buffer = b''
        self.doCONNECT()

    def doCONNECT(self):
        socs = [self.client, self.target]
        count = 0
        error = False
        while True:
            count += 1
            try:
                recv, _, err = select.select(socs, [], socs, 3)
            except Exception as e:
                self.server.printLog(f"Select error: {e}")
                break

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
                                    sent = self.target.send(data)
                                    data = data[sent:]
                            count = 0
                        else:
                            error = True
                            break
                    except Exception as e:
                        self.server.printLog(f"Data relay error: {e}")
                        error = True
                        break

            if count == TIMEOUT:
                error = True

            if error:
                break


def print_usage():
    print('Usage: proxy.py -p <port>')
    print('       proxy.py -b <bindAddr> -p <port>')
    print('       proxy.py -b 0.0.0.0 -p 80')


def parse_args(argv):
    global LISTENING_ADDR
    try:
        opts, args = getopt.getopt(argv, "hb:", ["bind="])
    except getopt.GetoptError:
        print_usage()
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print_usage()
            sys.exit()
        elif opt in ("-b", "--bind"):
            LISTENING_ADDR = arg


def main(host=LISTENING_ADDR, port=LISTENING_PORT):
    print("\033[0;34m•" * 8, "\033[1;32m PROXY PYTHON WEBSOCKET", "\033[0;34m•" * 8, "\n")
    print("\033[1;33mIP:\033[1;32m " + LISTENING_ADDR)
    print("\033[1;33mPORT:\033[1;32m " + str(LISTENING_PORT) + "\n")
    print("\033[0;34m•" * 10, "\033[1;32m ILYASS AUTO SCRIPT", "\033[0;34m•\033[1;37m" * 11, "\n")

    server = Server(LISTENING_ADDR, LISTENING_PORT)
    server.start()

    while True:
        try:
            time.sleep(2)
        except KeyboardInterrupt:
            print('Stopping...')
            server.close()
            break


if __name__ == '__main__':
    parse_args(sys.argv[1:])
    main()
        
