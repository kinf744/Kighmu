#!/usr/bin/env python3
# =========================================================
# WS/WSS Tunnel Server - Lacasita-style Optimized
# Version : 2.6 - Handshake HTTP/1.1 101 personnalisé visible
# =========================================================

import asyncio
import websockets
import ssl
import os
import sys
import logging
import traceback

WS_PORT = 8880
WSS_PORT = 443
LOG_FILE = "/var/log/ws_wss_server.log"
CUSTOM_BANNER = "@Dinda_Putri_As_Rerechan02"

DOMAIN = "localhost"
if os.path.exists(os.path.expanduser("~/.kighmu_info")):
    with open(os.path.expanduser("~/.kighmu_info")) as f:
        for line in f:
            if line.startswith("DOMAIN="):
                DOMAIN = line.split("=", 1)[1].strip()
                break

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] %(message)s",
    handlers=[logging.FileHandler(LOG_FILE), logging.StreamHandler(sys.stdout)]
)
log_main = logging.getLogger("ws_wss.main")

class OptimizedServer:

    async def handle_client(self, websocket, path):
        client_ip = websocket.remote_address[0] if websocket.remote_address else "unknown"
        log_main.info(f"Nouvelle connexion WebSocket de {client_ip} sur {path}")

        # --- Message visible côté client après handshake ---
        try:
            await websocket.send(f"💡 Handshake reçu: {CUSTOM_BANNER}")
        except Exception:
            pass

        # --- Tunnel SSH (optionnel) ---
        ssh_host = "127.0.0.1"
        ssh_port = 22
        try:
            reader, writer = await asyncio.open_connection(ssh_host, ssh_port)
            log_main.info(f"Tunnel SSH établi pour {client_ip}")

            async def ws_to_ssh():
                try:
                    async for msg in websocket:
                        if isinstance(msg, bytes):
                            writer.write(msg)
                            await writer.drain()
                except Exception:
                    pass
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
                except Exception:
                    pass
                finally:
                    try:
                        await websocket.close()
                    except Exception:
                        pass

            await asyncio.gather(ws_to_ssh(), ssh_to_ws())

        except Exception:
            log_main.warning(f"Tunnel SSH inaccessible pour {client_ip}, on continue sans SSH")

        log_main.info(f"Connexion fermée pour {client_ip}")

    async def start_servers(self):
        # WS
        await websockets.serve(self.handle_client, "0.0.0.0", WS_PORT, ping_interval=None)
        log_main.info(f"Serveur WS lancé sur ws://{DOMAIN}:{WS_PORT}")

        # WSS
        ssl_ctx = self._load_or_generate_cert()
        await websockets.serve(self.handle_client, "0.0.0.0", WSS_PORT, ssl=ssl_ctx, ping_interval=None)
        log_main.info(f"Serveur WSS lancé sur wss://{DOMAIN}:{WSS_PORT}")

        await asyncio.Future()  # run forever

    def _load_or_generate_cert(self):
        cert_path = f"/etc/letsencrypt/live/{DOMAIN}/fullchain.pem"
        key_path = f"/etc/letsencrypt/live/{DOMAIN}/privkey.pem"
        if not os.path.exists(cert_path) or not os.path.exists(key_path):
            cert_dir = "/etc/ssl/kighmu"
            os.makedirs(cert_dir, exist_ok=True)
            os.system(f"openssl req -x509 -newkey rsa:2048 -nodes "
                      f"-keyout {cert_dir}/key.pem -out {cert_dir}/cert.pem -days 365 "
                      f"-subj '/CN={DOMAIN}' || true")
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
    log_main.info("🚀 Démarrage du serveur WS/WSS Optimized (Handshake 101 personnalisé)...")
    server = OptimizedServer()
    try:
        asyncio.run(server.start_servers())
    except KeyboardInterrupt:
        log_main.info("🛑 Arrêt manuel du serveur.")
    except Exception as e:
        log_main.error(f"Erreur critique : {e}")
        traceback.print_exc()
