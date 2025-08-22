#!/bin/bash
# ==============================================
# v2ray_slowdns_install.sh - Installation et configuration V2Ray SlowDNS
# ==============================================

INSTALL_DIR="$HOME/Kighmu"
CONFIG_PATH="/usr/local/etc/v2ray_slowdns/config.json"
SERVICE_NAME="v2ray-slowdns"
PORT=5304  # Port par défaut pour V2Ray WS

SLOWDNS_DIR="/etc/slowdns"
NS_FILE="$SLOWDNS_DIR/ns.txt"
PUB_KEY_FILE="$SLOWDNS_DIR/server.pub"
UUID_FILE="$INSTALL_DIR/v2ray_uuid.txt"

mkdir -p "$(dirname "$CONFIG_PATH")"
mkdir -p "$INSTALL_DIR"

# Lire Namespace
if [ ! -f "$NS_FILE" ]; then
    echo "Namespace SlowDNS introuvable ($NS_FILE). Assurez-vous que le script principal a été exécuté."
    exit 1
fi
NS=$(cat "$NS_FILE")

# Lire clé publique SlowDNS
if [ ! -f "$PUB_KEY_FILE" ]; then
    echo "Clé publique SlowDNS introuvable ($PUB_KEY_FILE). Assurez-vous que le script principal a été exécuté."
    exit 1
fi
PUB_KEY=$(cat "$PUB_KEY_FILE")

# Utiliser UUID stable, généré une fois
if [ ! -f "$UUID_FILE" ]; then
    UUID=$(cat /proc/sys/kernel/random/uuid)
    echo "$UUID" > "$UUID_FILE"
else
    UUID=$(cat "$UUID_FILE")
fi

# Installer V2Ray si nécessaire
if ! command -v v2ray >/dev/null 2>&1; then
    echo "Installation de V2Ray..."
    bash "$INSTALL_DIR/xray_installe.sh"
else
    echo "V2Ray déjà installé."
fi

# Création fichier config V2Ray SlowDNS
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

# Service systemd
if systemctl list-unit-files | grep -q "$SERVICE_NAME"; then
    systemctl restart "$SERVICE_NAME"
else
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
echo "UUID : $UUID"
echo "Clé publique SlowDNS : $PUB_KEY"
