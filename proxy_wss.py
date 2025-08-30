#!/usr/bin/env python3
import subprocess
import shutil
import sys

# Fonction pour exécuter une commande shell
def run(cmd):
    print(f"[*] Exécution : {cmd}")
    result = subprocess.run(cmd, shell=True)
    if result.returncode != 0:
        print(f"Erreur lors de l'exécution : {cmd}")
        sys.exit(1)

# Demander l'adresse du serveur distant
SERVER = input("Entrez le domaine ou IP du serveur distant : ").strip()
if not SERVER:
    print("Erreur : vous devez entrer un domaine ou une IP.")
    sys.exit(1)

LOCAL_PORT = 8880
WS_PORT = 80

# Vérifier les dépendances
deps = ["wget", "curl", "ssh", "sshpass"]
for dep in deps:
    if not shutil.which(dep):
        print(f"[*] Installation de {dep}...")
        run(f"sudo apt update && sudo apt install -y {dep}")

# Installer wstunnel si nécessaire
if not shutil.which("wstunnel"):
    print("[*] Installation de wstunnel...")
    run("wget https://github.com/erebe/wstunnel/releases/download/v4.6.3/wstunnel-linux-amd64 -O /usr/local/bin/wstunnel")
    run("chmod +x /usr/local/bin/wstunnel")

# Stopper les anciens tunnels
run(f"pkill -f 'wstunnel.*{LOCAL_PORT}'")

# Démarrer le tunnel SSH via WebSocket
print(f"[*] Démarrage du tunnel SSH via WebSocket vers {SERVER}...")
cmd = f"wstunnel -t 127.0.0.1:{LOCAL_PORT}:{SERVER}:22 -s ws://{SERVER}:{WS_PORT}/ &"
run(cmd)
print(f"[*] Tunnel actif sur 127.0.0.1:{LOCAL_PORT}")
