#!/bin/bash

PROXY_PORT=8080
SCRIPT_PATH="/usr/local/bin/KIGHMUPROXY.py"
LOG_FILE="/var/log/kighmuproxy.log"
SCRIPT_URL="https://raw.githubusercontent.com/ton-utilisateur/ton-depot/main/KIGHMUPROXY.py"  # Mets ici le vrai lien

echo "Vérification de Python3..."
if ! command -v python3 >/dev/null 2>&1; then
    sudo apt update
    sudo apt install -y python3 python3-pip
fi

echo "Téléchargement du script KIGHMUPROXY proxy SOCKS..."
sudo wget -q -O "$SCRIPT_PATH" "$SCRIPT_URL"
sudo chmod +x "$SCRIPT_PATH"

echo "Arrêt d'un ancien proxy KIGHMUPROXY en cours d'exécution..."
sudo pkill -f "$SCRIPT_PATH" || true

echo "Démarrage du proxy SOCKS KIGHMUPROXY sur le port $PROXY_PORT..."
nohup sudo python3 "$SCRIPT_PATH" $PROXY_PORT > "$LOG_FILE" 2>&1 &

sleep 3

if pgrep -f "$SCRIPT_PATH" > /dev/null; then
    echo "Proxy SOCKS KIGHMUPROXY lancé sur le port $PROXY_PORT."
    echo "Logs disponibles dans $LOG_FILE"
else
    echo "Erreur : échec de démarrage du proxy. Consultez $LOG_FILE."
fi

echo "Ouverture du port $PROXY_PORT dans le firewall (UFW)..."
sudo ufw allow $PROXY_PORT/tcp
