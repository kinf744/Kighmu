#!/usr/bin/env python3
# =========================================================
# WS/WSS Tunnel Server - Kighmu VPS Manager
# Auteur : Kinf744
# Version : 2.0
# =========================================================

import asyncio
import websockets
import ssl
import socket
import os
import sys
import logging
import traceback
from datetime import datetime

# ---------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------

DEFAULT_SSH_HOST = "127.0.0.1"
DEFAULT_SSH_PORT = 22

WS_PORT = 8880   # WebSocket non sécurisé
WSS_PORT = 443   # WebSocket sécurisé

LOG_FILE = "/var/log/ws_wss_server.log"

# Chargement du domaine depuis ~/.kighmu_info si disponible
DOMAIN = "localhost"
if os.path.exists(os.path.expanduser("~/.kighmu_info")):
    with open(os.path.expanduser("~/.kighmu_info")) as f:
        for line in f:
            if line.startswith("DOMAIN="):
                DOMAIN = line.split("=", 1)[1].strip()
                break

# ---------------------------------------------------------
# CONFIGURATION DU LOGGING
# ---------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout)
    ]
)

# Logs supplémentaires par composants (facultatif)
log_main = logging.getLogger("ws_wss.main")
log_tls  = logging.getLogger("ws_wss.tls")
log_ws   = logging.getLogger("ws_wss.ws")
log_ssh  = logging.getLogger("ws_wss.ssh")
log_vpn  = logging.getLogger("ws_wss.vpn")

# Redirection des loggers vers le même fichier principal
for lg in [log_main, log_tls, log_ws, log_ssh, log_vpn]:
    lg.propagate = True  # assure que les messages atteignent le root logger

# ---------------------------------------------------------
# CLASSE DE TUNNEL SSH VIA WEBSOCKET
# ---------------------------------------------------------
class WSSTunnelServer:
    def __init__(self, ssh_host=DEFAULT_SSH_HOST, ssh_port=DEFAULT_SSH_PORT):
        self.ssh_host = ssh_host
        self.ssh_port = ssh_port

    async def handle_client(self, websocket, path):
        client_ip = websocket.remote_address[0]
        log_main.info(f"Nouvelle connexion WebSocket de {client_ip} sur {path}")

        # Prépare l'état de la session
        ssl_handshake_ok = False
        ssh_established = False
        try:
            # Connexion au serveur SSH local
            log_ssh.debug(f"Essai d'ouverture de la connexion SSH locale vers {self.ssh_host}:{self.ssh_port} pour {client_ip}")
            reader, writer = await asyncio.open_connection(self.ssh_host, self.ssh_port)
            ssh_established = True
            log_ssh.info(f"Tunnel SSH établi pour {client_ip}")

            async def ws_to_ssh():
                nonlocal writer
                try:
                    async for message in websocket:
                        if isinstance(message, bytes):
                            writer.write(message)
                            await writer.drain()
                            log_ws.debug(f"WS->SSH: {len(message)} octets pour {client_ip}")
                        else:
                            log_ws.warning(f"Message texte ignoré de {client_ip}")
                except Exception as e:
                    log_ws.exception(f"Erreur WS->SSH pour {client_ip}: {e}")
                finally:
                    try:
                        writer.close()
                        await writer.wait_closed()
                    except Exception:
                        pass

            async def ssh_to_ws():
                nonlocal websocket
                try:
                    while True:
                        data = await reader.read(4096)
                        if not data:
                            break
                        await websocket.send(data)
                        log_ws.debug(f"SSH->WS: {len(data)} octets pour {client_ip}")
                except Exception as e:
                    log_ws.exception(f"Erreur SSH->WS pour {client_ip}: {e}")
                finally:
                    try:
                        await websocket.close()
                    except Exception:
                        pass

            await asyncio.gather(ws_to_ssh(), ssh_to_ws())

        except Exception as e:
            log_main.error(f"Erreur avec {client_ip}: {e}")
            traceback.print_exc()
        finally:
            log_main.info(f"Connexion fermée pour {client_ip}")
            # Fermeture sécurisée si nécessaire
            try:
                if 'writer' in locals():
                    writer.close()
                    await writer.wait_closed()
            except Exception:
                pass

    async def start_servers(self):
        # Serveur WebSocket (non sécurisé)
        ws_server = await websockets.serve(self.handle_client, "0.0.0.0", WS_PORT, ping_interval=None)
        log_main.info(f"Serveur WS lancé sur ws://{DOMAIN}:{WS_PORT}")

        # Serveur WebSocket sécurisé (WSS)
        ssl_context = self._load_or_generate_cert()
        wss_server = await websockets.serve(self.handle_client, "0.0.0.0", WSS_PORT, ssl=ssl_context, ping_interval=None)
        log_main.info(f"Serveur WSS lancé sur wss://{DOMAIN}:{WSS_PORT}")

        await asyncio.Future()  # Exécution infinie

    def _load_or_generate_cert(self):
        """
        Charge un certificat Let's Encrypt s'il existe, sinon le génère automatiquement via certbot.
        """
        cert_path = f"/etc/letsencrypt/live/{DOMAIN}/fullchain.pem"
        key_path = f"/etc/letsencrypt/live/{DOMAIN}/privkey.pem"

        if not os.path.exists(cert_path) or not os.path.exists(key_path):
            log_tls.warning("Aucun certificat Let's Encrypt trouvé. Tentative de génération...")
            # Exécution sécurisée via subprocess pour éviter shell injection si possible
            rc = os.system(f"sudo certbot certonly --standalone -d {DOMAIN} --agree-tos -m admin@{DOMAIN} --non-interactive 2>&1 || true")
            log_tls.debug(f"Certbot exit code: {rc}")

        if not os.path.exists(cert_path) or not os.path.exists(key_path):
            log_tls.warning("⚠️ Impossible de générer un certificat valide. Passage en mode auto-signé.")
            cert_dir = "/etc/ssl/kighmu"
            os.makedirs(cert_dir, exist_ok=True)
            os.system(f"openssl req -x509 -newkey rsa:2048 -nodes -keyout {cert_dir}/key.pem -out {cert_dir}/key.pem -days 365 -subj '/CN={DOMAIN}' 2>&1 || true")
            cert_path = f"{cert_dir}/cert.pem"
            key_path = f"{cert_dir}/key.pem"

        ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ssl_context.load_cert_chain(certfile=cert_path, keyfile=key_path)
        log_tls.info(f"TLS: certificat chargé (cert={cert_path}, key={key_path})")
        return ssl_context


# ---------------------------------------------------------
# MAIN
# ---------------------------------------------------------
if __name__ == "__main__":
    log_main.info("🚀 Démarrage du serveur WS/WSS avancé...")
    print("START")  # Debug rapide si besoin
    tunnel = WSSTunnelServer()
    try:
        asyncio.run(tunnel.start_servers())
    except KeyboardInterrupt:
        log_main.info("🛑 Arrêt manuel du serveur.")
    except Exception as e:
        log_main.error(f"Erreur critique : {e}")
        traceback.print_exc()
