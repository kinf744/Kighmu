#!/bin/bash
# ==========================================================
# UDP Custom Server v1.4 → SSH
# Téléchargement automatique du binaire externe
# Compatible Debian/Ubuntu
# ==========================================================

set -euo pipefail

# ================= VARIABLES =================
INSTALL_DIR="/opt/udp-custom"
BIN_DIR="$INSTALL_DIR/bin"
BIN_PATH="$BIN_DIR/udp-custom"
CONFIG_DIR="$INSTALL_DIR/config"
CONFIG_FILE="$CONFIG_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/udp_custom.service"

UDP_PORT=54000
SSH_TARGET="127.0.0.1:22"
RUN_USER="udpuser"
LOG_DIR="/var/log/udp-custom"
LOG_FILE="$LOG_DIR/install.log"

# ================= LOG =================
mkdir -p "$LOG_DIR"
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" | tee -a "$LOG_FILE"
}

log "============================================"
log " INSTALLATION UDP CUSTOM → SSH (BINAIRE EXTERNE)"
log "============================================"

# ================= DEPENDANCES =================
apt update -y
apt install -y curl iptables ca-certificates openssh-server netfilter-persistent wget

# ================= UTILISATEUR =================
if ! id "$RUN_USER" &>/dev/null; then
  useradd -r -m -s /usr/sbin/nologin "$RUN_USER"
  log "Utilisateur $RUN_USER créé"
fi

# ================= TELECHARGEMENT BIN =================
mkdir -p "$BIN_DIR"
log "Téléchargement du binaire UDP Custom"
wget -q --show-progress \
 "https://github.com/NETWORKTWEAKER/AUTO-SCRIPT/raw/master/udp-custom/udp-custom-linux-amd64" \
 -O "$BIN_PATH"
chmod +x "$BIN_PATH"
chown "$RUN_USER:$RUN_USER" "$BIN_PATH"

if [ ! -x "$BIN_PATH" ]; then
  log "❌ Échec du téléchargement ou binaire non exécutable"
  exit 1
fi
log "✅ Binaire téléchargé et exécutable : $BIN_PATH"
file "$BIN_PATH" | tee -a "$LOG_FILE"

# ================= CONFIG JSON =================
mkdir -p "$CONFIG_DIR"
log "Création config.json"
cat > "$CONFIG_FILE" <<EOF
{
  "listen": "0.0.0.0:$UDP_PORT",
  "target": "$SSH_TARGET",
  "timeout": 600,
  "log_level": "info"
}
EOF
chown -R "$RUN_USER:$RUN_USER" "$INSTALL_DIR"

# ================= IPTABLES =================
log "Ouverture UDP $UDP_PORT"
iptables -C INPUT -p udp --dport "$UDP_PORT" -j ACCEPT 2>/dev/null \
  || iptables -I INPUT -p udp --dport "$UDP_PORT" -j ACCEPT
iptables-save > /etc/iptables/rules.v4
systemctl enable netfilter-persistent
systemctl restart netfilter-persistent

# ================= SYSTEMD =================
log "Création service systemd"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=UDP Custom Server (UDP → SSH)
After=network-online.target ssh.service
Wants=network-online.target

[Service]
Type=simple
User=$RUN_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$BIN_PATH server --config $CONFIG_FILE
Restart=always
RestartSec=3
LimitNOFILE=1048576
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# ================= DEMARRAGE =================
systemctl daemon-reload
systemctl enable udp_custom.service
systemctl restart udp_custom.service

sleep 2

# ================= VERIFICATION =================
if systemctl is-active --quiet udp_custom.service; then
  log "✅ Service udp_custom actif"
else
  log "❌ Service udp_custom en échec"
  journalctl -u udp_custom.service --no-pager | tail -n 40
  exit 1
fi

if ss -lunp | grep -q ":$UDP_PORT"; then
  log "✅ UDP Custom écoute sur le port $UDP_PORT"
else
  log "❌ Port UDP $UDP_PORT non actif"
  exit 1
fi

log "============================================"
log " INSTALLATION TERMINÉE AVEC SUCCÈS"
log " BINAIRE : $BIN_PATH"
log " UDP $UDP_PORT → SSH $SSH_TARGET"
log "============================================"
