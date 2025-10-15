#!/usr/bin/env python3
# =========================================================
# WS/WSS Tunnel Server - Kighmu VPS Manager (Safe Test Version)
# Version : 2.3 - Handshake safe + bannière client
# =========================================================

import asyncio
import websockets
import ssl
import os
import sys
import logging
import traceback

# ---------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------
WS_PORT = 8880   # WebSocket non sécurisé
WSS_PORT = 443   # WebSocket sécurisé
LOG_FILE = "/var/log/ws_wss_server.log"
CUSTOM_HANDSHAKE_REASON = "Dinda Putri As Rerechan02"

# Domaine
DOMAIN = "localhost"
if os.path.exists(os.path.expanduser("~/.kighmu_info")):
    with open(os.path.expanduser("~/.kighmu_info")) as f:
        for line in f:
            if line.startswith("DOMAIN="):
                DOMAIN = line.split("=", 1)[1].strip()
                break

# Logging
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout)
    ]
)

log_main = logging.getLogger("ws_wss.main")

# ---------------------------------------------------------
# CLASSE DE SERVEUR WS SAFE
# ---------------------------------------------------------
class SafeWSServer:

    async def handle_client(self, websocket, path):
        client_ip = websocket.remote_address[0] if websocket.remote_address else "unknown"

        # --- Log handshake personnalisé ---
        handshake_line = f"HTTP/1.1 101 {CUSTOM_HANDSHAKE_REASON} Switching Protocols"
        log_main.info(handshake_line)
        log_main.info(f"Nouvelle connexion WebSocket de {client_ip} sur {path}")

        # --- Envoi de la bannière au client ---
        try:
            await websocket.send(f"💡 Handshake reçu: {CUSTOM_HANDSHAKE_REASON}")
        except Exception as e:
            log_main.warning(f"Impossible d’envoyer la bannière au client {client_ip}: {e}")

        # --- Tentative de tunnel SSH safe ---
        ssh_host = "127.0.0.1"
        ssh_port = 22
        try:
            reader, writer = await asyncio.open_connection(ssh_host, ssh_port)
            log_main.info(f"Tunnel SSH établi pour {client_ip}")

            async def ws_to_ssh():
                try:
                    async for message in websocket:
                        if isinstance(message, bytes):
                            writer.write(message)
                            await writer.drain()
                except Exception as e:
                    log_main.warning(f"WS->SSH error: {e}")
                finally:
                    try:
                        writer.close()
                        await writer.wait_closed()
                    except Exception:
                        pass

            async def ssh_to_ws():
                try:
                    while True:
                        data = await reader.read(4096)
                        if not data:
                            break
                        await websocket.send(data)
                except Exception as e:
                    log_main.warning(f"SSH->WS error: {e}")
                finally:
                    try:
                        await websocket.close()
                    except Exception:
                        pass

            await asyncio.gather(ws_to_ssh(), ssh_to_ws())

        except Exception as e:
            log_main.warning(f"Tunnel SSH inaccessible pour {client_ip}, on continue sans SSH: {e}")

        log_main.info(f"Connexion fermée pour {client_ip}")

    async def start_servers(self):
        # Serveur WS
        await websockets.serve(self.handle_client, "0.0.0.0", WS_PORT, ping_interval=None)
        log_main.info(f"Serveur WS lancé sur ws://{DOMAIN}:{WS_PORT}")

        # Serveur WSS
        ssl_context = self._load_or_generate_cert()
        await websockets.serve(self.handle_client, "0.0.0.0", WSS_PORT, ssl=ssl_context, ping_interval=None)
        log_main.info(f"Serveur WSS lancé sur wss://{DOMAIN}:{WSS_PORT}")

        await asyncio.Future()  # Exécution infinie

    def _load_or_generate_cert(self):
        cert_path = f"/etc/letsencrypt/live/{DOMAIN}/fullchain.pem"
        key_path = f"/etc/letsencrypt/live/{DOMAIN}/privkey.pem"

        if not os.path.exists(cert_path) or not os.path.exists(key_path):
            cert_dir = "/etc/ssl/kighmu"
            os.makedirs(cert_dir, exist_ok=True)
            os.system(f"openssl req -x509 -newkey rsa:2048 -nodes -keyout {cert_dir}/key.pem -out {cert_dir}/key.pem -days 365 -subj '/CN={DOMAIN}' 2>&1 || true")
            cert_path = f"{cert_dir}/cert.pem"
            key_path = f"{cert_dir}/key.pem"

        ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ssl_context.load_cert_chain(certfile=cert_path, keyfile=key_path)
        log_main.info(f"TLS: certificat chargé (cert={cert_path}, key={key_path})")
        return ssl_context


# ---------------------------------------------------------
# MAIN
# ---------------------------------------------------------
if __name__ == "__main__":
    log_main.info("🚀 Démarrage du serveur WS/WSS safe (bannière + SSH safe)...")
    server = SafeWSServer()
    try:
        asyncio.run(server.start_servers())
    except KeyboardInterrupt:
        log_main.info("🛑 Arrêt manuel du serveur.")
    except Exception as e:
        log_main.error(f"Erreur critique : {e}")
        traceback.print_exc()
