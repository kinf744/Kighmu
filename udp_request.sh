#!/bin/bash
# UDP Request v1.8 - CORRIGÉ pour udp_request )
set -euo pipefail

UDP_PORT=4466
BIN_PATH="/usr/local/bin/udp_request"
CONFIG_FILE="/etc/udp_request/config.json"
SERVICE_NAME="udp_request.service"

# 1️⃣ CLEAN TOTAL
systemctl stop "$SERVICE_NAME" 2>/dev/null || true
rm -f "/etc/systemd/system/$SERVICE_NAME"
rm -rf /opt/udp_request /var/log/udp_request
userdel udpuser 2>/dev/null || true

# 2️⃣ BINAIRE (nom correct = udp_request PAS udp_request-linux-amd64)
wget -q "https://github.com/kinf744/Kighmu/releases/download/v1.0.0/udp_request" -O "$BIN_PATH"
chmod +x "$BIN_PATH"

# 3️⃣ CONFIG (syntaxe ZIVPN-compatible)
mkdir -p /etc/udp_request
cat > "$CONFIG_FILE" << 'EOF'
{
  "listen": ":4466",
  "exclude_port": [53,5300,5667,20000,36712],
  "timeout": 600
}
EOF

# 4️⃣ IPTABLES INTELLIGENT 
iptables -C INPUT -p udp --dport 4466 -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport 4466 -j ACCEPT

# SAVE IPTABLES 
netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4

# 5️⃣ SYSTEMD CORRIGÉ (**CLÉ : `server` comme ZIVPN**)
cat > "/etc/systemd/system/$SERVICE_NAME" << EOF
[Unit]
Description=UDP socksip Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BIN_PATH server -c $CONFIG_FILE
Restart=always
RestartSec=5
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal
SyslogIdentifier=udp-custom

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

# 6️⃣ TEST
sleep 3
if systemctl is-active --quiet "$SERVICE_NAME"; then
    IP=$(hostname -I | awk '{print $1}')
    echo "✅ UDP socksip OK → $IP:4466"
    echo "📱 UDP socksip: udp://$IP:4466"
    ss -ulnp | grep 4466
else
    echo "❌ ÉCHEC → Logs:"
    journalctl -u udpudp_request.service -n 20
fi
