#!/bin/bash
# udp_custom.sh
# Installation et configuration UDP Custom pour HTTP Custom VPN

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
log "|             INSTALLATION UDP CUSTOM         |"
log "+--------------------------------------------+"

log "Vérification des prérequis et dépendances..."
install_package_if_missing() {
  local pkg="$1"
  log "Installation de $pkg..."
  if apt-get update -y >/dev/null 2>&1; then
    :
  fi
  if ! apt-get install -y "$pkg" >/dev/null 2>&1; then
    log "⚠️ Attention : échec de l'installation du paquet $pkg, le script continue..."
  else
    log "Le paquet $pkg a été installé avec succès."
  fi
}

# Dépendances essentielles
essential_packages=(
  git curl build-essential libssl-dev jq iptables nftables ufw ca-certificates
)
for p in "${essential_packages[@]}"; do
  install_package_if_missing "$p"
done

# Vérification et système de proxy réseau
log "Vérification réseau et connectivité..."
if ! command -v curl >/dev/null 2>&1; then
  log "Curl introuvable; installation..."
  apt-get install -y curl
fi
IP_TEST=$(curl -s --max-time 5 https://ifconfig.co)
if [[ -z "$IP_TEST" ]]; then
  log "⚠️ Impossible de déterminer l’IP publique via curl. Vérifier la connectivité réseau."
fi

# Clonage ou mise à jour du dépôt UDP Custom
if [ ! -d "$INSTALL_DIR" ]; then
  log "Clonage du dépôt udp-custom..."
  if git clone https://github.com/http-custom/udp-custom.git "$INSTALL_DIR" 2>>"$LOG_FILE"; then
    log "Clonage réussi."
  else
    log "Échec du clonage. Vérifier l’accès réseau et l’URL du dépôt."
    exit 1
  fi
else
  log "udp-custom déjà présent, mise à jour..."
  cd "$INSTALL_DIR"
  if git pull 2>>"$LOG_FILE"; then
    log "Mise à jour effectuée."
  else
    log "Échec de la mise à jour du dépôt."
    # ne pas aborter pour laisser continuer l’installation
  fi
fi

cd "$INSTALL_DIR"

# Vérification du binaire précompilé
if [ ! -x "$BIN_PATH" ]; then
  log "Le binaire $BIN_PATH n'est pas exécutable; correction des permissions..."
  if [ -f "$BIN_PATH" ]; then
    chmod +x "$BIN_PATH"
  fi
fi

if [ ! -x "$BIN_PATH" ]; then
  log "❌ Erreur critique: Le binaire $BIN_PATH est manquant ou non exécutable."
  exit 1
fi

# Validation et création/actualisation de la configuration
log "Configuration UDP..."
if [ ! -f "$CONFIG_FILE" ]; then
  log "Création du fichier de configuration UDP custom..."
  mkdir -p "$(dirname "$CONFIG_FILE")"
  cat > "$CONFIG_FILE" << EOF
{
  "server_port": $UDP_PORT,
  "exclude_port": [],
  "udp_timeout": 600,
  "dns_cache": true
}
EOF
else
  log "Mise à jour partielle de la configuration existante..."
  if command -v jq >/dev/null 2>&1; then
    jq ".server_port = $UDP_PORT" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  else
    log "jq non disponible; tentative de remplacement manuelle..."
    sed -i "s/"server_port": [0-9]*/"server_port": $UDP_PORT/" "$CONFIG_FILE"
  fi
fi

# Ouverture du port UDP dans iptables et nftables selon l’infrastructure
log "Ouverture du port UDP $UDP_PORT..."
if command -v nft >/dev/null 2>&1; then
  nft add rule inet filter input udp dport "$UDP_PORT" accept 2>>"$LOG_FILE" || true
else
  iptables -I INPUT -p udp --dport "$UDP_PORT" -j ACCEPT
fi

# Création d’un utilisateur dédié pour limiter les privilèges
if ! id -u udpuser >/dev/null 2>&1; then
  useradd -r -m -d /home/udpuser udpuser || true
  log "Utilisateur dédié udpuser créé."
fi
chown -R udpuser:udpuser "$INSTALL_DIR"

# Service systemd robuste
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
Restart=on-failure
RestartSec=5
Environment=LOG_DIR=$LOG_DIR
StandardOutput=journal
StandardError=journal
SyslogIdentifier=udp-custom

[Install]
WantedBy=multi-user.target
EOF

log "Reload systemd et gestion du service..."
systemctl daemon-reload
systemctl enable udp_custom.service
systemctl restart udp_custom.service

# Démarrage manuel en mode foreground avec journalisation
log "Démarrage du démon UDP Custom et journalisation..."
nohup "$BIN_PATH" -c "$CONFIG_FILE" > /var/log/udp_custom.log 2>&1 &

sleep 3

if pgrep -f "udp-custom-linux-amd64" >/dev/null; then
  log "UDP Custom démarré avec succès sur le port $UDP_PORT."
else
  log "❌ Échec: UDP Custom ne s’est pas lancé correctement."
  exit 1
fi

log "+--------------------------------------------+"
log "|          Configuration terminée            |"
log "|  Configure HTTP Custom avec IP du serveur, |"
log "|  port UDP $UDP_PORT, et activez UDP Custom |"
log "+--------------------------------------------+"

exit 0
