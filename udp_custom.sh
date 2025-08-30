#!/bin/bash
# udp_custom.sh
# Installation et configuration UDP Custom pour HTTP Custom VPN

set -e

INSTALL_DIR="/root/udp-custom"
CONFIG_FILE="$INSTALL_DIR/config/config.json"
BIN_PATH="$INSTALL_DIR/bin/udp-custom-linux-amd64"
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

# Vérifier la présence et droits du binaire précompilé
if [ ! -x "$BIN_PATH" ]; then
    echo "Le binaire $BIN_PATH n'est pas exécutable, changement de permission..."
    chmod +x "$BIN_PATH"
fi

if [ ! -x "$BIN_PATH" ]; then
    echo "Erreur: Le binaire $BIN_PATH est manquant ou non exécutable."
    exit 1
fi

# Configuration du port UDP dans config.json
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Création du fichier de configuration UDP custom..."
    mkdir -p "$(dirname "$CONFIG_FILE")"
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

# Création du fichier de service systemd pour udp-custom
SERVICE_PATH="/etc/systemd/system/udp-custom.service"

echo "Création du service systemd udp-custom..."

cat > "$SERVICE_PATH" << EOF
[Unit]
Description=UDP Custom Service for HTTP Custom VPN
After=network.target

[Service]
Type=simple
User=root
ExecStart=$BIN_PATH -c $CONFIG_FILE
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# Rechargement des services systemd pour prendre en compte le nouveau service
systemctl daemon-reload

# Activation du service au démarrage
systemctl enable udp-custom.service

# Démarrage immédiat du service
systemctl start udp-custom.service

sleep 3

if systemctl is-active --quiet udp-custom.service; then
    echo "UDP Custom démarré avec succès sur le port $UDP_PORT via systemd."
else
    echo "Erreur: UDP Custom ne s'est pas lancé correctement via systemd."
fi

echo "+--------------------------------------------+"
echo "|          Configuration terminée            |"
echo "|  Configure HTTP Custom avec IP du serveur, |"
echo "|  port UDP $UDP_PORT, et activez UDP Custom |"
echo "|  (service systemd activé pour démarrage)   |"
echo "+--------------------------------------------+"
