#!/usr/bin/env python3
import subprocess
import shutil
import sys

def run(cmd):
    print(f"[*] Exécution : {cmd}")
    try:
        subprocess.run(cmd, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as e:
        print(f"Erreur lors de l'exécution : {cmd}")
        print(e.stderr.decode())
        sys.exit(1)

SERVER = input("Entrez le domaine ou IP du serveur distant : ").strip()
if not SERVER:
    print("Erreur : vous devez entrer un domaine ou une IP.")
    sys.exit(1)

WS_PORT = 80

# Installation des dépendances si manquantes
deps = ["wget", "curl", "ssh", "sshpass"]
for dep in deps:
    if not shutil.which(dep):
        print(f"[*] Installation de {dep}...")
        run(f"sudo apt update && sudo apt install -y {dep}")

# Installation de wstunnel si nécessaire
if not shutil.which("wstunnel"):
    print("[*] Installation de wstunnel...")
    run("wget https://github.com/erebe/wstunnel/releases/download/v4.6.3/wstunnel-linux-amd64 -O /usr/local/bin/wstunnel")
    run("chmod +x /usr/local/bin/wstunnel")

# Lancement du tunnel SSH via WebSocket
print(f"[*] Démarrage du tunnel SSH via WebSocket vers {SERVER}...")
cmd = f"wstunnel -t 22 ws://{SERVER}:{WS_PORT}/ &"
run(cmd)

print(f"[*] Tunnel actif vers {SERVER} sur le port 22 via WebSocket sur le port {WS_PORT}")
