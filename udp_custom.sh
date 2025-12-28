#!/bin/bash
# ==========================================================
# UDP Custom Server → SSH (fonctionnel)
# Compatible HTTP Custom VPN (Android)
# ==========================================================

set -euo pipefail

# ---------- VARIABLES ----------
INSTALL_DIR="/opt/udp-custom"
BIN_DIR="$INSTALL_DIR/bin"
BIN_PATH="$BIN_DIR/udp-custom-linux-amd64"
UDP_PORT=54000
TARGET_HOST="127.0.0.1"
TARGET_PORT=22
RUN_USER="udpuser"
LOG_DIR="/var/log/udp-custom"
SERVICE_NAME="udp_custom.service"

# ---------- LOG ----------
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install.log"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" | tee -a "$LOG_FILE"
}

log "============================================"
log " INSTALLATION UDP CUSTOM → SSH (STABLE)"
log "============================================"

# ---------- DEPENDANCES ----------
apt update -y
apt install -y \
  git curl iptables ca-certificates \
  openssh-server netfilter-persistent

# ---------- UTILISATEUR DÉDIÉ ----------
if ! id "$RUN_USER" &>/dev/null; then
  useradd -r -m -s /usr/sbin/nologin "$RUN_USER"
  log "Utilisateur $RUN_USER créé"
fi

# ---------- CLONAGE ----------
if [ ! -d "$INSTALL_DIR" ]; then
  git clone https://github.com/http-custom/udp-custom.git "$INSTALL_DIR"
else
  cd "$INSTALL_DIR"
  git pull || true
fi

# ---------- BINAIRE ----------
mkdir -p "$BIN_DIR"
chmod +x "$BIN_PATH"

if [ ! -x "$BIN_PATH" ]; then
  log "❌ Binaire udp-custom introuvable"
  exit 1
fi

# ---------- IPTABLES ----------
log "Configuration iptables UDP $UDP_PORT"

iptables -C INPUT -p udp --dport "$UDP_PORT" -j ACCEPT 2>/dev/null \
  || iptables -I INPUT -p udp --dport "$UDP_PORT" -j ACCEPT

iptables -C OUTPUT -p udp --sport "$UDP_PORT" -j ACCEPT 2>/dev/null \
  || iptables -I OUTPUT -p udp --sport "$UDP_PORT" -j ACCEPT

iptables-save > /etc/iptables/rules.v4
systemctl enable netfilter-persistent
systemctl restart netfilter-persistent

# ---------- SYSTEMD ----------
log "Création du service systemd"

cat > /etc/systemd/system/$SERVICE_NAME <<EOF
[Unit]
Description=UDP Custom Server (UDP → SSH)
After=network-online.target ssh.service
Wants=network-online.target

[Service]
Type=simple
User=$RUN_USER
ExecStart=$BIN_PATH \
  --listen 0.0.0.0:$UDP_PORT \
  --target $TARGET_HOST:$TARGET_PORT
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

# ---------- DÉMARRAGE ----------
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl restart $SERVICE_NAME

sleep 2

if ss -lunp | grep -q ":$UDP_PORT"; then
  log "✅ UDP Custom actif sur UDP $UDP_PORT → SSH $TARGET_PORT"
else
  log "❌ UDP Custom ne répond pas"
  journalctl -u $SERVICE_NAME --no-pager | tail -n 30
  exit 1
fi

log "============================================"
log " INSTALLATION TERMINÉE AVEC SUCCÈS"
log " UDP $UDP_PORT → SSH $TARGET_PORT"
log "============================================"
