#!/bin/bash
# ==========================================================
# UDP Custom Server - Installation Complète + Exclude Ports
# Version stable inspirée de UDP Request
# Ubuntu 20.04+ / Debian 12+
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
UDP_PORT=36712
UDP_DIR="/root/udp"
UDP_BIN="$UDP_DIR/udp-custom"
CONFIG_FILE="$UDP_DIR/config.json"
UDPGW_BIN="/usr/bin/udpgw"
SERVICE_UDP="udp-custom.service"
SERVICE_UDPGW="udpgw.service"
LOG_INSTALL="/var/log/udp-custom-install.log"
LOG_RUNTIME="/var/log/udp-custom-runtime.log"
DEFAULT_EXCLUDE_PORTS="53,80,8443,8880,5300,9090,4466,444,5401,54000"

exec > >(tee -a "$LOG_INSTALL") 2>&1

log()  { echo -e "${GREEN}[+]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
err()  { echo -e "${RED}[ERREUR]${RESET} $*" >&2; }

# ================= ROOT =================
[[ "$EUID" -ne 0 ]] && err "Exécuter ce script en root" && exit 1

# ================= CLEAR =================
clear
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "${GREEN}${BOLD}     UDP CUSTOM — INSTALLATION STABLE${RESET}"
echo -e "${YELLOW}${BOLD}  Compatible SlowDNS / UDP Request${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo

# ================= OS CHECK =================
. /etc/os-release || { err "OS indétectable"; exit 1; }
[[ "$ID" != "ubuntu" && "$ID" != "debian" ]] && err "OS non supporté: $ID" && exit 1
log "OS détecté: $PRETTY_NAME"

# ================= DEPENDANCES =================
log "Installation des dépendances minimales..."
apt update -y >/dev/null 2>&1 || warn "apt update ignoré"
apt install -y wget curl jq ca-certificates net-tools iproute2 dos2unix || warn "Certaines dépendances n'ont pas pu être installées"
log "Dépendances installées"

# ================= IP / INTERFACE =================
SERVER_IP=$(ip -4 route get 1 | awk '{print $7; exit}')
SERVER_IFACE=$(ip -4 route get 1 | awk '{print $5; exit}')
[[ -z "$SERVER_IP" || -z "$SERVER_IFACE" ]] && warn "Impossible de détecter IP ou interface, utilisation par défaut" && SERVER_IP="0.0.0.0" && SERVER_IFACE="eth0"
log "IP serveur   : $SERVER_IP"
log "Interface    : $SERVER_IFACE"

# ================= CLEAN PREVIOUS =================
log "Nettoyage des anciennes installations..."
systemctl stop $SERVICE_UDP 2>/dev/null || true
systemctl disable $SERVICE_UDP 2>/dev/null || true
rm -rf "$UDP_DIR" "$UDPGW_BIN"
rm -f /etc/systemd/system/$SERVICE_UDP /etc/systemd/system/$SERVICE_UDPGW
rm -f /usr/local/bin/udp-custom
log "Anciennes installations nettoyées"

# ================= CREATE DIR =================
mkdir -p "$UDP_DIR"

# ================= DOWNLOAD BINAIRES =================
log "Téléchargement des binaires UDP Custom..."
wget -q "https://raw.github.com/http-custom/udp-custom/main/bin/udp-custom-linux-amd64" -O "$UDP_BIN" \
  && chmod +x "$UDP_BIN" \
  || warn "Impossible de télécharger $UDP_BIN"
ln -sf "$UDP_BIN" /usr/local/bin/udp-custom

wget -q "https://raw.github.com/http-custom/udp-custom/main/module/udpgw" -O "$UDPGW_BIN" \
  && chmod +x "$UDPGW_BIN" \
  || warn "Impossible de télécharger $UDPGW_BIN"

# ================= CONFIG EXCLUDE PORTS =================
read -p "Ports à exclure (Entrée pour défaut: $DEFAULT_EXCLUDE_PORTS) : " EXCLUDE_INPUT
EXCLUDE_PORTS="${EXCLUDE_INPUT:-$DEFAULT_EXCLUDE_PORTS}"

# Validation simple
if [[ ! "$EXCLUDE_PORTS" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
  warn "Format invalide, utilisation des ports par défaut"
  EXCLUDE_PORTS="$DEFAULT_EXCLUDE_PORTS"
fi

# Vérifier que le port principal n’est pas exclu
if echo ",$EXCLUDE_PORTS," | grep -q ",$UDP_PORT,"; then
  warn "Le port principal $UDP_PORT était dans la liste, il sera retiré automatiquement"
  EXCLUDE_PORTS=$(echo "$EXCLUDE_PORTS" | sed "s/\b$UDP_PORT\b//g" | sed 's/,,/,/g' | sed 's/^,//;s/,$//')
fi

# Convertir en JSON
IFS=',' read -ra PORTS <<< "$EXCLUDE_PORTS"
EXCLUDE_JSON="[${PORTS[*]// /,}]"

# ================= CONFIG JSON =================
cat > "$CONFIG_FILE" << EOF
{
  "listen": ":$UDP_PORT",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "exclude_ports": $EXCLUDE_JSON,
  "auth": {
    "mode": "passwords"
  }
}
EOF
chmod 644 "$CONFIG_FILE"
log "Configuration créée : $CONFIG_FILE"
log "Ports exclus : $EXCLUDE_PORTS"

# ================= SYSTEMD =================
log "Création du service systemd UDP Custom..."
cat > "/etc/systemd/system/$SERVICE_UDP" <<EOF
[Unit]
Description=UDP Custom Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$UDP_BIN server -config=$CONFIG_FILE
Restart=always
RestartSec=2
StandardOutput=append:$LOG_RUNTIME
StandardError=append:$LOG_RUNTIME
NoNewPrivileges=true
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable $SERVICE_UDP >/dev/null 2>&1
systemctl restart $SERVICE_UDP || warn "Impossible de démarrer le service automatiquement"

sleep 3

# ================= VERIFICATION =================
if systemctl is-active --quiet $SERVICE_UDP; then
  log "UDP Custom actif sur le port $UDP_PORT"
else
  warn "UDP Custom ne démarre pas. Vérifiez les logs : journalctl -u $SERVICE_UDP -n 50 --no-pager"
fi

# ================= FIN =================
echo
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "${GREEN}${BOLD} INSTALLATION TERMINÉE${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "IP serveur   : $SERVER_IP"
echo -e "Port UDP     : $UDP_PORT"
echo -e "Ports exclus : $EXCLUDE_PORTS"
echo -e "Service      : $SERVICE_UDP"
echo -e "Logs runtime : $LOG_RUNTIME"
echo -e "${CYAN}${BOLD}============================================${RESET}"
