#!/bin/bash
# udp_custom.sh
# Installation et configuration UDP Custom pour HTTP Custom VPN

set -e

INSTALL_DIR="/root/udp-custom"
CONFIG_FILE="$INSTALL_DIR/config.json"
UDP_PORT=54000

echo "+--------------------------------------------+"
echo "|             INSTALLATION UDP CUSTOM         |"
echo "+--------------------------------------------+"

echo "Installation des dépendances..."
apt-get update
apt-get install -y git curl build-essential libssl-dev jq iptables

# Cloner le dépôt udp-custom si non présent
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Clonage du dépôt udp-custom..."
    git clone https://github.com/http-custom/udp-custom.git "$INSTALL_DIR"
else
    echo "udp-custom déjà présent, mise à jour..."
    cd "$INSTALL_DIR"
    git pull
fi

cd "$INSTALL_DIR"

# Compilation du projet udp-custom (si Makefile présent)
if [ -f "Makefile" ]; then
    echo "Compilation du projet udp-custom..."
    make clean && make
fi

# Vérification du binaire udp-custom
if [ ! -x "./udp-custom" ]; then
    echo "Erreur: Le binaire udp-custom n'a pas été compilé ou est manquant."
    exit 1
fi

# Configuration du port UDP dans config.json
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Création du fichier de configuration UDP custom..."
    cat > "$CONFIG_FILE" << EOF
{
  "server_port": $UDP_PORT,
  "exclude_port": [],
  "udp_timeout": 600,
  "dns_cache": true
}
EOF
else
    echo "Modification du port dans la configuration existante..."
    jq ".server_port = $UDP_PORT" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
fi

# Ouverture du port UDP dans iptables
echo "Ouverture du port UDP $UDP_PORT dans iptables..."
iptables -I INPUT -p udp --dport $UDP_PORT -j ACCEPT

# Démarrage du démon udp-custom en arrière-plan
echo "Démarrage du démon udp-custom sur le port $UDP_PORT..."
nohup "$INSTALL_DIR/udp-custom" -c "$CONFIG_FILE" > /var/log/udp_custom.log 2>&1 &

sleep 3

if pgrep -f "udp-custom" > /dev/null; then
    echo "UDP Custom démarré avec succès sur le port $UDP_PORT."
else
    echo "Erreur: UDP Custom ne s'est pas lancé correctement."
fi

echo "+--------------------------------------------+"
echo "|          Configuration terminée            |"
echo "|  Configure HTTP Custom avec IP du serveur, |"
echo "|  port UDP $UDP_PORT, et activez UDP Custom |"
echo "+--------------------------------------------+"
