#!/bin/bash
# ==========================================================
# UDP REQUEST — INSTALLATION STABLE (FIX DÉFINITIF)
# Compatible SlowDNS / UDP Custom / Xray
# OS : Ubuntu 20.04+ / Debian 10+
# Auteur : corrigé pour binaire interactif udp_request
# ==========================================================

set -e

# ================= COULEURS =================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

log()  { echo -e "${GREEN}[+]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
err()  { echo -e "${RED}[ERREUR]${RESET} $*"; exit 1; }

# ================= ROOT =================
[[ "$EUID" -ne 0 ]] && err "Exécute ce script en root"

clear
echo -e "${CYAN}============================================${RESET}"
echo -e "${GREEN}     UDP REQUEST — MODE STABLE${RESET}"
echo -e "${YELLOW} Compatible SlowDNS / UDP Custom / Xray${RESET}"
echo -e "${CYAN}============================================${RESET}"
echo

# ================= VARIABLES =================
UDP_BIN="/usr/bin/udp_request"
WRAPPER="/usr/bin/udp_requestd"
SERVICE="/etc/systemd/system/UDPserver.service"
LOG_FILE="/var/log/UDPserver.log"

# Ports UDP exclus (anti‑conflit)
EXCLUDED_PORTS=(53 80 81 443 444 8443 8880 9090 5300 5400 5401 36712 25432 30300 30310)

# ================= DEPENDANCES =================
log "Installation des dépendances..."
apt update -y >/dev/null 2>&1 || true
apt install -y wget iproute2 net-tools >/dev/null 2>&1

# ================= IP / IFACE =================
SERVER_IP=$(ip -4 route get 1 | awk '{print $7; exit}')
SERVER_IFACE=$(ip -4 route get 1 | awk '{print $5; exit}')

[[ -z "$SERVER_IP" || -z "$SERVER_IFACE" ]] && err "Impossible de détecter IP ou interface"

log "Interface réseau : $SERVER_IFACE"
log "IP détectée      : $SERVER_IP"

# ================= NETTOYAGE =================
log "Arrêt et nettoyage des anciennes instances..."
systemctl stop udp-request 2>/dev/null || true
pkill -f udp_request 2>/dev/null || true
rm -f "$UDP_BIN" "$WRAPPER" "$SERVICE"

# ================= TELECHARGEMENT =================
log "Téléchargement du binaire udp_request..."
wget -q -O "$UDP_BIN" \
  "https://github.com/kinf744/Kighmu/releases/download/v1.0.0/udp_request" \
  || err "Échec téléchargement udp_request"

chmod +x "$UDP_BIN"

# ================= WRAPPER NON INTERACTIF =================
log "Création du wrapper non-interactif (FIX)..."

EXCLUDE_OPT=$(IFS=,; echo "${EXCLUDED_PORTS[*]}")

cat > "$WRAPPER" <<EOF
#!/bin/bash
# Wrapper daemon-safe pour udp_request
exec </dev/null
exec >>$LOG_FILE 2>&1

while true; do
  $UDP_BIN \\
    -ip=$SERVER_IP \\
    -net=$SERVER_IFACE \\
    -exclude=$EXCLUDE_OPT \\
    -mode=system

  sleep 2
done
EOF

chmod +x "$WRAPPER"

# ================= SYSTEMD =================
log "Création du service systemd..."
cat > "$SERVICE" <<EOF
[Unit]
Description=UDP Request (Stable Daemon)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$WRAPPER
Restart=always
RestartSec=2
NoNewPrivileges=true
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable udp-request
systemctl restart udp-request

sleep 3

# ================= VERIFICATION =================
if systemctl is-active --quiet udp-request; then
  log "UDP Request actif et STABLE"
else
  err "UDP Request ne démarre pas"
fi

# ================= RESUME =================
echo
echo -e "${CYAN}============================================${RESET}"
echo -e "${GREEN} INSTALLATION TERMINÉE AVEC SUCCÈS${RESET}"
echo -e "${CYAN}============================================${RESET}"
echo -e "Service      : udp-request"
echo -e "Interface    : $SERVER_IFACE"
echo -e "IP serveur   : $SERVER_IP"
echo -e "Ports exclus : ${EXCLUDED_PORTS[*]}"
echo -e "Logs         : $LOG_FILE"
echo -e "${CYAN}============================================${RESET}"
