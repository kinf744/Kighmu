#!/bin/bash
# ==========================================================
# udp_request.sh
# Installe et configure le serveur UDP Request (udpServer)
# Compatible SocksIP Tunnel - Mode UDP Request
# OS : Ubuntu 20.04+ / Debian 10+
# ==========================================================

set -euo pipefail

# ============================
# Couleurs & fonctions log
# ============================
setup_colors() {
  RED=""; GREEN=""; YELLOW=""; CYAN=""; BOLD=""; RESET=""
  if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"; CYAN="$(tput setaf 6)"
    BOLD="$(tput bold)"; RESET="$(tput sgr0)"
  fi
}
setup_colors

log() { echo -e "${GREEN}[+]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
err() { echo -e "${RED}[ERREUR]${RESET} $*" >&2; }

[[ "$EUID" -ne 0 ]] && err "Exécuter en root" && exit 1

# ============================
# Variables
# ============================
UDP_BIN="/usr/bin/udpServer"
SERVICE_FILE="/etc/systemd/system/UDPserver.service"
LOG_FILE="/var/log/udp-request-install.log"
UDP_REQUEST_PORT=54000   # Port dédié pour UDP Request

exec > >(tee -a "$LOG_FILE") 2>&1

# ============================
# Bannière
# ============================
banner() {
  clear
  echo -e "${CYAN}${BOLD}============================================${RESET}"
  echo -e "${GREEN}${BOLD}      UDP Request Server Installer${RESET}"
  echo -e "${YELLOW}${BOLD}      SocksIP Tunnel - udpServer${RESET}"
  echo -e "${CYAN}${BOLD}============================================${RESET}"
  echo
}
banner

# ============================
# Vérification OS
# ============================
. /etc/os-release || { err "OS indétectable"; exit 1; }
[[ "$ID" != "ubuntu" && "$ID" != "debian" ]] && err "OS non supporté" && exit 1

# ============================
# Détection IP / Interface
# ============================
ip=$(ip -4 addr show | awk '/inet / && $2 !~ /^127./ {print $2}' | head -n1 | cut -d/ -f1)
iface=$(ip -4 addr show | awk '/inet / && $2 !~ /^127./ {print $7}' | head -n1)
[[ -z "$ip" || -z "$iface" ]] && err "IP/interface introuvable" && exit 1

SERVER_IP="$ip"
SERVER_IFACE="$iface"
log "IP        : ${CYAN}${SERVER_IP}${RESET}"
log "Interface : ${CYAN}${SERVER_IFACE}${RESET}"

# ============================
# Dépendances
# ============================
log "Mise à jour et installation des dépendances..."
apt update -y >/dev/null 2>&1 || warn "apt update ignoré"
apt install -y wget nftables net-tools openssh-server tcpdump

# ============================
# Téléchargement binaire
# ============================
log "Téléchargement udpServer..."
wget -q -O "$UDP_BIN" "https://bitbucket.org/iopmx/udprequestserver/downloads/udpServer" \
  && chmod +x "$UDP_BIN" \
  || { err "Téléchargement échoué"; exit 1; }

# ============================
# Configuration nftables spécifique UDP Request
# ============================
log "Configuration nftables pour UDP Request ($UDP_REQUEST_PORT)..."

nft list tables inet tunnels &>/dev/null || nft add table inet tunnels
nft list chain inet tunnels input &>/dev/null || \
    nft add chain inet tunnels input { type filter hook input priority 0 \; policy drop \; }

# Autoriser UDP Request
nft delete rule inet tunnels input udp dport $UDP_REQUEST_PORT accept &>/dev/null || true
nft add rule inet tunnels input udp dport $UDP_REQUEST_PORT accept

# Autoriser loopback et ICMP
nft delete rule inet tunnels input iif lo accept &>/dev/null || true
nft add rule inet tunnels input iif lo accept
nft delete rule inet tunnels input ip protocol icmp accept &>/dev/null || true
nft add rule inet tunnels input ip protocol icmp accept

# Autoriser SSH TCP
nft delete rule inet tunnels input tcp dport 22 accept &>/dev/null || true
nft add rule inet tunnels input tcp dport 22 accept

systemctl enable nftables
systemctl restart nftables

log "✅ nftables mis à jour pour UDP Request"

# ============================
# Création service systemd
# ============================
cat > "$SERVICE_FILE" <<EOF
[Unit]
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$UDP_BIN -ip=$SERVER_IP -net=$SERVER_IFACE -port=$UDP_REQUEST_PORT -mode=system >> /var/log/udp-request-server.log 2>&1
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start UDPserver || { err "Démarrage échoué"; exit 1; }
systemctl enable UDPserver >/dev/null 2>&1

# ============================
# Fin
# ============================
echo
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "${GREEN}${BOLD} Installation terminée${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "IP        : ${GREEN}${SERVER_IP}${RESET}"
echo -e "Interface : ${GREEN}${SERVER_IFACE}${RESET}"
echo -e "Port UDP  : ${GREEN}${UDP_REQUEST_PORT}${RESET}"
echo -e "Service   : ${GREEN}UDPserver${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
