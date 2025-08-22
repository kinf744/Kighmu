#!/bin/bash
# v2ray_slowdns_install.sh
# Installation et configuration du tunnel V2Ray SlowDNS WS TCP
# Utilise le même namespace et la même clé publique que SSH SlowDNS

set -e

SERVICE_NAME="v2ray-slowdns"
INSTALL_DIR="/usr/local/etc/v2ray_slowdns"
BIN_PATH="/usr/local/bin/v2ray"
CONFIG_PATH="$INSTALL_DIR/config.json"
TCP_PORT=5304

# Fichiers du SSH SlowDNS pour NS et clé publique
SSH_NS_FILE="/etc/slowdns/ns.txt"
SSH_PUB_KEY_FILE="/etc/slowdns/server.pub"

# Récupérer le NS et la clé publique depuis SSH SlowDNS
if [[ -f "$SSH_NS_FILE" ]]; then
    NAMESPACE=$(cat "$SSH_NS_FILE")
else
    echo "Namespace SSH SlowDNS introuvable ($SSH_NS_FILE)."
    read -rp "Entrez le namespace (NS) pour V2Ray SlowDNS : " NAMESPACE
    [[ -z "$NAMESPACE" ]] && { echo "Namespace non fourni, arrêt."; exit 1; }
fi

if [[ -f "$SSH_PUB_KEY_FILE" ]]; then
    PUB_KEY=$(cat "$SSH_PUB_KEY_FILE")
else
    echo "Clé publique SSH SlowDNS introuvable ($SSH_PUB_KEY_FILE)."
    PUB_KEY="inconnue"
fi

echo "Installation et configuration du tunnel V2Ray SlowDNS (WS TCP port $TCP_PORT)"
echo "Namespace : $NAMESPACE"

# Installer V2Ray si non présent
if ! command -v $BIN_PATH &> /dev/null; then
    echo "V2Ray non trouvé, installation..."
    bash <(curl -L -s https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
else
    echo "V2Ray déjà installé."
fi

# Créer le dossier de configuration
mkdir -p "$INSTALL_DIR"

# UUID initial pour le service
UUID=$(cat /proc/sys/kernel/random/uuid)

# Créer le fichier de configuration V2Ray
cat > "$CONFIG_PATH" <<EOF
{
  "inbounds": [
    {
      "port": $TCP_PORT,
      "listen": "0.0.0.0",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/kighmu"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

echo "Fichier de configuration créé : $CONFIG_PATH"

# Création du service systemd
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"

sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=V2Ray SlowDNS Tunnel Service (WS)
After=network.target

[Service]
Type=simple
User=root
ExecStart=$BIN_PATH run -config $CONFIG_PATH
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Activer et démarrer le service
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

# Vérification du port
sleep 2
if ss -lnpt | grep -q ":$TCP_PORT "; then
    echo "V2Ray SlowDNS WS fonctionne sur le port $TCP_PORT."
    echo "UUID initial : $UUID"
    echo "Namespace (NS) : $NAMESPACE"
    echo "Clé publique : $PUB_KEY"
else
    echo "Erreur : le service n'écoute pas sur le port $TCP_PORT."
    echo "Vérifiez avec : sudo systemctl status $SERVICE_NAME"
fi
