#!/bin/bash
# badvpn_install_only.sh - Installation complète de BadVPN-UDPGW avec message de succès et logs
# Auteur: kinf744 (2025) - Licence MIT

set -euo pipefail

# couleures
RED="e[1;31m"
GREEN="e[1;32m"
CYAN="e[1;36m"
RESET="e[0m"

# Config
BINARY_URL="https://raw.githubusercontent.com/kinf744/binaries/main/badvpn-udpgw"
BIN_PATH="/usr/local/bin/badvpn-udpgw"
PORT="7300"
LOG_DIR="/var/log/badvpn"
LOG_FILE="$LOG_DIR/install.log"
SYSTEMD_UNIT="/etc/systemd/system/badvpn.service"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "+--------------------------------------------+"
echo "|             INSTALLATION RÉUSSI             |"
echo "+--------------------------------------------+"

echo "Démarrage de l'installation BadVPN-UDPGW..."
if [ -x "$BIN_PATH" ]; then
  echo -e "${GREEN}BadVPN déjà installé.${RESET}"
  exit 0
fi

mkdir -p "$(dirname "$BIN_PATH")"
echo "Téléchargement du binaire BadVPN depuis $BINARY_URL..."
if ! wget -q --show-progress -O "$BIN_PATH" "$BINARY_URL"; then
  echo -e "${RED}Échec du téléchargement du binaire BadVPN.${RESET}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] INSTALL_FAILED: download" >> "$LOG_FILE"
  exit 1
fi
chmod +x "$BIN_PATH"

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
EOF

systemctl daemon-reload
systemctl enable badvpn.service
if ! systemctl restart badvpn.service; then
  echo -e "${RED}Erreur lors du démarrage du service BadVPN.${RESET}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] INSTALL_FAILED: service_start" >> "$LOG_FILE"
  exit 1
fi

if command -v ufw >/dev/null 2>&1; then
  ufw allow "$PORT/udp" >/dev/null 2>&1 || true
fi
iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
iptables -C OUTPUT -p udp --sport "$PORT" -j ACCEPT 2>/dev/null || iptables -I OUTPUT -p udp --port "$PORT" -j ACCEPT

if systemctl is-active --quiet badvpn.service; then
  echo -e "${GREEN}BadVPN installé et actif sur le port UDP $PORT.${RESET}"
  echo "+--------------------------------------------+"
  echo "|             INSTALLATION RÉUSSI               |"
  echo "+--------------------------------------------+"
else
  echo -e "${RED}Le service BadVPN n’est pas actif après démarrage.${RESET}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] INSTALL_FAILED: startup" >> "$LOG_FILE"
  exit 1
fi

echo "Installation terminée avec succès."
