#!/usr/bin/env python3
import paramiko
import socket
import threading
import struct
import select
import sys

class ForwardServer(threading.Thread):
    def __init__(self, ssh_transport, bind_addr='0.0.0.0', bind_port=8080):
        super().__init__()
        self.ssh_transport = ssh_transport
        self.bind_addr = bind_addr
        self.bind_port = bind_port
        self.server = None
        self.running = False

    def run(self):
        self.running = True
        self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server.bind((self.bind_addr, self.bind_port))
        self.server.listen(100)
        print(f"Proxy SOCKS5 SSH démarré sur {self.bind_addr}:{self.bind_port}")

        while self.running:
            client_sock, addr = self.server.accept()
            handler = ForwardHandler(client_sock, self.ssh_transport)
            handler.start()

    def stop(self):
        self.running = False
        if self.server:
            self.server.close()

class ForwardHandler(threading.Thread):
    def __init__(self, client_sock, ssh_transport):
        super().__init__()
        self.client_sock = client_sock
        self.ssh_transport = ssh_transport

    def run(self):
        try:
            ver, nmethods = struct.unpack("!BB", self.client_sock.recv(2))
            self.client_sock.recv(nmethods)  # ignore methods
            self.client_sock.sendall(b"\x05\x00")  # no auth required

            ver, cmd, _, atyp = struct.unpack("!BBBB", self.client_sock.recv(4))
            if ver != 5 or cmd != 1:  # only CONNECT supported
                self.client_sock.close()
                return

            if atyp == 1:
                dst_addr = socket.inet_ntoa(self.client_sock.recv(4))
            elif atyp == 3:
                domain_length = self.client_sock.recv(1)[0]
                dst_addr = self.client_sock.recv(domain_length).decode()
            elif atyp == 4:
                dst_addr = socket.inet_ntop(socket.AF_INET6, self.client_sock.recv(16))
            else:
                self.client_sock.close()
                return

            dst_port = struct.unpack('!H', self.client_sock.recv(2))

            channel = self.ssh_transport.open_channel('direct-tcpip', (dst_addr, dst_port), self.client_sock.getsockname())
            if channel is None:
                self.client_sock.sendall(struct.pack("!BBBBIH", 5, 5, 0, 1, 0, 0))  # failure
                self.client_sock.close()
                return

            self.client_sock.sendall(struct.pack("!BBBBIH", 5, 0, 0, 1, 0, 0))  # success

            self.relay(self.client_sock, channel)
        except Exception as e:
            print(f"Erreur canal : {e}")
        finally:
            self.client_sock.close()

    def relay(self, client_sock, channel):
        sockets = [client_sock, channel]
        while True:
            rlist, _, _ = select.select(sockets, [], [])
            if client_sock in rlist:
                data = client_sock.recv(1024)
                if len(data) == 0:
                    break
                channel.send(data)
            if channel in rlist:
                data = channel.recv(1024)
                if len(data) == 0:
                    break
                client_sock.send(data)
        channel.close()

def create_ssh_transport(hostname, port, username, pkey_path):
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    key = paramiko.RSAKey.from_private_key_file(pkey_path)
    client.connect(hostname=hostname, port=port, username=username, pkey=key)
    return client.get_transport()

if __name__ == "__main__":
    if len(sys.argv) < 5:
        print("Utilisation: python3 ssh_socks_proxy.py <serveur_ssh> <port_ssh> <utilisateur> <cle_privee> [port_local_proxy]")
        sys.exit(1)
    hostname = sys.argv[1]
    port = int(sys.argv)
    username = sys.argv
    pkey_file = sys.argv
    local_port = int(sys.argv) if len(sys.argv) > 5 else 8080

    transport = create_ssh_transport(hostname, port, username, pkey_file)
    server = ForwardServer(transport, bind_port=local_port)
    server.start()

    try:
        while True:
            pass
    except KeyboardInterrupt:
        print("Arrêt du proxy SOCKS")
        server.stop()
            
