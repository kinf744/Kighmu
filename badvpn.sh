#!/bin/bash
# badvpn.sh - Installation et gestion du service BadVPN-UDPGW (adapté Kighmu)
# Auteur: kinf744 (2025) - Licence MIT

set -euo pipefail

# Couleurs
RED="\u001B[1;31m"
GREEN="\u001B[1;32m"
YELLOW="\u001B[1;33m"
CYAN="\u001B[1;36m"
RESET="\u001B[0m"

# Variables configurables
BINARY_URL="https://raw.githubusercontent.com/kinf744/binaries/main/badvpn-udpgw"
BIN_PATH="/usr/local/bin/badvpn-udpgw"
PORT="7300"
SYSTEMD_UNIT="/etc/systemd/system/badvpn.service"

# Fonctions utilitaires
log() {
  echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')]${RESET} $*"
}
die() {
  echo -e "${RED}$*${RESET}" >&2
  exit 1
}

install_badvpn() {
  log "Installation de BadVPN-UDPGW..."
  if [[ -x "$BIN_PATH" ]]; then
    echo -e "${YELLOW}BadVPN déjà présent.${RESET}"
    return 0
  fi

  mkdir -p "$(dirname "$BIN_PATH")"
  log "Téléchargement du binaire BadVPN..."
  if ! wget -q --show-progress -O "$BIN_PATH" "$BINARY_URL"; then
    die "Échec du téléchargement du binaire BadVPN."
  fi
  chmod +x "$BIN_PATH"
  log "Binaire placé : $BIN_PATH"

  # Fichier systemd
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
Environment=MSGLEVEL=1
StandardOutput=journal
StandardError=journal
SyslogIdentifier=badvpn
LimitNOFILE=1048576
Nice=-5
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=99

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable badvpn.service
  systemctl restart badvpn.service

  if command -v ufw >/dev/null 2>&1; then
    ufw allow "$PORT/udp" || true
  fi
  iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT || true
  iptables -I OUTPUT -p udp --sport "$PORT" -j ACCEPT || true

  log "BadVPN installé et démarré sur port UDP $PORT."
}

uninstall_badvpn() {
  log "Arrêt et suppression de BadVPN-UDPGW..."
  systemctl stop badvpn.service || true
  systemctl disable badvpn.service || true
  rm -f "$SYSTEMD_UNIT"
  systemctl daemon-reload

  rm -f "$BIN_PATH"

  if command -v ufw >/dev/null 2>&1; then
    ufw delete allow "$PORT/udp" || true
  fi
  iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT || true
  iptables -D OUTPUT -p udp --sport "$PORT" -j ACCEPT || true

  log "BadVPN supprimé proprement."
}

status_badvpn() {
  if systemctl is-active --quiet badvpn.service; then
    echo -e "${GREEN}BadVPN est actif (port UDP $PORT).${RESET}"
  else
    echo -e "${RED}BadVPN n'est PAS actif.${RESET}"
  fi
}

# Exécution non interactive via arguments (préférence d’orchestrateur)
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
