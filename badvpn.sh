#!/bin/bash
# badvpn.sh - Installation et gestion du service BadVPN-UDPGW (adapté Kighmu)
# by kinf744 (2025) - Licence MIT

set -o errexit
set -o nounset
set -o pipefail

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RESET="\033[0m"

BINARY_URL="https://raw.githubusercontent.com/kinf744/binaries/main/badvpn-udpgw"
BIN_PATH="/usr/local/bin/badvpn-udpgw"
PORT="7300"
SYSTEMD_UNIT="/etc/systemd/system/badvpn.service"

install_badvpn() {
    echo -e "${CYAN}Installation BadVPN-UDPGW...${RESET}"
    if [[ -x "$BIN_PATH" ]]; then
        echo -e "${YELLOW}BadVPN déjà présent.${RESET}"
        return 0
    fi

    wget -q --show-progress -O "$BIN_PATH" "$BINARY_URL" || {
        echo -e "${RED}Téléchargement du binaire BadVPN échoué !${RESET}"
        return 1
    }
    chmod +x "$BIN_PATH"
    echo -e "${GREEN}Binaire placé : $BIN_PATH${RESET}"

    cat > "$SYSTEMD_UNIT" <<EOF
[Unit]
Description=BadVPN UDP Gateway
After=network.target

[Service]
Type=simple
ExecStart=$BIN_PATH --listen-addr 127.0.0.1:$PORT --max-clients 1000 --max-connections-for-client 10
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable badvpn.service
    systemctl restart badvpn.service

    if command -v ufw &>/dev/null; then
        ufw allow "$PORT/udp" || true
    fi
    iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT || true
    iptables -I OUTPUT -p udp --sport "$PORT" -j ACCEPT || true

    echo -e "${GREEN}BadVPN installé et démarré sur port UDP $PORT.${RESET}"
}

uninstall_badvpn() {
    echo -e "${YELLOW}Arrêt et suppression de BadVPN-UDPGW...${RESET}"

    systemctl stop badvpn.service || true
    systemctl disable badvpn.service || true
    rm -f "$SYSTEMD_UNIT"
    systemctl daemon-reload

    rm -f "$BIN_PATH"

    if command -v ufw &>/dev/null; then
        ufw delete allow "$PORT/udp" || true
    fi
    iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT || true
    iptables -D OUTPUT -p udp --sport "$PORT" -j ACCEPT || true

    echo -e "${GREEN}BadVPN supprimé proprement.${RESET}"
}

status_badvpn() {
    if systemctl is-active --quiet badvpn.service; then
        echo -e "${GREEN}BadVPN est actif (port UDP $PORT).${RESET}"
    else
        echo -e "${RED}BadVPN n'est PAS actif.${RESET}"
    fi
}

