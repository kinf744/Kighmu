import asyncio
import ssl
import websockets
import os
from websockets.exceptions import ConnectionClosedOK, ConnectionClosedError

CONF_FILE = "/etc/proxy_wss/domain.conf"

def get_domain():
    """Récupère le domaine depuis /etc/proxy_wss/domain.conf ou demande à l'utilisateur"""
    if os.path.exists(CONF_FILE):
        with open(CONF_FILE, "r") as f:
            domain = f.read().strip()
            if domain:
                print(f"[+] Domaine chargé depuis {CONF_FILE}: {domain}")
                return domain
    # Fallback si pas trouvé (exécution manuelle)
    domain = input("Entrez le nom de domaine (exemple: monserveur.exemple.com) : ").strip()
    return domain

def create_ssl_context(domain):
    """Crée le contexte SSL basé sur les certificats Let's Encrypt"""
    CERT_FILE = f"/etc/letsencrypt/live/{domain}/fullchain.pem"
    KEY_FILE = f"/etc/letsencrypt/live/{domain}/privkey.pem"

    if not (os.path.exists(CERT_FILE) and os.path.exists(KEY_FILE)):
        raise FileNotFoundError(
            f"❌ Certificats introuvables pour le domaine {domain}\n"
            f"Vérifiez que Let's Encrypt est bien configuré:\n"
            f"  certbot certonly --standalone -d {domain}"
        )

    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_ctx.load_cert_chain(CERT_FILE, KEY_FILE)
    return ssl_ctx

async def ssh_wss_tunnel_handler(websocket, path, ssh_host='127.0.0.1', ssh_port=22):
    print(f"Nouvelle connexion WSS de {websocket.remote_address}")

    # Extra: lecture éventuelle d'un payload custom
    auth_payload = websocket.request_headers.get("X-Auth-Payload")
    if auth_payload:
        print(f"Payload AUTH reçu : {auth_payload}")

    try:
        reader_tcp, writer_tcp = await asyncio.open_connection(ssh_host, ssh_port)
    except Exception as e:
        print(f"Erreur connexion SSH locale : {e}")
        await websocket.close()
        return

    async def websocket_to_tcp():
        try:
            async for message in websocket:
                if isinstance(message, str):
                    message = message.encode()
                writer_tcp.write(message)
                await writer_tcp.drain()
        except (ConnectionClosedOK, ConnectionClosedError):
            pass
        except Exception as e:
            print(f"Erreur websocket_to_tcp : {e}")
        finally:
            writer_tcp.close()
            await writer_tcp.wait_closed()

    async def tcp_to_websocket():
        try:
            while True:
                data = await reader_tcp.read(1024)
                if not data:
                    break
                await websocket.send(data)
        except (ConnectionClosedOK, ConnectionClosedError):
            pass
        except Exception as e:
            print(f"Erreur tcp_to_websocket : {e}")
        finally:
            await websocket.close()

    await asyncio.gather(websocket_to_tcp(), tcp_to_websocket())
    print(f"Connexion fermée : {websocket.remote_address}")

async def main():
    domain = get_domain()
    ssl_context = create_ssl_context(domain)

    wss_host = "0.0.0.0"
    wss_port = 8443

    async def handler(websocket, path):
        await ssh_wss_tunnel_handler(websocket, path)

    try:
        server = await websockets.serve(handler, wss_host, wss_port, ssl=ssl_context)
        print(f"✅ Serveur WSS démarré sur {wss_host}:{wss_port} avec domaine {domain}")
        await server.wait_closed()
    except Exception as e:
        print(f"Erreur serveur WSS : {e}")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("Arrêt du serveur WSS")
    
