#!/bin/bash
# ==========================================================
# UDP Custom Server v1.4 → SSH
# Compatible HTTP Custom (Android)
# Ubuntu 20.04+
# ==========================================================

set -euo pipefail

# ================= VARIABLES =================
INSTALL_DIR="/opt/udp-custom"
BIN_PATH="$INSTALL_DIR/bin/udp-custom"
CONFIG_DIR="$INSTALL_DIR/config"
CONFIG_FILE="$CONFIG_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/udp-custom.service"

UDP_PORT=54000
SSH_TARGET="127.0.0.1:22"
RUN_USER="udpuser"
LOG_DIR="/var/log/udp-custom"
LOG_FILE="$LOG_DIR/udp-custom.log"

# ================= LOG =================
mkdir -p "$LOG_DIR"
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" | tee -a "$LOG_FILE"
}

log "============================================"
log " INSTALLATION UDP CUSTOM → SSH (v1.4)"
log "============================================"

# ================= DEPENDANCES =================
apt update -y
apt install -y \
  git curl iptables ca-certificates \
  openssh-server netfilter-persistent

# ================= UTILISATEUR =================
if ! id "$RUN_USER" &>/dev/null; then
  useradd -r -m -s /usr/sbin/nologin "$RUN_USER"
  log "Utilisateur $RUN_USER créé"
fi

# ================= DEPOT =================
log "Téléchargement udp-custom..."
wget -q -O "$BIN_PATH" \
  "https://github.com/kinf744/Kighmu/releases/download/v1.0.0/udp-custom" \
  && chmod +x "$BIN_PATH" \
  || { err "Échec du téléchargement udp-custom"; exit 1; }

# ================= BINAIRE =================
if [ ! -x "$BIN_PATH" ]; then
  log "❌ Binaire udp-custom introuvable"
  exit 1
fi

# ================= CONFIG JSON =================
log "Création config.json"

mkdir -p "$CONFIG_DIR"

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

chown -R "$RUN_USER:$RUN_USER" "$INSTALL_DIR"

# ================= IPTABLES =================
if command -v iptables >/dev/null 2>&1; then
        if ! sudo iptables -C INPUT -p tcp --dport 54000 -j ACCEPT 2>/dev/null; then
            sudo iptables -I INPUT -p tcp --dport 54000 -j ACCEPT
            command -v netfilter-persistent >/dev/null && sudo netfilter-persistent save
            echo "✅ Port 54000 ouvert dans le firewall"
        fi
fi

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

[Install]
WantedBy=multi-user.target
EOF

# ================= DEMARRAGE =================
systemctl daemon-reload
systemctl enable udp-custom.service
systemctl restart udp-custom.service

sleep 2

# ================= VERIFICATION =================
if systemctl is-active --quiet udp-custom.service; then
  log "✅ Service udp-custom actif"
else
  log "❌ Service udp-custom en échec"
  journalctl -u udp+
  hcustom.service --no-pager | tail -n 40
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
log " UDP $UDP_PORT → SSH $SSH_TARGET"
log "============================================"
