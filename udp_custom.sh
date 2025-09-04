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

# Fonction création service systemd
create_systemd_service() {
  SERVICE_PATH="/etc/systemd/system/udp_custom.service"

  echo "Création du fichier systemd udp_custom.service..."

  cat <<EOF | sudo tee "$SERVICE_PATH" > /dev/null
[Unit]
Description=UDP Custom Service for HTTP Custom VPN
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=$BIN_PATH -c $CONFIG_FILE
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=udp-custom

[Install]
WantedBy=multi-user.target
EOF

  echo "Reload systemd daemon, enable and start udp_custom service..."
  sudo systemctl daemon-reload
  sudo systemctl enable udp_custom.service
  sudo systemctl restart udp_custom.service
  echo "Service udp_custom activé et démarré."
}

# Démarrage du démon udp-custom en arrière-plan
echo "Démarrage du démon udp-custom sur le port $UDP_PORT..."
nohup "$BIN_PATH" -c "$CONFIG_FILE" > /var/log/udp_custom.log 2>&1 &

sleep 3

if pgrep -f "udp-custom-linux-amd64" > /dev/null; then
    echo "UDP Custom démarré avec succès sur le port $UDP_PORT."
    create_systemd_service
else
    echo "Erreur: UDP Custom ne s'est pas lancé correctement."
fi

echo "+--------------------------------------------+"
echo "|          Configuration terminée            |"
echo "|  Configure HTTP Custom avec IP du serveur, |"
echo "|  port UDP $UDP_PORT, et activez UDP Custom |"
echo "+--------------------------------------------+"
