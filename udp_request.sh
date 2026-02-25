#!/bin/bash
# UDP Request Installer v2.5 (Optimisé & Stable)

set -euo pipefail

SERVICE_NAME="udp_request.service"
BIN_PATH="/usr/local/bin/udp_request"

echo "🔄 Nettoyage ancien service..."
systemctl stop "$SERVICE_NAME" 2>/dev/null || true
systemctl disable "$SERVICE_NAME" 2>/dev/null || true
rm -f "/etc/systemd/system/$SERVICE_NAME"

# -------------------------------
# Vérification architecture
# -------------------------------
ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" ]]; then
    echo "❌ Architecture non supportée: $ARCH"
    exit 1
fi

# -------------------------------
# Détection interface réseau
# -------------------------------
NET_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
SERVER_IP=$(hostname -I | awk '{print $1}')

if [[ -z "$NET_IFACE" || -z "$SERVER_IP" ]]; then
    echo "❌ Impossible de détecter l'interface ou l'IP"
    exit 1
fi

echo "🌐 Interface détectée: $NET_IFACE"
echo "🌍 IP détectée: $SERVER_IP"

# -------------------------------
# Téléchargement binaire
# -------------------------------
echo "📥 Téléchargement udp_request..."
wget -q "https://github.com/kinf744/Kighmu/releases/download/v1.0.0/udp_request" -O "$BIN_PATH"

if [[ ! -f "$BIN_PATH" ]]; then
    echo "❌ Échec téléchargement"
    exit 1
fi

chmod 755 "$BIN_PATH"

# -------------------------------
# Création service systemd
# -------------------------------
echo "🛠 Création service..."

cat > "/etc/systemd/system/$SERVICE_NAME" << EOF
[Unit]
Description=UDP Request Service (Optimized)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BIN_PATH -mode system -net $NET_IFACE -ip $SERVER_IP
Restart=always
RestartSec=3
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

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
    echo ""
    echo "✅ UDP Request installé et actif"
    echo "🖥 Interface: $NET_IFACE"
    echo "🌍 IP: $SERVER_IP"
    systemctl status "$SERVICE_NAME" --no-pager | head -n 10
else
    echo "❌ Échec démarrage → Logs:"
    journalctl -u "$SERVICE_NAME" -n 20 --no-pager
fi
