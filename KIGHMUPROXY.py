#!/usr/bin/env python3
# encoding: utf-8
# KIGHMUPROXY - Proxy TCP SOCKS inspiré DarkSSH (version améliorée)

import socket
import threading
import select
import sys
import time
import datetime

IP = '0.0.0.0'
PASS = ''  # Mot de passe optionnel
BUFLEN = 8196 * 8
TIMEOUT = 60
MSG = 'KIGHMUPROXY'
RESPONSE = "HTTP/1.1 200 OK\r\n\r\n"
DEFAULT_HOST = '0.0.0.0:22'


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
        self.soc = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.soc.settimeout(2)
        self.soc.bind((self.host, self.port))
        self.soc.listen(0)
        self.running = True
        self.print_log(f"KIGHMUPROXY démarré sur {self.host}:{self.port}", level="INFO")

        try:
            while self.running:
                try:
                    c, addr = self.soc.accept()
                    c.setblocking(1)
                except socket.timeout:
                    continue

                conn = ConnectionHandler(c, self, addr)
                conn.start()
                self.add_conn(conn)
        finally:
            self.running = False
            self.soc.close()

    def print_log(self, msg, level="INFO"):
        with self.logLock:
            now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            print(f"[{now}] [{level}] {msg}")

    def add_conn(self, conn):
        with self.threadsLock:
            if self.running:
                self.threads.append(conn)

    def remove_conn(self, conn):
        with self.threadsLock:
            if conn in self.threads:
                self.threads.remove(conn)

    def close(self):
        self.print_log("Fermeture du proxy et des connexions...", level="INFO")
        self.running = False
        with self.threadsLock:
            threads = list(self.threads)
            for c in threads:
                c.close()


class ConnectionHandler(threading.Thread):
    def __init__(self, client_socket, server, addr):
        super().__init__()
        self.client = client_socket
        self.server = server
        self.addr = addr
        self.client_closed = False
        self.target_closed = True

    def close(self):
        try:
            if not self.client_closed:
                self.client.shutdown(socket.SHUT_RDWR)
                self.client.close()
        except:
            pass
        finally:
            self.client_closed = True

        try:
            if not self.target_closed and hasattr(self, 'target'):
                self.target.shutdown(socket.SHUT_RDWR)
                self.target.close()
        except:
            pass
        finally:
            self.target_closed = True

    def run(self):
        try:
            client_buffer = self.client.recv(BUFLEN)
            host_port = self.find_header(client_buffer, 'X-Real-Host')

            if not host_port:
                host_port = DEFAULT_HOST

            passwd = self.find_header(client_buffer, 'X-Pass')

            if PASS and passwd != PASS:
                self.client.send(b"HTTP/1.1 400 WrongPass!\r\n\r\n")
                self.server.print_log(f"{self.addr} Mot de passe invalide", level="ERROR")
                self.close()
                return

            if host_port.startswith(IP) or not PASS:
                self.server.print_log(f"{self.addr} CONNECT vers {host_port}", level="CONN")
                self.method_connect(host_port)
            else:
                self.client.send(b"HTTP/1.1 403 Forbidden!\r\n\r\n")
                self.server.print_log(f"{self.addr} Accès refusé", level="ERROR")

        except Exception as e:
            self.server.print_log(f"{self.addr} Erreur : {e}", level="ERROR")
        finally:
            self.close()
            self.server.remove_conn(self)

    def find_header(self, data, header):
        try:
            data_str = data.decode(errors='ignore')
            start = data_str.find(header + ": ")
            if start == -1:
                return ''
            start += len(header) + 2
            end = data_str.find('\r\n', start)
            if end == -1:
                return ''
            return data_str[start:end].strip()
        except:
            return ''

    def connect_target(self, host_port):
        i = host_port.find(':')
        if i != -1:
            port = int(host_port[i+1:])
            host = host_port[:i]
        else:
            port = 22
            host = host_port

        info = socket.getaddrinfo(host, port)[0]
        soc_family, soc_type, proto, _, addr = info

        self.target = socket.socket(soc_family, soc_type, proto)
        self.target_closed = False
        self.target.connect(addr)

    def method_connect(self, host_port):
        self.server.print_log(f"{self.addr} Ouverture de tunnel vers {host_port}", level="INFO")
        self.connect_target(host_port)
        self.client.sendall(RESPONSE.encode())
        self.do_connect()

    def do_connect(self):
        socks = [self.client, self.target]
        timeout_counter = 0
        error = False
        while True:
            try:
                recv, _, err = select.select(socks, [], socks, 3)
            except Exception:
                break

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
                            timeout_counter = 0
                        else:
                            error = True
                    except Exception:
                        error = True
                        break

            timeout_counter += 1
            if timeout_counter >= TIMEOUT or error:
                break


def main():
    print("KIGHMUPROXY - tunnel SSH proxy SOCKS type DarkSSH\n")

    # Demande systématique du port à chaque démarrage
    while True:
        try:
            port_input = input("Veuillez saisir le port sur lequel démarrer le proxy : ")
            port = int(port_input)
            if port < 1 or port > 65535:
                print("❌ Veuillez entrer un numéro de port valide (1-65535).")
                continue
            break
        except ValueError:
            print("❌ Entrée invalide. Veuillez entrer un numéro de port valide (ex. 8080).")

    # Confirmation lisible
    print(f"✅ Le proxy sera démarré sur {IP}:{port}\n")

    # Lancer le serveur proxy
    server = Server(IP, port)
    server.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n⏹️  Arrêt du proxy...")
        server.close()


if __name__ == '__main__':
    main()
                        
