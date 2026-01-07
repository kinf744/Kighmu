#!/bin/bash
# ==========================================================
# UDP Custom Server v1.4 → SSH
# Mode BACKEND pour cohabitation avec UDP Request MAÎTRE
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

UDP_PORT=36712  # Port interne (backend TCP via le maître UDP)
LOG_DIR="/var/log/udp-custom"
BIN_LOG="$LOG_DIR/udp-custom.log"
TCPDUMP_LOG="$LOG_DIR/udp_packets.log"
SSH_TEST_LOG="$LOG_DIR/ssh_test.log"

mkdir -p "$INSTALL_DIR" "$LOG_DIR"

# ================= LOG =================
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" | tee -a "$BIN_LOG"; }

log "============================================"
log "INSTALLATION UDP CUSTOM (MODE BACKEND)"
log "============================================"

# ================= DEPENDANCES =================
log "🔹 Mise à jour & installation des dépendances"
apt update -y
apt install -y wget net-tools openssh-server tcpdump >/dev/null 2>&1

# ================= BINAIRE =================
log "🔹 Téléchargement du binaire UDP Custom"
wget -q --show-progress \
"https://raw.githubusercontent.com/noobconner21/UDP-Custom-Script/main/udp-custom-linux-amd64" \
-O "$BIN_PATH"
chmod +x "$BIN_PATH"
log "✅ Binaire prêt : $BIN_PATH"

# ================= CONFIG JSON =================
log "🔹 Création config.json (écoute backend, pas UDP direct)"
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

# ================= SYSTEMD =================
log "🔹 Création service systemd"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=UDP Custom Server (backend TCP via UDP Request)
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

log "✅ UDP Custom backend prêt sur le port $UDP_PORT"
log "Logs du binaire : $BIN_LOG"

log "============================================"
log "INSTALLATION TERMINÉE — MODE BACKEND"
log "============================================"
