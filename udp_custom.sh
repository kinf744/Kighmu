#!/bin/bash
# udp_custom.sh
# Installation et configuration UDP Custom pour HTTP Custom VPN
# Fonctionnalité : iptables persistantes pour port UDP, systemd redémarrage automatique

set -euo pipefail

# --- Variables ---
INSTALL_DIR="/opt/udp-custom"
CONFIG_FILE="$INSTALL_DIR/config/config.json"
BIN_PATH="$INSTALL_DIR/bin/udp-custom-linux-amd64"
UDP_PORT=54000
LOG_DIR="/var/log/udp-custom"
LOG_FILE="$LOG_DIR/install.log"

mkdir -p "$LOG_DIR"

log() {
  local msg="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') | $msg" | tee -a "$LOG_FILE"
}

log "+--------------------------------------------+"
log "|             INSTALLATION UDP CUSTOM        |"
log "+--------------------------------------------+"

# --- Dépendances ---
install_package_if_missing() {
  local pkg="$1"
  log "Installation de $pkg..."
  apt-get update -y >/dev/null 2>&1 || true
  if ! apt-get install -y "$pkg" >/dev/null 2>&1; then
    log "⚠️ Échec de l'installation de $pkg, le script continue..."
  else
    log "Le paquet $pkg a été installé avec succès."
  fi
}

essential_packages=(git curl build-essential libssl-dev jq iptables ca-certificates)
for p in "${essential_packages[@]}"; do
  install_package_if_missing "$p"
done

# --- Vérification IP publique ---
if ! command -v curl >/dev/null 2>&1; then
  install_package_if_missing curl
fi
IP_TEST=$(curl -s --max-time 5 https://ifconfig.co)
if [[ -z "$IP_TEST" ]]; then
  log "⚠️ Impossible de déterminer l’IP publique via curl."
fi

# --- Clonage ou mise à jour du dépôt ---
mkdir -p "$(dirname "$BIN_PATH")"

if ! wget -q -O "$BIN_PATH" "https://github.com/kinf744/Kighmu/releases/download/v1.0.0/udp-custom"; then
    log "❌ Échec du téléchargement udp-custom"
    exit 1
fi

chmod +x "$BIN_PATH"
log "✅ Binaire udp-custom téléchargé et exécutable"

# --- Configuration JSON ---
log "Configuration UDP..."
mkdir -p "$(dirname "$CONFIG_FILE")"
cat > "$CONFIG_FILE" << EOF
{
  "server_port": $UDP_PORT,
  "exclude_port": [],
  "udp_timeout": 600,
  "dns_cache": true
}
EOF

# --- Création utilisateur dédié ---
if ! id -u udpuser >/dev/null 2>&1; then
  useradd -r -m -d /home/udpuser udpuser || true
  log "Utilisateur dédié udpuser créé."
fi
chown -R udpuser:udpuser "$INSTALL_DIR"

# --- iptables persistantes ---
log "Configuration du port UDP $UDP_PORT avec iptables..."
iptables -C INPUT -p udp --dport "$UDP_PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport "$UDP_PORT" -j ACCEPT
iptables -C OUTPUT -p udp --sport "$UDP_PORT" -j ACCEPT 2>/dev/null || iptables -I OUTPUT -p udp --sport "$UDP_PORT" -j ACCEPT

# Sauvegarde persistante
mkdir -p /etc/iptables
iptables-save | tee /etc/iptables/rules.v4
systemctl enable netfilter-persistent
systemctl restart netfilter-persistent || true
log "Règles iptables appliquées et persistantes."

# --- Service systemd ---
SERVICE_PATH="/etc/systemd/system/udp-custom.service"
log "Création du fichier systemd udp-custom.service..."
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=UDP Custom Service for HTTP Custom VPN
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=udpuser
Group=udpuser
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
systemctl enable udp-custom.service
systemctl restart udp-custom.service

# --- Vérification démarrage ---
sleep 3
if pgrep -f "udp-custom-linux-amd64" >/dev/null; then
  log "UDP Custom démarré avec succès sur le port $UDP_PORT."
else
  log "❌ Échec: UDP Custom ne s’est pas lancé correctement."
  exit 1
fi

log "+--------------------------------------------+"
log "|          Configuration terminée            |"
log "|  Port UDP $UDP_PORT ouvert et persistant   |"
log "|  Service systemd udp_custom actif          |"
log "+--------------------------------------------+"

# --- Désinstallation ---
uninstall_udp_custom() {
    log ">>> Désinstallation UDP Custom..."
    systemctl stop udp_custom.service || true
    systemctl disable udp_custom.service || true
    rm -f /etc/systemd/system/udp_custom.service
    systemctl daemon-reload

    rm -rf "$INSTALL_DIR"

    iptables -D INPUT -p udp --dport "$UDP_PORT" -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -p udp --sport "$UDP_PORT" -j ACCEPT 2>/dev/null || true
    iptables-save | tee /etc/iptables/rules.v4
    systemctl restart netfilter-persistent || true

    log "[OK] UDP Custom désinstallé."
}

exit 0
