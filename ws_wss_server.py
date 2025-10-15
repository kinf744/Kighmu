#!/usr/bin/env python3
# =========================================================
# WS Tunnel Server - Version épurée (WS only)
# Version : 2.7 - WS uniquement, handshake visible
# =========================================================

import asyncio
import websockets
import os
import sys
import logging
import traceback

WS_PORT = 8880   # WebSocket non sécurisé
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

class WSTunnelServer:

    async def handle_client(self, websocket, path):
        client_ip = websocket.remote_address[0] if websocket.remote_address else "unknown"
        log_main.info(f"Nouvelle connexion WebSocket de {client_ip} sur {path}")

        # --- Message visible côté client après handshake ---
        try:
            await websocket.send(f"💡 Handshake reçu: {CUSTOM_BANNER}")
        except Exception:
            pass

        # --- Tentative tunnel SSH ---
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

    async def start_server(self):
        # WS uniquement
        await websockets.serve(self.handle_client, "0.0.0.0", WS_PORT, ping_interval=None)
        log_main.info(f"Serveur WS lancé sur ws://{DOMAIN}:{WS_PORT}")
        await asyncio.Future()  # run forever

# ---------------------------------------------------------
# MAIN
# ---------------------------------------------------------
if __name__ == "__main__":
    log_main.info("🚀 Démarrage du serveur WS uniquement, handshake visible...")
    server = WSTunnelServer()
    try:
        asyncio.run(server.start_server())
    except KeyboardInterrupt:
        log_main.info("🛑 Arrêt manuel du serveur.")
    except Exception as e:
        log_main.error(f"Erreur critique : {e}")
        traceback.print_exc()
