import asyncio
import ssl
import websockets
from websockets.exceptions import ConnectionClosedOK, ConnectionClosedError

def ask_domain():
    domain = input("Entrez le nom de domaine (exemple: monserveur.exemple.com) : ").strip()
    return domain

def create_ssl_context(domain):
    CERT_FILE = f"/etc/letsencrypt/live/{domain}/fullchain.pem"
    KEY_FILE = f"/etc/letsencrypt/live/{domain}/privkey.pem"
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_ctx.load_cert_chain(CERT_FILE, KEY_FILE)
    return ssl_ctx

async def ssh_wss_tunnel_handler(websocket, path, ssh_host='127.0.0.1', ssh_port=22):
    print(f"Nouvelle connexion WSS de {websocket.remote_address}")

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
    domain = ask_domain()
    ssl_context = create_ssl_context(domain)

    wss_host = "0.0.0.0"
    wss_port = 8443

    async def handler(websocket, path):
        await ssh_wss_tunnel_handler(websocket, path)

    try:
        server = await websockets.serve(handler, wss_host, wss_port, ssl=ssl_context)
        print(f"Serveur WSS démarré sur {wss_host}:{wss_port} avec domaine {domain}")
        await server.wait_closed()
    except Exception as e:
        print(f"Erreur serveur WSS : {e}")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("Arrêt du serveur WSS")
