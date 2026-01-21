#!/bin/bash
# ==========================================================
# udp_custom.sh — VERSION FINALE STABLE
# UDP-CUSTOM + EXCLUSION PORTS (iptables)
# ==========================================================

set -euo pipefail

# ================= COULEURS =================
RED=""; GREEN=""; YELLOW=""; CYAN=""; BOLD=""; RESET=""
if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  RED="$(tput setaf 1)"
  GREEN="$(tput setaf 2)"
  YELLOW="$(tput setaf 3)"
  CYAN="$(tput setaf 6)"
  BOLD="$(tput bold)"
  RESET="$(tput sgr0)"
fi

log()  { echo -e "${GREEN}[+]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
err()  { echo -e "${RED}[ERREUR]${RESET} $*" >&2; }

# ================= ROOT =================
[[ "$EUID" -ne 0 ]] && err "Exécuter ce script en root" && exit 1

# ================= VARIABLES =================
UDP_BIN="/usr/bin/udp-custom"
SERVICE_FILE="/etc/systemd/system/udp-custom.service"
INSTALL_LOG="/var/log/udp-custom-install.log"
RUNTIME_LOG="/var/log/udp-custom.log"

# PORTS À EXCLURE (SlowDNS / UDP Request / Xray)
EXCLUDED_PORTS=(53 5300 5400 30300 30310 25432 4466 81 8880 80 9090 444 5401 8443)

exec > >(tee -a "$INSTALL_LOG") 2>&1

clear
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "${GREEN}${BOLD} UDP CUSTOM — MODE STABLE (iptables)${RESET}"
echo -e "${YELLOW}${BOLD} SlowDNS / UDP Request compatibles${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo

# ================= OS CHECK =================
. /etc/os-release || { err "OS indétectable"; exit 1; }
[[ "$ID" != "ubuntu" && "$ID" != "debian" ]] && err "OS non supporté" && exit 1

# ================= DEPENDANCES =================
log "Installation des dépendances..."
apt update -y >/dev/null 2>&1 || true
apt install -y wget iptables iptables-persistent net-tools iproute2 >/dev/null 2>&1

# ================= IP =================
SERVER_IP=$(ip -4 route get 1 | awk '{print $7; exit}')
log "IP serveur : ${CYAN}$SERVER_IP${RESET}"

# ================= BINAIRE =================
log "Téléchargement udp-custom..."
wget -q -O "$UDP_BIN" \
  "https://github.com/kinf744/Kighmu/releases/download/v1.0.0/udp-custom" \
  || { err "Téléchargement échoué"; exit 1; }

chmod +x "$UDP_BIN"
file "$UDP_BIN" | grep -q ELF || { err "Binaire invalide"; exit 1; }
log "Binaire validé (ELF)"

# ================= IPTABLES (EXCLUSION PORTS) =================
log "Configuration iptables (exclusion des ports UDP)..."

iptables -t mangle -N UDP_CUSTOM_EXCLUDE 2>/dev/null || true
iptables -t mangle -F UDP_CUSTOM_EXCLUDE

for port in "${EXCLUDED_PORTS[@]}"; do
  iptables -t mangle -A UDP_CUSTOM_EXCLUDE -p udp --dport "$port" -j RETURN
done

# Appliquer la chaîne au trafic UDP entrant
iptables -t mangle -C PREROUTING -p udp -j UDP_CUSTOM_EXCLUDE 2>/dev/null \
  || iptables -t mangle -A PREROUTING -p udp -j UDP_CUSTOM_EXCLUDE

iptables-save > /etc/iptables/rules.v4
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
ExecStart=/usr/bin/udp-custom
Restart=on-failure
RestartSec=3
StandardOutput=append:$RUNTIME_LOG
StandardError=append:$RUNTIME_LOG
NoNewPrivileges=true
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable udp-custom >/dev/null 2>&1
systemctl restart udp-custom

sleep 3

# ================= VERIFICATION =================
if systemctl is-active --quiet udp-custom; then
  log "udp-custom est ACTIF et STABLE"
else
  err "udp-custom ne démarre pas"
  journalctl -u udp-custom -n 50 --no-pager
  exit 1
fi

# ================= RÉSUMÉ =================
echo
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "${GREEN}${BOLD} INSTALLATION TERMINÉE${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "IP serveur   : ${GREEN}$SERVER_IP${RESET}"
echo -e "Service      : ${GREEN}udp-custom${RESET}"
echo -e "Ports exclus : ${GREEN}${EXCLUDED_PORTS[*]}${RESET}"
echo -e "Logs runtime : ${GREEN}$RUNTIME_LOG${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
