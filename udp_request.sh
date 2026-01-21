#!/bin/bash
# ==========================================================
# udp_request.sh — VERSION STABLE FINALE
# UDP Request Server (SlowDNS / UDP Custom / Xray FRIENDLY)
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
UDP_BIN="/usr/bin/udp_request"
SERVICE_FILE="/etc/systemd/system/udp_request.service"
INSTALL_LOG="/var/log/udp_request-install.log"

exec > >(tee -a "$INSTALL_LOG") 2>&1

log()  { echo -e "${GREEN}[+]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
err()  { echo -e "${RED}[ERREUR]${RESET} $*" >&2; }

# ================= ROOT =================
[[ "$EUID" -ne 0 ]] && err "Exécuter ce script en root" && exit 1

clear
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "${GREEN}${BOLD}     UDP REQUEST — MODE STABLE${RESET}"
echo -e "${YELLOW}${BOLD}  Compatible SlowDNS / UDP Custom / Xray${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo

# ================= OS CHECK =================
. /etc/os-release || { err "OS indétectable"; exit 1; }
[[ "$ID" != "ubuntu" && "$ID" != "debian" ]] && err "OS non supporté" && exit 1

# ================= DEPENDANCES =================
log "Installation des dépendances..."
apt update -y >/dev/null 2>&1 || true
apt install -y wget net-tools iproute2 >/dev/null 2>&1

# ================= NETWORK =================
SERVER_IFACE=$(ip -4 route get 1 | awk '{print $5; exit}')
SERVER_IP=$(ip -4 route get 1 | awk '{print $7; exit}')

[[ -z "$SERVER_IFACE" ]] && err "Interface réseau introuvable" && exit 1

log "Interface réseau : ${CYAN}$SERVER_IFACE${RESET}"
log "IP détectée      : ${CYAN}$SERVER_IP${RESET}"

# ================= CLEANUP =================
log "Arrêt et nettoyage des anciennes instances..."
systemctl stop UDPserver 2>/dev/null || true
pkill -f udpServer 2>/dev/null || true
sleep 2

# ================= BINAIRE =================
log "Téléchargement du binaire udpServer..."
wget -q -O "$UDP_BIN" \
  "https://github.com/kinf744/Kighmu/releases/download/v1.0.0/udp_request" \
  || { err "Échec du téléchargement udpServer"; exit 1; }
chmod +x "$UDP_BIN"

# ================= PORTS UDP EXCLUS =================
log "Définition des ports UDP exclus (statique + dynamique)..."

# --- Ports critiques connus (NE JAMAIS TOUCHER)
EXCLUDED_STATIC_PORTS=(
  53
  80 81
  443 444
  8080 8880
  9090
  5300 5400 5401
  8443
  25432
  30300 30310
  36712
)

# --- Ports UDP déjà utilisés (dynamiques)
USED_UDP_PORTS=$(ss -lunp | awk 'NR>1 {print $5}' \
  | awk -F: '{print $NF}' \
  | grep -E '^[0-9]+$' \
  | sort -u)

# --- Fusion + déduplication
EXCLUDED_ALL_PORTS=$(printf "%s\n" \
  "${EXCLUDED_STATIC_PORTS[@]}" \
  $USED_UDP_PORTS \
  | sort -n -u | paste -sd,)

EXCLUDE_OPT="-exclude=$EXCLUDED_ALL_PORTS"

log "Ports UDP exclus finaux : ${CYAN}$EXCLUDED_ALL_PORTS${RESET}"

# ================= SYSTEMD =================
log "Création du service systemd UDPserver..."

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=UDP Request Server (STABLE)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$UDP_BIN \\
  -net=$SERVER_IFACE \\
  $EXCLUDE_OPT \\
  -mode=system
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=5
StandardOutput=journal
StandardError=journal
NoNewPrivileges=true
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable UDPserver >/dev/null 2>&1
systemctl restart UDPserver

sleep 3

# ================= VERIFICATION =================
if systemctl is-active --quiet UDPserver; then
  log "UDP Request STABLE actif et fonctionnel"
else
  err "Échec du démarrage UDPserver"
  journalctl -u UDPserver -n 50 --no-pager
  exit 1
fi

# ================= RÉSUMÉ =================
echo
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "${GREEN}${BOLD} INSTALLATION TERMINÉE${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "Interface réseau : ${GREEN}$SERVER_IFACE${RESET}"
echo -e "IP détectée      : ${GREEN}$SERVER_IP${RESET}"
echo -e "Mode             : ${GREEN}UDP STABLE${RESET}"
echo -e "Ports exclus     : ${GREEN}$EXCLUDED_ALL_PORTS${RESET}"
echo -e "Service          : ${GREEN}UDPserver${RESET}"
echo -e "Logs             : ${GREEN}journalctl -u UDPserver -f${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
