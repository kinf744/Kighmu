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

# ---------------------------------------------------------
# CLASSE DE TUNNEL SSH VIA WEBSOCKET
# ---------------------------------------------------------
class WSSTunnelServer:
    def __init__(self, ssh_host=DEFAULT_SSH_HOST, ssh_port=DEFAULT_SSH_PORT):
        self.ssh_host = ssh_host
        self.ssh_port = ssh_port

    async def handle_client(self, websocket, path):
        client_ip = websocket.remote_address[0]
        logging.info(f"Nouvelle connexion WebSocket de {client_ip} sur {path}")

        try:
            # Connexion au serveur SSH local
            reader, writer = await asyncio.open_connection(self.ssh_host, self.ssh_port)
            logging.info(f"Tunnel SSH établi pour {client_ip}")

            async def ws_to_ssh():
                try:
                    async for message in websocket:
                        if isinstance(message, bytes):
                            writer.write(message)
                            await writer.drain()
                        else:
                            logging.warning(f"Message texte ignoré de {client_ip}")
                except Exception:
                    pass
                finally:
                    writer.close()
                    await writer.wait_closed()

            async def ssh_to_ws():
                try:
                    while True:
                        data = await reader.read(4096)
                        if not data:
                            break
                        await websocket.send(data)
                except Exception:
                    pass
                finally:
                    await websocket.close()

            await asyncio.gather(ws_to_ssh(), ssh_to_ws())

        except Exception as e:
            logging.error(f"Erreur avec {client_ip}: {e}")
            traceback.print_exc()
        finally:
            logging.info(f"Connexion fermée pour {client_ip}")

    async def start_servers(self):
        # Serveur WebSocket (non sécurisé)
        ws_server = await websockets.serve(self.handle_client, "0.0.0.0", WS_PORT, ping_interval=None)
        logging.info(f"Serveur WS lancé sur ws://{DOMAIN}:{WS_PORT}")

        # Serveur WebSocket sécurisé (WSS)
        ssl_context = self._load_or_generate_cert()
        wss_server = await websockets.serve(self.handle_client, "0.0.0.0", WSS_PORT, ssl=ssl_context, ping_interval=None)
        logging.info(f"Serveur WSS lancé sur wss://{DOMAIN}:{WSS_PORT}")

        await asyncio.Future()  # Exécution infinie

    def _load_or_generate_cert(self):
        """
        Charge un certificat Let's Encrypt s'il existe, sinon le génère automatiquement via certbot.
        """
        cert_path = f"/etc/letsencrypt/live/{DOMAIN}/fullchain.pem"
        key_path = f"/etc/letsencrypt/live/{DOMAIN}/privkey.pem"

        if not os.path.exists(cert_path) or not os.path.exists(key_path):
            logging.warning("Aucun certificat Let's Encrypt trouvé. Tentative de génération...")
            os.system(f"sudo certbot certonly --standalone -d {DOMAIN} --agree-tos -m admin@{DOMAIN} --non-interactive || true")

        if not os.path.exists(cert_path) or not os.path.exists(key_path):
            logging.warning("⚠️ Impossible de générer un certificat valide. Passage en mode auto-signé.")
            cert_dir = "/etc/ssl/kighmu"
            os.makedirs(cert_dir, exist_ok=True)
            os.system(f"openssl req -x509 -newkey rsa:2048 -nodes -keyout {cert_dir}/key.pem -out {cert_dir}/cert.pem -days 365 -subj '/CN={DOMAIN}'")
            cert_path = f"{cert_dir}/cert.pem"
            key_path = f"{cert_dir}/key.pem"

        ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ssl_context.load_cert_chain(certfile=cert_path, keyfile=key_path)
        return ssl_context


# ---------------------------------------------------------
# MAIN
# ---------------------------------------------------------
if __name__ == "__main__":
    logging.info("🚀 Démarrage du serveur WebSocket/SSH avancé...")
    tunnel = WSSTunnelServer()
    try:
        asyncio.run(tunnel.start_servers())
    except KeyboardInterrupt:
        logging.info("🛑 Arrêt manuel du serveur.")
    except Exception as e:
        logging.error(f"Erreur critique : {e}")
