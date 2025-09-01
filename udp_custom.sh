#!/bin/bash
# udp_custom_install.sh
# Installation et configuration UDP Custom avec service systemd persistant

set -e

INSTALL_DIR="/root/udp-custom"
CONFIG_FILE="$INSTALL_DIR/config/config.json"
BIN_PATH="$INSTALL_DIR/bin/udp-custom-linux-amd64"
UDP_PORT=54000
SERVICE_FILE="/etc/systemd/system/udp_custom.service"

echo "+--------------------------------------------+"
echo "|             INSTALLATION UDP CUSTOM         |"
echo "+--------------------------------------------+"

echo "Installation des dépendances..."
apt-get update
apt-get install -y git curl build-essential libssl-dev jq iptables iptables-persistent

# Cloner ou mettre à jour le dépôt udp-custom
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Clonage du dépôt udp-custom..."
    git clone https://github.com/http-custom/udp-custom.git "$INSTALL_DIR"
else
    echo "udp-custom déjà présent, mise à jour..."
    cd "$INSTALL_DIR"
    git pull
fi

cd "$INSTALL_DIR"

# Vérifier permissions du binaire
if [ ! -x "$BIN_PATH" ]; then
    echo "Le binaire $BIN_PATH n'est pas exécutable, changement de permission..."
    chmod +x "$BIN_PATH"
fi

# Préparer fichier config
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

echo "Ouverture du port UDP $UDP_PORT dans iptables..."
iptables -I INPUT -p udp --dport $UDP_PORT -j ACCEPT
iptables-save > /etc/iptables/rules.v4

echo "Création du service systemd pour udp-custom..."

sudo tee $SERVICE_FILE > /dev/null << EOF
[Unit]
Description=UDP Custom Tunnel Service
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=600
StartLimitBurst=10

[Service]
Type=simple
ExecStart=$BIN_PATH -c $CONFIG_FILE
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

echo "Rechargement systemd et activation du service..."
systemctl daemon-reload
systemctl enable udp_custom.service
systemctl restart udp_custom.service

sleep 3

if systemctl is-active --quiet udp_custom.service; then
    echo "Service UDP Custom démarré et activé automatiquement au démarrage."
else
    echo "Erreur: échec du démarrage du service UDP Custom."
    echo "Consultez les logs avec : sudo journalctl -u udp_custom.service"
fi

echo "+--------------------------------------------+"
echo "|          Installation terminée             |"
echo "|  Utilisez 'systemctl status udp_custom' pour |"
echo "|  vérifier le status du service.             |"
echo "+--------------------------------------------+"
