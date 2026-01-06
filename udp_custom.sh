#!/bin/bash
# ==========================================================
# udp_custom.sh
# UDP Custom Server → SSH
# Compatible HTTP Custom (Android)
# OS : Ubuntu 20.04+ / Debian 10+
# ==========================================================

set -euo pipefail

# ================= COULEURS =================
setup_colors() {
  RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; BOLD=""; RESET=""
  if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"
    CYAN="$(tput setaf 6)"
    BOLD="$(tput bold)"
    RESET="$(tput sgr0)"
  fi
}
setup_colors

# ================= VARIABLES =================
INSTALL_DIR="/opt/udp-custom"
BIN_PATH="$INSTALL_DIR/udp-custom-linux-amd64"
CONFIG_FILE="$INSTALL_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/udp_custom.service"

LOG_DIR="/var/log/udp-custom"
BIN_LOG="$LOG_DIR/udp-custom.log"

exec > >(tee -a "$BIN_LOG") 2>&1

# ================= FONCTIONS =================
banner() {
  clear
  echo -e "${CYAN}${BOLD}============================================${RESET}"
  echo -e "${GREEN}${BOLD}        UDP Custom Server Installer${RESET}"
  echo -e "${YELLOW}${BOLD}        Tunnel UDP → SSH${RESET}"
  echo -e "${CYAN}${BOLD}============================================${RESET}"
  echo
}

log()  { echo -e "${GREEN}[+]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
err()  { echo -e "${RED}[ERREUR]${RESET} $*" >&2; }

# ================= CHECKS =================
[[ "$EUID" -ne 0 ]] && err "Exécuter en root" && exit 1

. /etc/os-release || { err "OS indétectable"; exit 1; }
[[ "$ID" != "ubuntu" && "$ID" != "debian" ]] && err "OS non supporté" && exit 1

banner

# ================= INSTALL =================
log "Mise à jour des paquets..."
apt update -y >/dev/null 2>&1 || warn "apt update ignoré"

log "Installation des dépendances..."
apt install -y wget net-tools openssh-server

mkdir -p "$INSTALL_DIR" "$LOG_DIR"

# ================= CONFIG =================
read -rp "$(echo -e "${YELLOW}[?]${RESET} Port UDP à écouter : ")" UDP_PORT

log "Téléchargement du binaire UDP Custom..."
wget -q -O "$BIN_PATH" \
"https://raw.githubusercontent.com/noobconner21/UDP-Custom-Script/main/udp-custom-linux-amd64" \
|| { err "Téléchargement échoué"; exit 1; }

chmod +x "$BIN_PATH"

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

log "config.json créé"

# ================= SYSTEMD =================
log "Création service systemd..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=UDP Custom Server
After=network.target

[Service]
ExecStart=$BIN_PATH server --config $CONFIG_FILE
Restart=always
RestartSec=3
LimitNOFILE=1048576
StandardOutput=append:$BIN_LOG
StandardError=append:$BIN_LOG
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable udp_custom >/dev/null 2>&1
systemctl restart udp_custom
sleep 2

# ================= VERIFICATION =================
if systemctl is-active --quiet udp_custom; then
  log "Service udp_custom actif"
else
  err "Service udp_custom en échec"
  journalctl -u udp_custom --no-pager | tail -n 40
  exit 1
fi

if ss -lunp | grep -q ":$UDP_PORT"; then
  log "UDP Custom écoute sur le port $UDP_PORT"
else
  warn "Le port UDP $UDP_PORT n'écoute pas (vérifier config)"
fi

# ================= FIN =================
echo
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "${GREEN}${BOLD} Installation terminée${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "Port UDP : ${GREEN}$UDP_PORT${RESET}"
echo -e "Service  : ${GREEN}udp_custom${RESET}"
echo -e "Logs     : ${GREEN}$BIN_LOG${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
