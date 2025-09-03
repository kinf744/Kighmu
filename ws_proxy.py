#!/usr/bin/env python3
import asyncio
import websockets

LOCAL_HOST = '127.0.0.1'
LOCAL_PORT = 80
REMOTE_WS_URI = 'ws://localhost:12345'  # Adapter vers le serveur WebSocket cible

async def proxy_handler(client_ws, path):
    async with websockets.connect(REMOTE_WS_URI) as remote_ws:
        async def forward(ws_from, ws_to):
            async for message in ws_from:
                await ws_to.send(message)

        await asyncio.gather(forward(client_ws, remote_ws), forward(remote_ws, client_ws))

async def main():
    async with websockets.serve(proxy_handler, LOCAL_HOST, LOCAL_PORT):
        print(f"WebSocket proxy listening on ws://{LOCAL_HOST}:{LOCAL_PORT}")
        await asyncio.Future()  # Run forever

if __name__ == "__main__":
    asyncio.run(main())
    
