#!/usr/bin/env python3
import subprocess
import shutil
import sys

def run(cmd):
    print(f"[*] Exécution : {cmd}")
    try:
        subprocess.run(cmd, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as e:
        # Ignorer l'erreur pkill si aucun processus trouvé (code retour 1)
        if "pkill" in cmd and e.returncode == 1:
            print("[*] Aucun processus à tuer avec pkill, continuation du script.")
        else:
            print(f"Erreur lors de l'exécution : {cmd}")
            print(e.stderr.decode())
            sys.exit(1)

# Demander le domaine ou IP du serveur distant
SERVER = input("Entrez le domaine ou IP du serveur distant : ").strip()
if not SERVER:
    print("Erreur : vous devez entrer un domaine ou une IP.")
    sys.exit(1)

LOCAL_PORT = 8880
WS_PORT = 80

# Installer les dépendances si manquantes
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

# Arrêter les tunnels wstunnel existants sur le port local (ignore erreur s'il n'y en a pas)
run(f"pkill -f 'wstunnel.*{LOCAL_PORT}'")

# Lancer le tunnel SSH via WebSocket en arrière-plan
print(f"[*] Démarrage du tunnel SSH via WebSocket vers {SERVER}...")
cmd = f"wstunnel -t 127.0.0.1:{LOCAL_PORT}:{SERVER}:22 -s ws://{SERVER}:{WS_PORT}/ &"
run(cmd)

print(f"[*] Tunnel actif sur 127.0.0.1:{LOCAL_PORT}")
            
