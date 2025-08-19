#!/usr/bin/env python3
# KIGHMUSSH simple SOCKS proxy

import socket
import threading
import select
import sys
import time

IP = '0.0.0.0'
PORT = 8080
BUFLEN = 8192
TIMEOUT = 60

class Server(threading.Thread):
    def __init__(self, host, port):
        threading.Thread.__init__(self)
        self.host = host
        self.port = port
        self.running = False
        self.threads = []

    def run(self):
        self.running = True
        self.soc = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.soc.bind((self.host, self.port))
        self.soc.listen(5)
        print(f"Proxy SOCKS KIGHMUSSH démarré sur {self.host}:{self.port}")
        while self.running:
            try:
                client_socket, client_addr = self.soc.accept()
                client_socket.settimeout(TIMEOUT)
                handler = ConnectionHandler(client_socket, client_addr)
                handler.start()
                self.threads.append(handler)
            except Exception:
                continue

    def stop(self):
        self.running = False
        self.soc.close()
        for t in self.threads:
            t.join()

class ConnectionHandler(threading.Thread):
    def __init__(self, client_socket, client_addr):
        threading.Thread.__init__(self)
        self.client_socket = client_socket
        self.client_addr = client_addr

    def run(self):
        try:
            print(f"Connexion entrante de {self.client_addr}")
            data = self.client_socket.recv(BUFLEN)
            # Traiter les données ici (mode proxy SOCKS à compléter)
            self.client_socket.send(data)  # Echo simple pour test
            self.client_socket.close()
        except Exception as e:
            print(f"Erreur connexion {self.client_addr}: {e}")

def main():
    port = PORT
    if len(sys.argv) > 1:
        port = int(sys.argv[1])
    server = Server(IP, port)
    server.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("Arrêt du proxy SOCKS KIGHMUSSH...")
        server.stop()

if __name__ == "__main__":
    main()
        
