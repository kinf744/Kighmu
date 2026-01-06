#!/bin/bash
# ==========================================================
# udp_request.sh
# Installe et configure le serveur UDP Request (udpServer)
# Compatible SocksIP Tunnel - Mode UDP Request
# OS : Ubuntu 20.04+ / Debian 10+
# ==========================================================

set -euo pipefail

UDP_BIN="/usr/bin/udpServer"
SERVICE_FILE="/etc/systemd/system/UDPserver.service"
LOG_FILE="/var/log/udp-request-install.log"

# -------- Log global du script --------
exec > >(tee -a "$LOG_FILE") 2>&1

# -------- Couleurs simples --------
GREEN="e[32m"
RED="e[31m"
YELLOW="e[33m"
BLUE="e[34m"
NC="e[0m"

# -------- Logo / Bannière --------
banner() {
  clear
  echo -e "e[1;36m============================================e[0m"
  echo -e "e[1;32m      UDP Request Server Installere[0m"
  echo -e "e[1;33m      SocksIP Tunnel - udpServere[0m"
  echo -e "e[1;36m============================================e[0m"
  echo
}

log() {
  echo -e "${GREEN}[+]${NC} $*"
}

err() {
  echo -e "${RED}[!]${NC} $*" >&2
}

# -------- Vérification root --------
if [[ "$EUID" -ne 0 ]]; then
  err "Ce script doit être exécuté en root."
  exit 1
fi

banner

# -------- Vérification OS --------
if [[ -e /etc/os-release ]]; then
  . /etc/os-release
else
  err "Impossible de détecter l’OS (/etc/os-release manquant)."
  exit 1
fi

case "$ID" in
  ubuntu|debian)
    :
    ;;
  *)
    err "OS non supporté : $ID. Utilise Ubuntu/Debian."
    exit 1
    ;;
esac

# -------- Mise à jour minimale --------
log "Mise à jour de la liste des paquets..."
apt update -y >/dev/null 2>&1 || true

# -------- Détection IP & interface --------
detect_ip_iface() {
  local ip iface

  ip=$(ip -4 addr show | awk '/inet / && $2 !~ /^127./ {print $2}' | head -n1 | cut -d'/' -f1)
  iface=$(ip -4 addr show | awk '/inet / && $2 !~ /^127./ {print $7}' | head -n1)

  if [[ -z "$ip" || -z "$iface" ]]; then
    err "Impossible de détecter l’IP ou l’interface réseau."
    exit 1
  fi

  SERVER_IP="$ip"
  SERVER_IFACE="$iface"
}

detect_ip_iface
log "IP détectée       : ${SERVER_IP}"
log "Interface détectée: ${SERVER_IFACE}"

# -------- Saisie ports à exclure (optionnel) --------
read -rp "$(echo -e "${YELLOW}[?]${NC} Saisir les ports UDP à exclure (slowdns 53, 5300, WG 51820, OVPN 1194, etc. séparés par espaces) [ENTER pour aucun] : ")" EXCLUDE_PORTS

EXCLUDE_OPT=""
if [[ -n "${EXCLUDE_PORTS:-}" ]]; then
  # Nettoyage, ne garder que des nombres > 0
  PORT_LIST=()
  for p in $EXCLUDE_PORTS; do
    if [[ "$p" =~ ^[0-9]+$ ]] && [[ "$p" -gt 0 ]]; then
      PORT_LIST+=("$p")
    fi
  done

  if [[ "${#PORT_LIST[@]}" -gt 0 ]]; then
    PORT_CSV=$(printf "%s," "${PORT_LIST[@]}")
    PORT_CSV="${PORT_CSV%,}"
    EXCLUDE_OPT=" -exclude=${PORT_CSV}"
    log "Ports exclus UDP : ${PORT_LIST[*]}"
  else
    log "Aucun port valide à exclure, on ignore."
  fi
fi

# -------- Téléchargement binaire udpServer --------
log "Téléchargement du binaire udpServer (UDP Request)..."
if wget -O "${UDP_BIN}" "https://bitbucket.org/iopmx/udprequestserver/downloads/udpServer" >/dev/null 2>&1; then
  chmod +x "${UDP_BIN}"
  log "Binaire udpServer installé dans ${UDP_BIN}"
else
  err "Échec du téléchargement de udpServer."
  exit 1
fi

# -------- Création du service systemd --------
log "Création du service systemd UDPserver..."

cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=UDP Request Server (udpServer) - SocksIP Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=${UDP_BIN} -ip=${SERVER_IP} -net=${SERVER_IFACE}${EXCLUDE_OPT} -mode=system >> /var/log/udp-request-server.log 2>&1
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

log "Service écrit dans ${SERVICE_FILE}"

# -------- Recharge systemd et démarrage --------
log "Recharge de systemd..."
systemctl daemon-reload

log "Démarrage du service UDPserver..."
systemctl start UDPserver || {
  err "Échec de démarrage de UDPserver. Vérifie journalctl -u UDPserver."
  exit 1
}

if systemctl is-active --quiet UDPserver; then
  log "Service UDPserver actif."
  systemctl enable UDPserver >/dev/null 2>&1
else
  err "UDPserver n’est pas actif après le démarrage."
  exit 1
fi

# -------- Infos finales --------
echo -e "
${BLUE}============================================${NC}"
echo -e "${GREEN} Installation UDP Request terminée avec succès${NC}"
echo -e "${BLUE}============================================${NC}"
echo -e "IP serveur      : ${GREEN}${SERVER_IP}${NC}"
echo -e "Interface NET   : ${GREEN}${SERVER_IFACE}${NC}"
if [[ -n "${PORT_LIST:-}" ]]; then
  echo -e "Ports UDP exclus: ${GREEN}${PORT_LIST[*]}${NC}"
else
  echo -e "Ports UDP exclus: ${YELLOW}aucun (tous couverts)${NC}"
fi
echo -e "Service         : ${GREEN}UDPserver${NC}"
echo -e "Log installation: ${GREEN}${LOG_FILE}${NC}"
echo -e "Log serveur     : ${GREEN}/var/log/udp-request-server.log${NC}"
echo -e "Commande état   : systemctl status UDPserver"
echo -e "Journal         : journalctl -u UDPserver -f"
echo -e "${BLUE}============================================${NC}
"
