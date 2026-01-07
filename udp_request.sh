#!/bin/bash
# ==========================================================
# udp_request.sh
# Installe et configure le serveur UDP Request (udpServer)
# Compatible SocksIP Tunnel - Mode UDP Request
# OS : Ubuntu 20.04+ / Debian 10+
# ==========================================================

set -euo pipefail

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

UDP_BIN="/usr/bin/udpServer"
SERVICE_FILE="/etc/systemd/system/UDPserver.service"
LOG_FILE="/var/log/udp-request-install.log"

exec > >(tee -a "$LOG_FILE") 2>&1

banner() {
  clear
  echo -e "${CYAN}${BOLD}============================================${RESET}"
  echo -e "${GREEN}${BOLD}      UDP Request Server Installer${RESET}"
  echo -e "${YELLOW}${BOLD}      SocksIP Tunnel - udpServer${RESET}"
  echo -e "${CYAN}${BOLD}============================================${RESET}"
  echo
}

log() { echo -e "${GREEN}[+]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
err() { echo -e "${RED}[ERREUR]${RESET} $*" >&2; }

[[ "$EUID" -ne 0 ]] && err "Exécuter en root" && exit 1

banner

. /etc/os-release || { err "OS indétectable"; exit 1; }
[[ "$ID" != "ubuntu" && "$ID" != "debian" ]] && err "OS non supporté" && exit 1

log "Mise à jour paquets..."
apt update -y >/dev/null 2>&1 || warn "apt update ignoré"

ip=$(ip -4 addr show | awk '/inet / && $2 !~ /^127./ {print $2}' | head -n1 | cut -d/ -f1)
iface=$(ip -4 addr show | awk '/inet / && $2 !~ /^127./ {print $7}' | head -n1)
[[ -z "$ip" || -z "$iface" ]] && err "IP/interface introuvable" && exit 1

SERVER_IP="$ip"
SERVER_IFACE="$iface"

log "IP        : ${CYAN}${SERVER_IP}${RESET}"
log "Interface : ${CYAN}${SERVER_IFACE}${RESET}"

read -rp "$(echo -e "${YELLOW}[?]${RESET} Ports UDP à exclure [ENTER = aucun] : ")" EXCLUDE_PORTS

PORT_LIST=()
for p in $EXCLUDE_PORTS; do
  [[ "$p" =~ ^[0-9]+$ && "$p" -gt 0 ]] && PORT_LIST+=("$p")
done

# Ajouter automatiquement le port UDP Custom (36712) à la liste des exclusions
PORT_LIST+=("36712" "53" "5300" "81" "22" "80" "443" "8443" "5401" "5400" "8880" "9090" "444" "22000")

EXCLUDE_OPT=""
if [[ "${#PORT_LIST[@]}" -gt 0 ]]; then
  EXCLUDE_OPT=" -exclude=$(IFS=,; echo "${PORT_LIST[*]}")"
  log "Ports exclus : ${PORT_LIST[*]}"
fi

log "Téléchargement udpServer..."
wget -q -O "$UDP_BIN" "https://bitbucket.org/iopmx/udprequestserver/downloads/udpServer" \
  && chmod +x "$UDP_BIN" \
  || { err "Téléchargement échoué"; exit 1; }

cat > "$SERVICE_FILE" <<EOF
[Unit]
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$UDP_BIN -ip=$SERVER_IP -net=$SERVER_IFACE$EXCLUDE_OPT -mode=system >> /var/log/udp-request-server.log 2>&1
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start UDPserver || { err "Démarrage échoué"; exit 1; }
systemctl enable UDPserver >/dev/null 2>&1

echo
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "${GREEN}${BOLD} Installation terminée${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "IP        : ${GREEN}${SERVER_IP}${RESET}"
echo -e "Interface : ${GREEN}${SERVER_IFACE}${RESET}"
echo -e "Ports UDP : ${GREEN}${PORT_LIST[*]:-aucun}${RESET}"
echo -e "Service   : ${GREEN}UDPserver${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
