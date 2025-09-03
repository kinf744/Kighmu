#!/usr/bin/env python3
import socket
import threading

LISTEN_ADDR = '127.0.0.1'
LISTEN_PORT = 80

# Payload HTTP custom pour le handshake WebSocket / tunnel HTTP
CUSTOM_PAYLOAD = (
    "GET /ws/ HTTP/1.1\r\n"
    "Host: example.com\r\n"
    "User-Agent: CustomClient/1.0\r\n"
    "Upgrade: websocket\r\n"
    "Connection: Upgrade\r\n"
    "Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==\r\n"
    "Sec-WebSocket-Version: 13\r\n"
    "\r\n"
)

class ProxyThread(threading.Thread):
    def __init__(self, client_socket, remote_host='127.0.0.1', remote_port=22):
        threading.Thread.__init__(self)
        self.client_socket = client_socket
        self.remote_host = remote_host
        self.remote_port = remote_port

    def run(self):
        remote_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        remote_socket.connect((self.remote_host, self.remote_port))

        # Envoi du payload custom HTTP (handshake)
        remote_socket.sendall(CUSTOM_PAYLOAD.encode())

        def relay(source, target):
            try:
                while True:
                    data = source.recv(4096)
                    if not data:
                        break
                    target.sendall(data)
            except:
                pass

        thread1 = threading.Thread(target=relay, args=(self.client_socket, remote_socket))
        thread2 = threading.Thread(target=relay, args=(remote_socket, self.client_socket))
        thread1.start()
        thread2.start()
        thread1.join()
        thread2.join()

        self.client_socket.close()
        remote_socket.close()

def main():
    sock_server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock_server.bind((LISTEN_ADDR, LISTEN_PORT))
    sock_server.listen(5)
    print(f"Proxy websocket custom HTTP à l'écoute sur {LISTEN_ADDR}:{LISTEN_PORT}")

    while True:
        client_sock, addr = sock_server.accept()
        print(f"Connexion reçue de {addr}")
        proxy_thread = ProxyThread(client_sock)
        proxy_thread.start()

if __name__ == '__main__':
    main()
    
