#!/bin/bash
# UDP Request Installer v3.0 (Multi Tunnel Compatible)

set -euo pipefail

SERVICE_NAME="udp_request.service"
BIN_PATH="/usr/local/bin/udp_request"
CONFIG_DIR="/etc/udp_request"
CONFIG_FILE="$CONFIG_DIR/config.json"
UDP_PORT=4466

echo "🔄 Nettoyage ancien service..."
systemctl stop "$SERVICE_NAME" 2>/dev/null || true
systemctl disable "$SERVICE_NAME" 2>/dev/null || true
rm -f "/etc/systemd/system/$SERVICE_NAME"

mkdir -p "$CONFIG_DIR"

# -------------------------------
# Vérification architecture
# -------------------------------
ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" ]]; then
    echo "❌ Architecture non supportée: $ARCH"
    exit 1
fi

# -------------------------------
# Téléchargement binaire
# -------------------------------
echo "📥 Téléchargement udp_request..."
wget -q https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/udp_request -O "$BIN_PATH"

chmod 755 "$BIN_PATH"

# -------------------------------
# Création config JSON
# -------------------------------
echo "⚙ Création config..."

cat > "$CONFIG_FILE" <<EOF
{
  "listen": ":$UDP_PORT",
  "exclude_port": [5300,53,35712],
  "timeout": 600
}
EOF

# -------------------------------
# Ouverture port
# -------------------------------
iptables -C INPUT -p udp --dport $UDP_PORT -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport $UDP_PORT -j ACCEPT

# -------------------------------
# Création service systemd
# -------------------------------
echo "🛠 Création service..."

cat > "/etc/systemd/system/$SERVICE_NAME" <<EOF
[Unit]
Description=UDP Request JSON Mode
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BIN_PATH server -c $CONFIG_FILE
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

sleep 2

# -------------------------------
# Vérification
# -------------------------------
if systemctl is-active --quiet "$SERVICE_NAME"; then
    IP=$(hostname -I | awk '{print $1}')
    echo ""
    echo "✅ UDP Request actif (Mode Safe)"
    echo "📡 udp://$IP:$UDP_PORT"
    ss -ulnp | grep $UDP_PORT
else
    echo "❌ Échec démarrage → Logs:"
    journalctl -u "$SERVICE_NAME" -n 20 --no-pager
fi
