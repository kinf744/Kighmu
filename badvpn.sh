#!/bin/bash
# badvpn.sh - Installation et gestion du service BadVPN-UDPGW (robuste)
# Auteur: kinf744 (2025) - Licence MIT

set -euo pipefail

# Couleurs
RED="e[1;31m"
GREEN="e[1;32m"
YELLOW="e[1;33m"
CYAN="e[1;36m"
RESET="e[0m"

# Variables configurables
BINARY_URL="https://raw.githubusercontent.com/kinf744/binaries/main/badvpn-udpgw"
BIN_PATH="/usr/local/bin/badvpn-udpgw"
PORT="7300"
SYSTEMD_UNIT="/etc/systemd/system/badvpn.service"

install_badvpn() {
  echo -e "${CYAN}>>> Installation BadVPN-UDPGW...${RESET}"

  if [ -x "$BIN_PATH" ]; then
    echo -e "${GREEN}BadVPN déjà installé.${RESET}"
    return 0
  fi

  mkdir -p "$(dirname "$BIN_PATH")"
  if ! wget -q --show-progress -O "$BIN_PATH" "$BINARY_URL"; then
    echo -e "${RED}Échec du téléchargement du binaire BadVPN. Vérifiez l’accès réseau et l’URL.${RESET}" >&2
    return 1
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

  # Applique le fichier systemd et démarre le service
  systemctl daemon-reload
  systemctl enable badvpn.service
  if ! systemctl restart badvpn.service; then
    echo -e "${RED}Erreur lors du démarrage du service BadVPN. Vérifiez le statut.${RESET}"
    return 1
  fi

  # Pare-feu
  if command -v ufw >/dev/null 2>&1; then
    ufw allow "$PORT/udp" >/dev/null 2>&1 || true
  fi
  iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
  iptables -C OUTPUT -p udp --sport "$PORT" -j ACCEPT 2>/dev/null || iptables -I OUTPUT -p udp --sport "$PORT" -j ACCEPT

  # Vérification rapide
  if systemctl is-active --quiet badvpn.service; then
    echo -e "${GREEN}BadVPN installé et actif sur le port UDP $PORT.${RESET}"
  else
    echo -e "${RED}Le service BadVPN n’est pas actif après démarrage.${RESET}"
    return 1
  fi
}

uninstall_badvpn() {
  echo -e "${YELLOW}>>> Désinstallation BadVPN...${RESET}"
  systemctl stop badvpn.service 2>/dev/null || true
  systemctl disable badvpn.service 2>/dev/null || true
  rm -f "$SYSTEMD_UNIT"
  systemctl daemon-reload

  rm -f "$BIN_PATH"

  if command -v ufw >/dev/null 2>&1; then
    ufw delete allow "$PORT/udp" >/dev/null 2>&1 || true
  fi
  iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null || true
  iptables -D OUTPUT -p udp --sport "$PORT" -j ACCEPT 2>/dev/null || true

  echo -e "${GREEN}[OK] BadVPN désinstallé.${RESET}"
}

status_badvpn() {
  if systemctl is-active --quiet badvpn.service; then
    echo -e "${GREEN}BadVPN est actif (port UDP $PORT).${RESET}"
  else
    echo -e "${RED}BadVPN n'est PAS actif.${RESET}"
  fi
}

case "${1:-}" in
  install|install_badvpn)
    install_badvpn
    ;;
  uninstall|uninstall_badvpn)
    uninstall_badvpn
    ;;
  restart|reload|start)
    if [[ -x "$BIN_PATH" ]]; then
      systemctl daemon-reload
      systemctl restart badvpn.service
      systemctl is-active --quiet badvpn.service && echo "BadVPN démarré" || echo "Échec du démarrage"
    else
      echo "Binaire BadVPN introuvable. Veuillez installer d'abord." >&2
      exit 1
    fi
    ;;
  status|check|status_badvpn)
    status_badvpn
    ;;
  help|h|*)
    echo "Usage: $0 {install|uninstall|restart|status}"
    ;;
esac
