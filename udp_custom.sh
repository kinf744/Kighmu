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
BIN_PATH="$INSTALL_DIR/bin/udp-custom-linux-amd64"
CONFIG_DIR="$INSTALL_DIR/config"
CONFIG_FILE="$CONFIG_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/udp_custom.service"

UDP_PORT=54000
SSH_TARGET="127.0.0.1:22"
RUN_USER="udpuser"
LOG_DIR="/var/log/udp-custom"
LOG_FILE="$LOG_DIR/install.log"
BIN_LOG="$LOG_DIR/udp-custom.log"
SSH_TEST_LOG="$LOG_DIR/ssh_test.log"
TCPDUMP_LOG="$LOG_DIR/udp_packets.log"

mkdir -p "$LOG_DIR"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" | tee -a "$LOG_FILE"
}

log "============================================"
log "INSTALLATION UDP CUSTOM → SSH AVEC SUIVI UDP"
log "============================================"

# ================= INSTALLATION DEPENDANCES =================
log "🔹 Mise à jour & installation des dépendances"
apt update -y
apt install -y git curl iptables ca-certificates openssh-server netfilter-persistent wget tcpdump

# ================= UTILISATEUR =================
if ! id "$RUN_USER" &>/dev/null; then
  useradd -r -m -s /usr/sbin/nologin "$RUN_USER"
  log "✅ Utilisateur $RUN_USER créé"
else
  log "✅ Utilisateur $RUN_USER existant"
fi

# ================= BINAIRE =================
mkdir -p "$INSTALL_DIR/bin"
log "🔹 Téléchargement du binaire UDP Custom"
wget -q --show-progress --load-cookies /tmp/cookies.txt \
"https://github.com/NETWORKTWEAKER/AUTO-SCRIPT/raw/master/udp-custom/udp-custom-linux-amd64" \
-O "$BIN_PATH" && rm -rf /tmp/cookies.txt

chmod +x "$BIN_PATH"
if [ ! -x "$BIN_PATH" ]; then
  log "❌ Binaire introuvable ou non exécutable"
  exit 1
else
  log "✅ Binaire prêt : $BIN_PATH"
fi

# ================= CONFIG JSON =================
log "🔹 Création config.json"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_FILE" <<EOF
{
  "listen": "0.0.0.0:$UDP_PORT",
  "target": "$SSH_TARGET",
  "timeout": 600,
  "log_level": "debug"
}
EOF
chown -R "$RUN_USER:$RUN_USER" "$INSTALL_DIR"

# ================= IPTABLES =================
log "🔹 Configuration iptables pour UDP $UDP_PORT"
iptables -C INPUT -p udp --dport "$UDP_PORT" -j ACCEPT 2>/dev/null \
  || iptables -I INPUT -p udp --dport "$UDP_PORT" -j ACCEPT
iptables -C OUTPUT -p udp --sport "$UDP_PORT" -j ACCEPT 2>/dev/null \
  || iptables -I OUTPUT -p udp --sport "$UDP_PORT" -j ACCEPT
iptables-save > /etc/iptables/rules.v4
systemctl enable netfilter-persistent
systemctl restart netfilter-persistent
log "✅ Règles iptables appliquées"

# ================= SYSTEMD =================
log "🔹 Création service systemd avec logs détaillés"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=UDP Custom Server (UDP → SSH) avec suivi UDP
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

StandardOutput=append:$BIN_LOG
StandardError=append:$BIN_LOG
SyslogIdentifier=udp_custom

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable udp_custom.service
systemctl restart udp_custom.service
sleep 2

# ================= VERIFICATION =================
log "🔹 Vérification du service systemd"
if systemctl is-active --quiet udp_custom.service; then
  log "✅ Service udp_custom actif"
else
  log "❌ Service udp_custom en échec"
  journalctl -u udp_custom.service --no-pager | tail -n 40 | tee -a "$LOG_FILE"
  exit 1
fi

log "🔹 Vérification du port UDP $UDP_PORT"
if ss -lunp | grep -q ":$UDP_PORT"; then
  log "✅ UDP Custom écoute sur le port $UDP_PORT"
else
  log "❌ Port UDP $UDP_PORT non actif"
fi

log "🔹 Test SSH local"
ssh -o BatchMode=yes -o ConnectTimeout=5 127.0.0.1 -p 22 exit &> "$SSH_TEST_LOG" || \
log "❌ SSH impossible, voir $SSH_TEST_LOG"

# ================= SUIVI UDP EN TEMPS RÉEL =================
log "🔹 Démarrage suivi temps réel des paquets UDP entrants sur le port $UDP_PORT"
# On lance tcpdump en arrière-plan
nohup tcpdump -n -i any udp port "$UDP_PORT" -vvv -l >> "$TCPDUMP_LOG" 2>&1 &

log "✅ Suivi UDP lancé, logs disponibles dans $TCPDUMP_LOG"
log "============================================"
log "INSTALLATION TERMINÉE AVEC SUIVI UDP"
log "UDP $UDP_PORT → SSH $SSH_TARGET"
log "Logs du binaire : $BIN_LOG"
log "Logs test SSH : $SSH_TEST_LOG"
log "Logs UDP (tcpdump) : $TCPDUMP_LOG"
log "============================================"
