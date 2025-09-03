import socket
import threading

LISTEN_ADDR = '127.0.0.1'
LISTEN_PORT = 80

# Exemple de payload HTTP custom pour handshake WebSocket
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
    def __init__(self, client_socket, remote_host, remote_port):
        threading.Thread.__init__(self)
        self.client_socket = client_socket
        self.remote_host = remote_host
        self.remote_port = remote_port

    def run(self):
        remote_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        remote_socket.connect((self.remote_host, self.remote_port))

        # Envoyer le payload HTTP personnalisé en premier
        remote_socket.sendall(CUSTOM_PAYLOAD.encode())

        # Thread pour relayer client->serveur
        def client_to_server():
            try:
                while True:
                    data = self.client_socket.recv(4096)
                    if not data:
                        break
                    remote_socket.sendall(data)
            except:
                pass

        # Thread pour relayer serveur->client
        def server_to_client():
            try:
                while True:
                    data = remote_socket.recv(4096)
                    if not data:
                        break
                    self.client_socket.sendall(data)
            except:
                pass

        t1 = threading.Thread(target=client_to_server)
        t2 = threading.Thread(target=server_to_client)
        t1.start()
        t2.start()
        t1.join()
        t2.join()

        self.client_socket.close()
        remote_socket.close()

def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind((LISTEN_ADDR, LISTEN_PORT))
    server.listen(5)
    print(f"Proxy HTTP custom en écoute sur {LISTEN_ADDR}:{LISTEN_PORT}")

    while True:
        client_sock, addr = server.accept()
        print(f"Connexion de {addr}")
        # Remplacez par l'adresse de votre serveur SSH ou proxy distant
        proxy_thread = ProxyThread(client_sock, '127.0.0.1', 22)
        proxy_thread.start()

if __name__ == "__main__":
    main()
                    
