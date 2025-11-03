#!/bin/bash
# udp_custom.sh
# Installation et configuration UDP Custom pour HTTP Custom VPN
# Fonctionnalité : iptables persistantes pour port UDP, systemd redémarrage automatique

set -euo pipefail

INSTALL_DIR="/root/udp-custom"
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

# Dépendances
install_package_if_missing() {
  local pkg="$1"
  log "Installation de $pkg..."
  if apt-get update -y >/dev/null 2>&1; then :; fi
  if ! apt-get install -y "$pkg" >/dev/null 2>&1; then
    log "⚠️ Attention : échec de l'installation du paquet $pkg, le script continue..."
  else
    log "Le paquet $pkg a été installé avec succès."
  fi
}

essential_packages=(git curl build-essential libssl-dev jq iptables ca-certificates)
for p in "${essential_packages[@]}"; do
  install_package_if_missing "$p"
done

# Vérification IP publique
if ! command -v curl >/dev/null 2>&1; then
  install_package_if_missing curl
fi
IP_TEST=$(curl -s --max-time 5 https://ifconfig.co)
if [[ -z "$IP_TEST" ]]; then
  log "⚠️ Impossible de déterminer l’IP publique via curl."
fi

# Clonage ou mise à jour du dépôt
if [ ! -d "$INSTALL_DIR" ]; then
  log "Clonage du dépôt udp-custom..."
  git clone https://github.com/http-custom/udp-custom.git "$INSTALL_DIR" 2>>"$LOG_FILE" || {
    log "Échec du clonage. Vérifier l’accès réseau et l’URL du dépôt."
    exit 1
  }
else
  log "udp-custom déjà présent, mise à jour..."
  cd "$INSTALL_DIR"
  git pull 2>>"$LOG_FILE" || log "Échec de la mise à jour, le script continue."
fi

cd "$INSTALL_DIR"

# Vérification du binaire
if [ ! -x "$BIN_PATH" ]; then
  if [ -f "$BIN_PATH" ]; then
    chmod +x "$BIN_PATH"
  fi
fi
if [ ! -x "$BIN_PATH" ]; then
  log "❌ Erreur critique: Le binaire $BIN_PATH est manquant ou non exécutable."
  exit 1
fi

# Configuration JSON
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

# Création utilisateur dédié
if ! id -u udpuser >/dev/null 2>&1; then
  useradd -r -m -d /home/udpuser udpuser || true
  log "Utilisateur dédié udpuser créé."
fi
chown -R udpuser:udpuser "$INSTALL_DIR"

# Ouverture du port UDP via iptables persistantes
log "Configuration du port UDP $UDP_PORT avec iptables..."
iptables -C INPUT -p udp --dport "$UDP_PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport "$UDP_PORT" -j ACCEPT
iptables -C OUTPUT -p udp --sport "$UDP_PORT" -j ACCEPT 2>/dev/null || iptables -I OUTPUT -p udp --sport "$UDP_PORT" -j ACCEPT

# Sauvegarde iptables persistante
mkdir -p /etc/iptables
iptables-save | tee /etc/iptables/rules.v4
systemctl enable netfilter-persistent
systemctl restart netfilter-persistent || true
log "Règles iptables appliquées et persistantes."

# Service systemd
SERVICE_PATH="/etc/systemd/system/udp_custom.service"
log "Création du fichier systemd udp_custom.service..."
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
systemctl enable udp_custom.service
systemctl restart udp_custom.service

# Vérification du démarrage
sleep 3
if pgrep -f "udp-custom-linux-amd64" >/dev/null; then
  log "UDP Custom démarré avec succès sur le port $UDP_PORT."
else
  log "❌ Échec: UDP Custom ne s’est pas lancé correctement."
  exit 1
fi

log "+--------------------------------------------+"
log "|          Configuration terminée            |"
log "|  Port UDP $UDP_PORT ouvert et persistant    |"
log "|  Service systemd udp_custom actif          |"
log "+--------------------------------------------+"

# Fonction de désinstallation
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
