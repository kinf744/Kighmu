#!/usr/bin/env python3
import os
import subprocess
import sys

def run_command(command):
    """Exécute une commande système et affiche la sortie."""
    print(f"Executing: {command}")
    result = subprocess.run(command, shell=True, text=True, capture_output=True)
    if result.returncode != 0:
        print(f"Error: {result.stderr.strip()}")
    else:
        print(result.stdout.strip())

def install_python_packages():
    """Installe les paquets Python nécessaires."""
    print("Installing required Python packages...")
    run_command(f"{sys.executable} -m pip install --upgrade pip")
    run_command(f"{sys.executable} -m pip install sshtunnel paramiko")

def main():
    # Demande obligatoire du domaine
    domain = input("Veuillez entrer le nom de domaine (ex: ws.example.com) pour le tunnel SSH WebSocket (obligatoire) : ").strip()
    if not domain:
        print("Erreur : un domaine est requis pour continuer.")
        sys.exit(1)

    # Vérification des droits root
    if os.geteuid() != 0:
        print("Erreur : ce script doit être lancé en root (utilisez sudo).")
        sys.exit(1)

    # Mise à jour et installation des dépendances système
    run_command("apt-get update -y")
    run_command("apt-get install -y nodejs npm screen python3-pip")

    # Installation de wstunnel globalement via npm
    run_command("npm install -g wstunnel")

    # Installation des paquets Python nécessaires
    install_python_packages()

    # Suppression éventuelle de la session screen existante nommée sshws
    run_command("screen -S sshws -X quit || true")

    # Démarrage du tunnel SSH WebSocket dans une session screen détachée sur le port 8880
    run_command("screen -dmS sshws wstunnel -s 8880")

    # Payload WebSocket à utiliser côté client
    payload = (
        "GET /socket HTTP/1.1[crlf]"
        f"Host: {domain}[crlf]"
        "Upgrade: websocket[crlf][crlf]"
    )

    print("\nInstallation terminée avec succès.")
    print(f"Le tunnel SSH WebSocket est en écoute sur le port 8880 avec le domaine : {domain}")
    print("\nUtilisez le payload suivant pour vous connecter en WebSocket SSH :\n")
    print(payload)
    print("\nPour accéder à la session screen : screen -r sshws")
    print("Pour relancer manuellement le tunnel : screen -dmS sshws wstunnel -s 8880")

if __name__ == "__main__":
    main()
    
