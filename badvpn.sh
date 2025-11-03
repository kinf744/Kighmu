#!/bin/bash
# badvpn.sh - Installation complète de BadVPN-UDPGW avec iptables persistantes
# Auteur: kinf744 (2025) - Licence MIT

set -euo pipefail

# Couleurs
RED="\e[1;31m"
GREEN="\e[1;32m"
CYAN="\e[1;36m"
RESET="\e[0m"

# Vérification privilèges root
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Ce script doit être exécuté en tant que root.${RESET}"
  exit 1
fi

# Config
BIN_PATH="/root/Kighmu/badvpn-udpgw"
BINARY_URL="https://raw.githubusercontent.com/kinf744/binaries/main/badvpn-udpgw"
PORT="7300"
LOG_DIR="/var/log/badvpn"
LOG_FILE="$LOG_DIR/install.log"
SYSTEMD_UNIT="/etc/systemd/system/badvpn.service"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "+--------------------------------------------+"
echo "|             DÉBUT D'INSTALLATION           |"
echo "+--------------------------------------------+"

# Vérifie si wget ou curl est disponible
if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
  echo -e "${RED}Erreur : wget ou curl doit être installé.${RESET}"
  exit 1
fi

# Télécharger ou utiliser le binaire existant
if [ ! -x "$BIN_PATH" ]; then
  mkdir -p "$(dirname "$BIN_PATH")"
  echo "Téléchargement du binaire BadVPN..."
  if command -v wget >/dev/null 2>&1; then
    wget -q --show-progress -O "$BIN_PATH" "$BINARY_URL" || { echo -e "${RED}Échec téléchargement.${RESET}"; exit 1; }
  else
    curl -L --progress-bar -o "$BIN_PATH" "$BINARY_URL" || { echo -e "${RED}Échec téléchargement.${RESET}"; exit 1; }
  fi
  chmod +x "$BIN_PATH"
else
  echo -e "${GREEN}BadVPN déjà installé sur $BIN_PATH.${RESET}"
fi

# Vérifie si le port UDP est libre
if ss -lun | grep -q ":$PORT "; then
  echo -e "${RED}Le port UDP $PORT est déjà utilisé. Abandon.${RESET}"
  exit 1
fi

# Création du service systemd
cat > "$SYSTEMD_UNIT" <<EOF
[Unit]
Description=BadVPN UDP Gateway
After=network.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BIN_PATH --listen-addr 127.0.0.1:$PORT --max-clients 1000 --max-connections-for-client 10
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=badvpn
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable badvpn.service
if ! systemctl restart badvpn.service; then
  echo -e "${RED}Erreur lors du démarrage du service.${RESET}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] INSTALL_FAILED: service_start" >> "$LOG_FILE"
  exit 1
fi

# Ouverture du port UDP via iptables persistantes
iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
iptables -C OUTPUT -p udp --sport "$PORT" -j ACCEPT 2>/dev/null || iptables -I OUTPUT -p udp --sport "$PORT" -j ACCEPT
iptables-save | tee /etc/iptables/rules.v4
systemctl restart netfilter-persistent || true

# Vérification finale
if systemctl is-active --quiet badvpn.service; then
  echo -e "${GREEN}BadVPN installé et actif sur le port UDP $PORT.${RESET}"
  echo "+--------------------------------------------+"
  echo "|           INSTALLATION RÉUSSIE             |"
  echo "+--------------------------------------------+"
else
  echo -e "${RED}Le service BadVPN n’est pas actif après démarrage.${RESET}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] INSTALL_FAILED: startup" >> "$LOG_FILE"
  exit 1
fi

# Résumé final
echo -e "\n${CYAN}Résumé d'installation :${RESET}"
echo "  ➤ Port UDP    : $PORT"
echo "  ➤ Service     : badvpn.service"
echo "  ➤ Logs        : $LOG_FILE"

echo -e "\nInstallation terminée avec succès."
read -r -p "Appuyez sur Entrée pour quitter..."
