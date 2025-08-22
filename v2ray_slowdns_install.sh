#!/bin/bash
# ==============================================
# v2ray_slowdns_install.sh - Installation et configuration V2Ray SlowDNS
# ==============================================

INSTALL_DIR="$HOME/Kighmu"
CONFIG_PATH="/usr/local/etc/v2ray_slowdns/config.json"
SERVICE_NAME="v2ray-slowdns"
PORT=5304  # Port par défaut pour V2Ray WS
UUID=$(cat /proc/sys/kernel/random/uuid)

# Fichiers SlowDNS générés automatiquement
SLOWDNS_DIR="/etc/slowdns"
NS_FILE="$SLOWDNS_DIR/ns.txt"
PUB_KEY_FILE="$SLOWDNS_DIR/server.pub"

# Créer dossier config si nécessaire
mkdir -p "$(dirname "$CONFIG_PATH")"

# Vérifier que la clé publique SlowDNS existe
if [ ! -f "$PUB_KEY_FILE" ]; then
    echo "Clé publique SlowDNS introuvable ! Assurez-vous que le script VPS a été exécuté correctement."
    exit 1
fi

PUB_KEY=$(cat "$PUB_KEY_FILE")

# Demander le namespace si non défini
if [ ! -f "$NS_FILE" ]; then
    read -p "Entrez le namespace (NS) pour V2Ray SlowDNS : " NS
    if [[ -z "$NS" ]]; then
        echo "Namespace invalide. Abandon."
        exit 1
    fi
    echo "$NS" > "$NS_FILE"
else
    NS=$(cat "$NS_FILE")
fi

# Installer V2Ray si nécessaire
if ! command -v v2ray >/dev/null 2>&1; then
    echo "Installation de V2Ray..."
    bash "$INSTALL_DIR/xray_installe.sh"
else
    echo "V2Ray déjà installé."
fi

# Créer fichier de configuration V2Ray SlowDNS avec WS path correct (/kighmu)
cat > "$CONFIG_PATH" <<EOF
{
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "alterId": 0,
            "email": "user@$NS"
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
      "protocol": "freedom"
    }
  ]
}
EOF

# Activer et démarrer le service V2Ray SlowDNS
if systemctl list-unit-files | grep -q "$SERVICE_NAME"; then
    systemctl restart "$SERVICE_NAME"
else
    # Créer service systemd si nécessaire
    cat > /etc/systemd/system/$SERVICE_NAME.service <<EOL
[Unit]
Description=V2Ray SlowDNS Service
After=network.target

[Service]
ExecStart=/usr/local/bin/v2ray -config $CONFIG_PATH
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
fi

echo "Installation et configuration du tunnel V2Ray SlowDNS (WS TCP port $PORT)"
echo "Namespace : $NS"
echo "UUID initial : $UUID"
echo "Clé publique SlowDNS : $PUB_KEY"
