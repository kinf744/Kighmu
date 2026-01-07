#!/bin/bash
# ==========================================================
# udp_request-cohab.sh
# UDP Request Server MAÎTRE (udpServer)
# Cohabitation avec SlowDNS et UDP Custom
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
INSTALL_LOG="/var/log/udp-request-install.log"
RUNTIME_LOG="/var/log/udp-request-server.log"

# Ports critiques à exclure pour cohabitation
EXCLUDED_PORTS=(53 5300 36712 80 443 444 8443 5400 5401 8880 9090 22000)

exec > >(tee -a "$INSTALL_LOG") 2>&1

log()  { echo -e "${GREEN}[+]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
err()  { echo -e "${RED}[ERREUR]${RESET} $*" >&2; }

# ================= ROOT =================
[[ "$EUID" -ne 0 ]] && err "Exécuter en root" && exit 1

clear
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "${GREEN}${BOLD}     UDP REQUEST — MODE MAÎTRE${RESET}"
echo -e "${YELLOW}${BOLD}  Compatible SlowDNS / UDP Custom${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo

# ================= OS CHECK =================
. /etc/os-release || { err "OS indétectable"; exit 1; }
[[ "$ID" != "ubuntu" && "$ID" != "debian" ]] && err "OS non supporté" && exit 1

# ================= DEPENDANCES =================
log "Installation des dépendances minimales..."
apt update -y >/dev/null 2>&1 || warn "apt update ignoré"
apt install -y wget net-tools >/dev/null 2>&1

# ================= IP / IFACE =================
SERVER_IP=$(ip -4 route get 1 | awk '{print $7; exit}')
SERVER_IFACE=$(ip -4 route get 1 | awk '{print $5; exit}')
[[ -z "$SERVER_IP" || -z "$SERVER_IFACE" ]] && err "Impossible de détecter IP ou interface" && exit 1

log "IP serveur   : ${CYAN}$SERVER_IP${RESET}"
log "Interface    : ${CYAN}$SERVER_IFACE${RESET}"

# ================= BINAIRE =================
log "Téléchargement udpServer..."
wget -q -O "$UDP_BIN" \
  "https://bitbucket.org/iopmx/udprequestserver/downloads/udpServer" \
  && chmod +x "$UDP_BIN" \
  || { err "Échec du téléchargement"; exit 1; }

# ================= EXCLUDE =================
EXCLUDE_OPT="-exclude=$(IFS=,; echo "${EXCLUDED_PORTS[*]}")"
log "Ports UDP exclus : ${EXCLUDED_PORTS[*]}"

# ================= SYSTEMD =================
log "Création du service systemd UDP Request (MAÎTRE)..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=UDP Request Server (MAÎTRE UDP)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$UDP_BIN -ip=$SERVER_IP -net=$SERVER_IFACE $EXCLUDE_OPT -mode=system
Restart=always
RestartSec=3
StandardOutput=append:$RUNTIME_LOG
StandardError=append:$RUNTIME_LOG
NoNewPrivileges=true
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable UDPserver >/dev/null 2>&1
systemctl restart UDPserver

sleep 2

# ================= VERIFICATION =================
if systemctl is-active --quiet UDPserver; then
  log "UDP Request MAÎTRE actif"
else
  err "UDP Request ne démarre pas"
  journalctl -u UDPserver -n 40 --no-pager
  exit 1
fi

# ================= RÉSUMÉ =================
echo
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "${GREEN}${BOLD} INSTALLATION TERMINÉE${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "IP serveur   : ${GREEN}$SERVER_IP${RESET}"
echo -e "Interface    : ${GREEN}$SERVER_IFACE${RESET}"
echo -e "Ports exclus : ${GREEN}${EXCLUDED_PORTS[*]}${RESET}"
echo -e "Service      : ${GREEN}UDPserver (MAÎTRE)${RESET}"
echo -e "Logs runtime : ${GREEN}$RUNTIME_LOG${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
