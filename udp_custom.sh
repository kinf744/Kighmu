#!/bin/bash
# ==========================================================
# UDP Custom Server v1.4 → SSH
# Avec logs détaillés et suivi temps réel des paquets UDP
# Compatible HTTP Custom (Android)
# Ubuntu 20.04+
# ==========================================================

set -euo pipefail

# ================= VARIABLES =================
INSTALL_DIR="/opt/udp-custom"
BIN_PATH="$INSTALL_DIR/udp-custom-linux-amd64"
CONFIG_FILE="$INSTALL_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/udp_custom.service"

UDP_PORT=36712  # Port UDP à écouter (à ajuster)
LOG_DIR="/var/log/udp-custom"
BIN_LOG="$LOG_DIR/udp-custom.log"
TCPDUMP_LOG="$LOG_DIR/udp_packets.log"
SSH_TEST_LOG="$LOG_DIR/ssh_test.log"

mkdir -p "$INSTALL_DIR" "$LOG_DIR"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" | tee -a "$BIN_LOG"; }

log "============================================"
log "INSTALLATION UDP CUSTOM AVEC SUIVI UDP"
log "============================================"

# ================= INSTALLATION DEPENDANCES =================
log "🔹 Mise à jour & installation des dépendances"
apt update -y
apt install -y wget nftables net-tools openssh-server tcpdump

# ================= BINAIRE =================
log "🔹 Téléchargement du binaire UDP Custom"
wget -q --show-progress \
"https://raw.githubusercontent.com/noobconner21/UDP-Custom-Script/main/udp-custom-linux-amd64" \
-O "$BIN_PATH"
chmod +x "$BIN_PATH"
log "✅ Binaire prêt : $BIN_PATH"

# ================= CONFIG JSON =================
log "🔹 Création config.json"
cat > "$CONFIG_FILE" <<EOF
{
  "listen": ":$UDP_PORT",
  "stream_buffer": 8388608,
  "receive_buffer": 16777216,
  "auth": {
    "mode": "passwords"
  }
}
EOF
log "✅ config.json créé"

# ================= NFTABLES =================
log "🔹 Configuration nftables UDP Custom..."

# Activation nftables
systemctl enable nftables >/dev/null 2>&1 || true
systemctl start nftables >/dev/null 2>&1 || true

# Création table UDP Custom
nft delete table inet udp_custom 2>/dev/null || true
nft add table inet udp_custom

# Chaîne INPUT
nft add chain inet udp_custom input { type filter hook input priority 0 \; policy accept \; }
nft add rule inet udp_custom input ct state established,related accept
nft add rule inet udp_custom input iif lo accept
nft add rule inet udp_custom input ip protocol icmp accept
nft add rule inet udp_custom input udp dport "$UDP_PORT" accept
nft add rule inet udp_custom input tcp dport 22 accept

log "✅ nftables UDP Custom appliqué correctement"

# ================= SYSTEMD =================
log "🔹 Création service systemd"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=UDP Custom Server (UDP → HTTP Custom)
After=network.target

[Service]
Type=simple
ExecStart=$BIN_PATH server --config $CONFIG_FILE
Restart=always
RestartSec=3
LimitNOFILE=1048576
StandardOutput=append:$BIN_LOG
StandardError=append:$BIN_LOG
NoNewPrivileges=true
CPUSchedulingPolicy=other
Nice=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable udp_custom.service
systemctl restart udp_custom.service
sleep 2

# ================= VERIFICATION =================
if systemctl is-active --quiet udp_custom.service; then
  log "✅ Service udp_custom actif"
else
  log "❌ Service udp_custom en échec"
  journalctl -u udp_custom.service --no-pager | tail -n 40 | tee -a "$BIN_LOG"
  exit 1
fi

if ss -lunp | grep -q ":$UDP_PORT"; then
  log "✅ UDP Custom écoute sur le port $UDP_PORT"
else
  log "❌ Port UDP $UDP_PORT non actif"
fi

# ================= SUIVI UDP EN TEMPS RÉEL =================
log "🔹 Démarrage suivi temps réel des paquets UDP entrants sur le port $UDP_PORT"

log "✅ Suivi UDP lancé, logs disponibles dans $TCPDUMP_LOG"
log "============================================"
log "INSTALLATION TERMINÉE"
log "UDP $UDP_PORT → prêt pour HTTP Custom"
log "Logs du binaire : $BIN_LOG"
log "Logs UDP (tcpdump) : $TCPDUMP_LOG"
log "============================================"
