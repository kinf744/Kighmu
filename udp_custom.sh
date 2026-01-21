#!/bin/bash
# ==========================================================
# udp_custom_install.sh
# UDP Custom Server (Stable) avec config.json
# Compatible SlowDNS / UDP Request
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
UDP_BIN="/usr/bin/udp-custom"
CONFIG_JSON="/usr/bin/config.json"
SERVICE_FILE="/etc/systemd/system/udp-custom.service"
INSTALL_LOG="/var/log/udp-customd.log"
RUNTIME_LOG="/var/log/udp-custom.log"

EXCLUDED_PORTS=(53 5300 5400 30300 30310 25432 4466 81 8880 80 9090 444 5401 8443)

exec > >(tee -a "$INSTALL_LOG") 2>&1

log()  { echo -e "${GREEN}[+]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
err()  { echo -e "${RED}[ERREUR]${RESET} $*" >&2; }

# ================= ROOT =================
[[ "$EUID" -ne 0 ]] && err "Exécuter ce script en root" && exit 1

clear
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "${GREEN}${BOLD}     UDP CUSTOM — MODE STABLE${RESET}"
echo -e "${YELLOW}${BOLD}  Compatible SlowDNS / UDP Request${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo

# ================= OS CHECK =================
. /etc/os-release || { err "OS indétectable"; exit 1; }
[[ "$ID" != "ubuntu" && "$ID" != "debian" ]] && err "OS non supporté" && exit 1

# ================= DEPENDANCES =================
log "Installation des dépendances minimales..."
apt update -y >/dev/null 2>&1 || warn "apt update ignoré"
apt install -y wget net-tools iproute2 iptables iptables-persistent >/dev/null 2>&1

# ================= IP / IFACE =================
SERVER_IP=$(ip -4 route get 1 | awk '{print $7; exit}')
SERVER_IFACE=$(ip -4 route get 1 | awk '{print $5; exit}')
[[ -z "$SERVER_IP" || -z "$SERVER_IFACE" ]] && err "Impossible de détecter IP ou interface" && exit 1

log "IP serveur   : ${CYAN}$SERVER_IP${RESET}"
log "Interface    : ${CYAN}$SERVER_IFACE${RESET}"

# ================= BINAIRE =================
log "Téléchargement udp-custom..."
wget -q -O "$UDP_BIN" \
  "https://github.com/kinf744/Kighmu/releases/download/v1.0.0/udp-custom" \
  && chmod +x "$UDP_BIN" \
  || { err "Échec du téléchargement udp-custom"; exit 1; }

# ================= CONFIG =================
log "Création du fichier config.json..."
cat > "$CONFIG_JSON" <<EOF
{
  "listen": ":36712",
  "stream_buffer": 209715200,
  "receive_buffer": 209715200,
  "auth": {
    "mode": "passwords"
  }
}
EOF
chmod 644 "$CONFIG_JSON"

# ================= IPTABLES =================
log "Configuration iptables (exclusion des ports UDP)..."
for port in "${EXCLUDED_PORTS[@]}"; do
  iptables -I INPUT -p udp --dport "$port" -j ACCEPT
done
iptables-save >/etc/iptables/rules.v4
log "Ports exclus : ${EXCLUDED_PORTS[*]}"

# ================= SYSTEMD =================
log "Création du service systemd udp-custom..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=UDP Custom Server (Stable + iptables)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/usr/bin
ExecStart=$UDP_BIN
Restart=always
RestartSec=2
StandardOutput=append:$RUNTIME_LOG
StandardError=append:$RUNTIME_LOG
NoNewPrivileges=true
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable udp-custom >/dev/null 2>&1
systemctl restart udp-custom

# ================= VERIFICATION =================
sleep 3
if systemctl is-active --quiet udp-custom; then
  log "udp-custom STABLE actif"
else
  err "udp-custom ne démarre pas, vérifiez $RUNTIME_LOG"
  journalctl -u udp-custom -n 50 --no-pager
  exit 1
fi

# ================= RÉSUMÉ =================
echo
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "${GREEN}${BOLD} INSTALLATION TERMINÉE${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "IP serveur   : ${GREEN}$SERVER_IP${RESET}"
echo -e "Interface    : ${GREEN}$SERVER_IFACE${RESET}"
echo -e "Mode         : ${GREEN}UDP (STABLE)${RESET}"
echo -e "Ports exclus : ${GREEN}${EXCLUDED_PORTS[*]}${RESET}"
echo -e "Service      : ${GREEN}udp-custom${RESET}"
echo -e "Config       : ${GREEN}$CONFIG_JSON${RESET}"
echo -e "Logs runtime : ${GREEN}$RUNTIME_LOG${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
