#!/bin/bash
# ==========================================================
# udp_request.sh
# UDP Request Server (udpServer)
# Compatible avec UDP Custom / SlowDNS
# OS : Ubuntu 20.04+ / Debian 10+
# ==========================================================

set -euo pipefail

# ================= COULEURS =================
setup_colors() {
  RED=""; GREEN=""; YELLOW=""; CYAN=""; BOLD=""; RESET=""
  if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    CYAN="$(tput setaf 6)"
    BOLD="$(tput bold)"
    RESET="$(tput sgr0)"
  fi
}
setup_colors

# ================= VARIABLES =================
UDP_BIN="/usr/bin/udpServer"
SERVICE_FILE="/etc/systemd/system/UDPserver.service"
LOG_FILE="/var/log/udp-request-install.log"
RUNTIME_LOG="/var/log/udp-request-server.log"

# ⚠️ Ports à EXCLURE (UDP Custom + autres tunnels)
EXCLUDED_PORTS=(
  36712   # UDP Custom
  53
  80
  443
  444
  8443
  5300
  5401
  5400
  9090
  22000
)

# ================= LOGGING =================
exec > >(tee -a "$LOG_FILE") 2>&1

log()  { echo -e "${GREEN}[+]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
err()  { echo -e "${RED}[ERREUR]${RESET} $*" >&2; }

# ================= CHECK ROOT =================
[[ "$EUID" -ne 0 ]] && err "Exécuter en root" && exit 1

clear
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "${GREEN}${BOLD}     UDP Request Server Installer${RESET}"
echo -e "${YELLOW}${BOLD}  Compatible UDP Custom / SlowDNS${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo

# ================= OS CHECK =================
. /etc/os-release || { err "OS indétectable"; exit 1; }
[[ "$ID" != "ubuntu" && "$ID" != "debian" ]] && err "OS non supporté" && exit 1

# ================= DEPENDANCES =================
log "Installation dépendances..."
apt update -y >/dev/null 2>&1 || warn "apt update ignoré"
apt install -y wget net-tools nftables >/dev/null 2>&1

# ================= IP / IFACE =================
SERVER_IP=$(ip -4 addr show | awk '/inet / && $2 !~ /^127./ {print $2}' | head -n1 | cut -d/ -f1)
SERVER_IFACE=$(ip route | awk '/default/ {print $5}' | head -n1)

[[ -z "$SERVER_IP" || -z "$SERVER_IFACE" ]] && err "IP ou interface introuvable" && exit 1

log "IP        : ${CYAN}${SERVER_IP}${RESET}"
log "Interface : ${CYAN}${SERVER_IFACE}${RESET}"

# ================= TELECHARGEMENT =================
log "Téléchargement udpServer..."
wget -q -O "$UDP_BIN" "https://bitbucket.org/iopmx/udprequestserver/downloads/udpServer" \
  && chmod +x "$UDP_BIN" \
  || { err "Téléchargement échoué"; exit 1; }

# ================= EXCLUDE =================
EXCLUDE_OPT="-exclude=$(IFS=,; echo "${EXCLUDED_PORTS[*]}")"
log "Ports UDP exclus : ${EXCLUDED_PORTS[*]}"

# ================= SYSTEMD =================
log "Création service systemd..."

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=UDP Request Server (cohabitation UDP Custom)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$UDP_BIN -ip=0.0.0.0 -net=$SERVER_IFACE $EXCLUDE_OPT -mode=system
Restart=always
RestartSec=3
StandardOutput=append:$RUNTIME_LOG
StandardError=append:$RUNTIME_LOG
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable UDPserver >/dev/null 2>&1
systemctl restart UDPserver

sleep 2

# ================= VERIFICATION =================
if systemctl is-active --quiet UDPserver; then
  log "UDP Request actif et fonctionnel"
else
  err "UDP Request ne démarre pas"
  journalctl -u UDPserver -n 30 --no-pager
  exit 1
fi

echo
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "${GREEN}${BOLD} Installation terminée${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "IP        : ${GREEN}${SERVER_IP}${RESET}"
echo -e "Interface : ${GREEN}${SERVER_IFACE}${RESET}"
echo -e "Ports exclus : ${GREEN}${EXCLUDED_PORTS[*]}${RESET}"
echo -e "Service   : ${GREEN}UDPserver${RESET}"
echo -e "Logs      : ${GREEN}$RUNTIME_LOG${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
