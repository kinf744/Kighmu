#!/usr/bin/env python3
# =========================================================
# WS Tunnel Server - Kighmu VPS Manager (WS-only)
# Auteur : Kinf744 (adapté)
# Version : 3.0 - WS uniquement, handshake personnalisé
# =========================================================

import asyncio
import websockets
import os
import sys
import logging
import traceback

# -------------------- CONFIG --------------------
DEFAULT_SSH_HOST = "127.0.0.1"
DEFAULT_SSH_PORT = 22
WS_PORT = 8880
LOG_FILE = "/var/log/ws_wss_server.log"
CUSTOM_HANDSHAKE_REASON = "@Dinda_Putri_As_Rerechan02"

# Domaine optionnel
DOMAIN = "localhost"
if os.path.exists(os.path.expanduser("~/.kighmu_info")):
    with open(os.path.expanduser("~/.kighmu_info")) as f:
        for line in f:
            if line.startswith("DOMAIN="):
                DOMAIN = line.split("=", 1)[1].strip()
                break

# -------------------- Logging --------------------
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] %(message)s",
    handlers=[logging.FileHandler(LOG_FILE), logging.StreamHandler(sys.stdout)]
)
log_main = logging.getLogger("ws_wss.main")
log_ws = logging.getLogger("ws_wss.ws")
log_ssh = logging.getLogger("ws_wss.ssh")

# -------------------- Tunnel WS -> SSH --------------------
class WSTunnelServer:
    def __init__(self, ssh_host=DEFAULT_SSH_HOST, ssh_port=DEFAULT_SSH_PORT):
        self.ssh_host = ssh_host
        self.ssh_port = ssh_port

    async def handle_client(self, websocket, path):
        try:
            client_ip = websocket.remote_address[0]
        except Exception:
            client_ip = "unknown"

        # --- Log handshake personnalisé ---
        handshake_line = f"HTTP/1.1 101 {CUSTOM_HANDSHAKE_REASON} Switching Protocols"
        log_main.info(handshake_line)

        log_main.info(f"Nouvelle connexion WebSocket de {client_ip} sur {path}")

        try:
            # Connexion au SSH local
            reader, writer = await asyncio.open_connection(self.ssh_host, self.ssh_port)
            log_ssh.info(f"Tunnel SSH établi pour {client_ip}")

            async def ws_to_ssh():
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

# -------------------- Serveur --------------------
async def main():
    server = WSTunnelServer()
    ws_server = await websockets.serve(server.handle_client, "0.0.0.0", WS_PORT, ping_interval=None)
    log_main.info(f"Serveur WS lancé sur ws://{DOMAIN}:{WS_PORT}")
    await asyncio.Future()  # Exécution infinie

if __name__ == "__main__":
    log_main.info("🚀 Démarrage du serveur WS-only (handshake personnalisé)...")
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log_main.info("🛑 Arrêt manuel du serveur.")
    except Exception as e:
        log_main.error(f"Erreur critique : {e}")
        traceback.print_exc()
