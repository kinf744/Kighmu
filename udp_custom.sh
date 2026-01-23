#!/bin/bash
# ==========================================================
# UDP Custom Installer v1.5
# Ubuntu 20.04+ / Debian 10+
# Fonctionnalité : UDP → HTTP Custom / VPN
# ==========================================================

set -euo pipefail

# ================= VARIABLES =================
INSTALL_DIR="/opt/udp-custom"
BIN_PATH="$INSTALL_DIR/bin/udp-custom-linux-amd64"
CONFIG_FILE="$INSTALL_DIR/config/config.json"
UDP_PORT=54000
LOG_DIR="/var/log/udp-custom"
LOG_FILE="$LOG_DIR/install.log"
RUN_USER="udpuser"
SERVICE_NAME="udp-custom.service"
BINARY_URL="https://github.com/kinf744/Kighmu/releases/download/v1.0.0/udp-custom"

mkdir -p "$LOG_DIR"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" | tee -a "$LOG_FILE"
}

log "+--------------------------------------------+"
log "|          INSTALLATION UDP CUSTOM           |"
log "+--------------------------------------------+"

# ================= DEPENDANCES =================
install_package_if_missing() {
    local pkg="$1"
    log "Installation de $pkg..."
    apt-get update -y >/dev/null 2>&1 || true
    if ! apt-get install -y "$pkg" >/dev/null 2>&1; then
        log "⚠️ Échec de l'installation de $pkg, le script continue..."
    else
        log "✅ $pkg installé."
    fi
}

essential_packages=(git curl build-essential libssl-dev jq iptables ca-certificates netfilter-persistent)
for p in "${essential_packages[@]}"; do
    install_package_if_missing "$p"
done

# ================= UTILISATEUR =================
if ! id -u "$RUN_USER" >/dev/null 2>&1; then
    useradd -r -m -d /home/"$RUN_USER" -s /usr/sbin/nologin "$RUN_USER"
    log "✅ Utilisateur dédié $RUN_USER créé."
fi

# ================= TELECHARGEMENT BINAIRE =================
mkdir -p "$(dirname "$BIN_PATH")"

# Arrêter le service si déjà existant
systemctl stop "$SERVICE_NAME" 2>/dev/null || true

TMP_BIN="$(dirname "$BIN_PATH")/udp-custom.tmp"
if ! wget -q -O "$TMP_BIN" "$BINARY_URL"; then
    log "❌ Échec du téléchargement udp-custom"
    exit 1
fi
chmod +x "$TMP_BIN"
mv "$TMP_BIN" "$BIN_PATH"
log "✅ Binaire udp-custom téléchargé et exécutable"

chown -R "$RUN_USER:$RUN_USER" "$INSTALL_DIR"

# ================= CONFIG JSON =================
mkdir -p "$(dirname "$CONFIG_FILE")"
cat > "$CONFIG_FILE" <<EOF
{
  "server_port": $UDP_PORT,
  "exclude_port": [],
  "udp_timeout": 600,
  "dns_cache": true
}
EOF
log "✅ Fichier de configuration créé : $CONFIG_FILE"

# ================= IPTABLES =================
log "Configuration iptables pour le port UDP $UDP_PORT..."
iptables -C INPUT -p udp --dport "$UDP_PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport "$UDP_PORT" -j ACCEPT
iptables-save | tee /etc/iptables/rules.v4 >/dev/null
systemctl enable netfilter-persistent
systemctl restart netfilter-persistent || true
log "✅ Règles iptables appliquées et persistantes."

# ================= SYSTEMD =================
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"
log "Création du service systemd $SERVICE_NAME..."
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=UDP Custom Service for HTTP Custom VPN
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$RUN_USER
Group=$RUN_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$BIN_PATH -c $CONFIG_FILE
Restart=always
RestartSec=5
Environment=LOG_DIR=$LOG_DIR
StandardOutput=journal
StandardError=journal
SyslogIdentifier=udp-custom

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

# ================= VERIFICATION =================
sleep 3
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "✅ UDP Custom démarré avec succès sur le port $UDP_PORT."
else
    log "❌ Échec : UDP Custom ne s’est pas lancé correctement."
    journalctl -u "$SERVICE_NAME" --no-pager | tail -n 40
    exit 1
fi

log "+--------------------------------------------+"
log "|      Installation terminée avec succès     |"
log "|  Port UDP $UDP_PORT ouvert et persistant   |"
log "|  Service systemd $SERVICE_NAME actif      |"
log "+--------------------------------------------+"

# ================= FONCTION DESINSTALLATION =================
uninstall_udp_custom() {
    log ">>> Désinstallation UDP Custom..."
    systemctl stop "$SERVICE_NAME" || true
    systemctl disable "$SERVICE_NAME" || true
    rm -f "/etc/systemd/system/$SERVICE_NAME"
    systemctl daemon-reload

    rm -rf "$INSTALL_DIR"

    iptables -D INPUT -p udp --dport "$UDP_PORT" -j ACCEPT 2>/dev/null || true
    iptables-save | tee /etc/iptables/rules.v4 >/dev/null
    systemctl restart netfilter-persistent || true

    log "[OK] UDP Custom désinstallé."
}

exit 0
