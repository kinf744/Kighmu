#!/bin/bash
# ==============================================
# v2ray_slowdns_install.sh - Installation et configuration V2Ray + SlowDNS
# ==============================================

INSTALL_DIR="$HOME/Kighmu"
CONFIG_PATH="/usr/local/etc/v2ray_slowdns/config.json"
SERVICE_NAME="v2ray-slowdns"

# Ports SlowDNS/V2Ray
SLOWDNS_PORT=5301        # port du tunnel SlowDNS pour V2Ray
V2RAY_PORT=1080          # port interne de V2Ray
WS_PATH="/kighmu"        # chemin WebSocket

SLOWDNS_DIR="/etc/slowdns"
NS_FILE="$SLOWDNS_DIR/ns.conf"
PUB_KEY_FILE="$SLOWDNS_DIR/server.pub"
UUID_FILE="$INSTALL_DIR/v2ray_uuid.txt"

mkdir -p "$(dirname "$CONFIG_PATH")"
mkdir -p "$INSTALL_DIR"

# --- Nouvelle section pour tuer les services sur le port 1080 ---
if lsof -iTCP:$V2RAY_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "Un service écoute déjà sur le port $V2RAY_PORT. Arrêt en cours..."
    # Trouver le PID
    PIDS=$(lsof -iTCP:$V2RAY_PORT -sTCP:LISTEN -t)
    for pid in $PIDS; do
        # Tenter de trouver le service systemd associé
        SERVICE=$(systemctl list-units --type=service --all | grep -i v2ray | awk '{print $1}' | head -n1)
        if [[ -n "$SERVICE" ]]; then
            echo "Arrêt du service $SERVICE..."
            systemctl stop "$SERVICE"
            systemctl disable "$SERVICE"
        fi
        echo "Killing process $pid sur le port $V2RAY_PORT..."
        kill -9 "$pid"
    done
    echo "Port $V2RAY_PORT libéré."
fi
# -------------------------------------------------------------------

# Demande interactive du nom de domaine
read -p "Entrez le nom de domaine à utiliser (ex: sv2.kighmup.ddns-ip.net) : " DOMAIN
if [ -z "$DOMAIN" ]; then
    echo "Aucun domaine saisi, interruption de l'installation."
    exit 1
fi

# Lire Namespace
if [ ! -f "$NS_FILE" ]; then
    echo "Namespace SlowDNS introuvable ($NS_FILE). Exécute d'abord le script SlowDNS principal."
    exit 1
fi
NS=$(cat "$NS_FILE")

# Lire clé publique SlowDNS
if [ ! -f "$PUB_KEY_FILE" ]; then
    echo "Clé publique SlowDNS introuvable ($PUB_KEY_FILE). Exécute d'abord le script SlowDNS principal."
    exit 1
fi
PUB_KEY=$(cat "$PUB_KEY_FILE")

# UUID stable
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

# Création du fichier config V2Ray
mkdir -p "$(dirname "$CONFIG_PATH")"
cat > "$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "/var/log/v2ray_access.log",
    "error": "/var/log/v2ray_error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $V2RAY_PORT,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "alterId": 0,
            "email": "user@$DOMAIN"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "$WS_PATH",
          "headers": {
            "Host": "$DOMAIN"
          }
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

echo ""
echo "✅ Installation et configuration terminées."
echo "-------------------------------------------"
echo "Service V2Ray SlowDNS : $SERVICE_NAME"
echo "UUID : $UUID"
echo "Chemin WebSocket : $WS_PATH"
echo "Namespace : $NS"
echo "Clé publique SlowDNS : $PUB_KEY"
echo "Port SlowDNS : $SLOWDNS_PORT"
echo "Port interne V2Ray : $V2RAY_PORT"
echo "Domaine utilisé : $DOMAIN"
echo ""
echo "⚠️ Assure-toi que le service slowdns-v2ray (créé par le script principal)"
echo "   redirige bien UDP $SLOWDNS_PORT -> 127.0.0.1:$V2RAY_PORT"
echo ""
