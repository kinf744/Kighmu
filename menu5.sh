#!/bin/bash
# menu5.sh - Panneau de contrôle installation/désinstallation amélioré

# Définition des couleurs
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

afficher_modes_ports() {
    local any_active=0

    if systemctl is-active --quiet ssh || pgrep -x sshd >/dev/null 2>&1; then any_active=1; fi
    if systemctl is-active --quiet dropbear || pgrep -x dropbear >/dev/null 2>&1; then any_active=1; fi
    if systemctl is-active --quiet slowdns.service || pgrep -f "sldns-server" >/dev/null 2>&1 || screen -list | grep -q slowdns_session; then any_active=1; fi
    if systemctl is-active --quiet udp_custom.service || pgrep -f udp-custom-linux-amd64 >/dev/null 2>&1 || screen -list | grep -q udp_custom; then any_active=1; fi
    if systemctl is-active --quiet socks_python.service || pgrep -f KIGHMUPROXY.py >/dev/null 2>&1 || screen -list | grep -q socks_python; then any_active=1; fi
    if systemctl is-active --quiet socks_python_ws.service || pgrep -f ws2_proxy.py >/dev/null 2>&1; then any_active=1; fi
    if systemctl is-active --quiet stunnel4.service || pgrep -f stunnel >/dev/null 2>&1; then any_active=1; fi
    if systemctl is-active --quiet hysteria.service || pgrep -f hysteria >/dev/null 2>&1; then any_active=1; fi
    if systemctl is-active --quiet ws_wss_server.service; then any_active=1; fi

    if [[ $any_active -eq 0 ]]; then
        return
    fi

    echo -e "${CYAN}Modes actifs et ports utilisés:${RESET}"

    if systemctl is-active --quiet ssh || pgrep -x sshd >/dev/null 2>&1; then
        echo -e "  - OpenSSH: ${GREEN}port 22${RESET}"
    fi
    if systemctl is-active --quiet dropbear || pgrep -x dropbear >/dev/null 2>&1; then
        DROPBEAR_PORT=$(grep -oP '(?<=-p )\d+' /etc/default/dropbear 2>/dev/null || echo "22")
        echo -e "  - Dropbear: ${GREEN}port $DROPBEAR_PORT${RESET}"
    fi
    if systemctl is-active --quiet slowdns.service || pgrep -f "sldns-server" >/dev/null 2>&1 || screen -list | grep -q slowdns_session; then
        echo -e "  - SlowDNS: ${GREEN}ports UDP 5300${RESET}"
    fi
    if systemctl is-active --quiet udp_custom.service || pgrep -f udp-custom-linux-amd64 >/dev/null 2>&1 || screen -list | grep -q udp_custom; then
        echo -e "  - UDP Custom: ${GREEN}port UDP 54000${RESET}"
    fi
    if systemctl is-active --quiet socks_python.service || pgrep -f KIGHMUPROXY.py >/dev/null 2>&1 || screen -list | grep -q socks_python; then
        echo -e "  - SOCKS Python: ${GREEN}ports TCP 8080${RESET}"
    fi
    if systemctl is-active --quiet socks_python_ws.service || pgrep -f ws2_proxy.py >/dev/null 2>&1; then
        echo -e "  - Proxy WS: ${GREEN}port TCP 80${RESET}"
    fi
    if systemctl is-active --quiet stunnel4.service || pgrep -f stunnel >/dev/null 2>&1; then
        echo -e "  - Stunnel SSL/TLS: ${GREEN}port TCP 444${RESET}"
    fi
    if systemctl is-active --quiet hysteria.service || pgrep -f hysteria >/dev/null 2>&1; then
        echo -e "  - Hysteria UDP : ${GREEN}port UDP 22000${RESET}"
    fi
    if systemctl is-active --quiet ws_wss_server.service; then
        echo -e "  - WS/WSS Tunnel: ${GREEN}WS port 8880 | WSS port 443${RESET}"
    fi
}

# ========================================================================
# Fonctions d'installation / désinstallation pour chaque mode
# ========================================================================

install_slowdns() { bash "$HOME/Kighmu/slowdns.sh"; }
uninstall_slowdns() { systemctl stop slowdns.service; systemctl disable slowdns.service; rm -f /etc/systemd/system/slowdns.service; }

install_openssh() { apt install -y openssh-server; systemctl enable ssh; systemctl start ssh; }
uninstall_openssh() { apt remove -y openssh-server; }

install_dropbear() { apt install -y dropbear; systemctl enable dropbear; systemctl start dropbear; }
uninstall_dropbear() { apt remove -y dropbear; }

install_udp_custom() { bash "$HOME/Kighmu/udp_custom.sh"; }
uninstall_udp_custom() { systemctl stop udp_custom.service; systemctl disable udp_custom.service; rm -f /etc/systemd/system/udp_custom.service; }

install_socks_python() { bash "$HOME/Kighmu/socks_python.sh"; }
uninstall_socks_python() { systemctl stop socks_python.service; systemctl disable socks_python.service; rm -f /etc/systemd/system/socks_python.service; }

install_proxy_ws() { bash "$HOME/Kighmu/sockspy.sh"; }
uninstall_proxy_ws() { systemctl stop socks_python_ws.service; systemctl disable socks_python_ws.service; rm -f /etc/systemd/system/socks_python_ws.service; }

install_ssl_tls() { bash "$HOME/Kighmu/ssl.sh"; }
uninstall_ssl_tls() { systemctl stop stunnel4; systemctl disable stunnel4; rm -f /etc/stunnel/stunnel.conf; }

install_badvpn() { bash "$HOME/Kighmu/badvpn.sh"; }
uninstall_badvpn() { pkill -f badvpn; }

install_hysteria() { bash "$HOME/Kighmu/hysteria.sh"; }
uninstall_hysteria() { systemctl stop hysteria.service; systemctl disable hysteria.service; rm -f /etc/systemd/system/hysteria.service; }

# ========================================================================
# 🔥 Nouveau mode : TUNNEL WS/WSS SSH
# ========================================================================
install_ws_wss() {
    echo ">>> Installation du tunnel WS/WSS SSH..."
    if [ -f /usr/local/bin/ws_wssr.sh ]; then
        bash /usr/local/bin/ws_wssr.sh
    elif [ -f "$HOME/Kighmu/ws_wssr.sh" ]; then
        bash "$HOME/Kighmu/ws_wssr.sh"
    else
        echo "❌ Script ws_wssr.sh introuvable."
        return 1
    fi
    echo -e "${GREEN}[OK] Tunnel WS/WSS installé et lancé.${RESET}"
}

uninstall_ws_wss() {
    echo ">>> Désinstallation complète du tunnel WS/WSS..."
    systemctl stop ws_wss_server.service 2>/dev/null || true
    systemctl disable ws_wss_server.service 2>/dev/null || true
    rm -f /etc/systemd/system/ws_wss_server.service
    rm -f /usr/local/bin/ws_wss_server.py /usr/local/bin/ws_wssr.sh
    systemctl daemon-reload

    echo "Suppression des certificats Let's Encrypt..."
    DOMAIN_FILE="$HOME/.kighmu_info"
    if [[ -f "$DOMAIN_FILE" ]]; then
        DOMAIN=$(grep -m1 "DOMAIN=" "$DOMAIN_FILE" | cut -d'=' -f2)
        if [[ -n "$DOMAIN" ]]; then
            certbot delete --cert-name "$DOMAIN" -n || true
            rm -rf /etc/letsencrypt/live/$DOMAIN /etc/letsencrypt/archive/$DOMAIN
        fi
    fi

    echo "Suppression des règles firewall..."
    ufw delete allow 8880/tcp 2>/dev/null || true
    ufw delete allow 443/tcp 2>/dev/null || true

    echo -e "${GREEN}[OK] Tunnel WS/WSS désinstallé.${RESET}"
}

# ========================================================================
# Interface utilisateur
# ========================================================================

manage_mode() {
    MODE_NAME=$1
    INSTALL_FUNC=$2
    UNINSTALL_FUNC=$3

    while true; do
        clear
        echo -e "${CYAN}+======================================================+${RESET}"
        echo -e "|             🚀 Gestion du mode : $MODE_NAME 🚀          |"
        echo -e "${CYAN}+======================================================+${RESET}"
        echo -e "${GREEN}${BOLD}[1]${RESET} ${YELLOW}Installer${RESET}"
        echo -e "${GREEN}${BOLD}[2]${RESET} ${YELLOW}Désinstaller${RESET}"
        echo -e "${GREEN}${BOLD}[0]${RESET} ${YELLOW}Retour${RESET}"
        echo -ne "${BOLD}${YELLOW}👉 Choisissez une action : ${RESET}"
        read action
        case $action in
            1) $INSTALL_FUNC; read -p "Appuyez sur Entrée pour continuer..." ;;
            2) $UNINSTALL_FUNC; read -p "Appuyez sur Entrée pour continuer..." ;;
            0) break ;;
            *) echo -e "${RED}❌ Mauvais choix.${RESET}"; sleep 1 ;;
        esac
    done
}

while true; do
    clear
    HOST_IP=$(curl -s https://api.ipify.org)
    UPTIME=$(uptime -p)
    echo -e "${CYAN}+=====================================================+${RESET}"
    echo -e "|           🚀 PANNEAU DE CONTROLE DES MODES 🚀       |"
    echo -e "${CYAN}+=====================================================+${RESET}"
    echo -e "${CYAN} IP: ${GREEN}$HOST_IP${RESET} | ${CYAN}Up: ${GREEN}$UPTIME${RESET}"

    afficher_modes_ports

    echo -e "${CYAN}+======================================================+${RESET}"
    echo -e "${GREEN}${BOLD}[01]${RESET} ${YELLOW}OpenSSH${RESET}"
    echo -e "${GREEN}${BOLD}[02]${RESET} ${YELLOW}Dropbear${RESET}"
    echo -e "${GREEN}${BOLD}[03]${RESET} ${YELLOW}SlowDNS${RESET}"
    echo -e "${GREEN}${BOLD}[04]${RESET} ${YELLOW}UDP Custom${RESET}"
    echo -e "${GREEN}${BOLD}[05]${RESET} ${YELLOW}SOCKS/Python${RESET}"
    echo -e "${GREEN}${BOLD}[06]${RESET} ${YELLOW}SSL/TLS${RESET}"
    echo -e "${GREEN}${BOLD}[07]${RESET} ${YELLOW}BadVPN${RESET}"
    echo -e "${GREEN}${BOLD}[08]${RESET} ${YELLOW}Proxy WS${RESET}"
    echo -e "${GREEN}${BOLD}[09]${RESET} ${YELLOW}Hysteria${RESET}"
    echo -e "${GREEN}${BOLD}[10]${RESET} ${YELLOW}Tunnel WS/WSS SSH${RESET}"
    echo -e "${GREEN}${BOLD}[00]${RESET} ${YELLOW}Quitter${RESET}"
    echo -ne "${BOLD}${YELLOW}👉 Choisissez un mode : ${RESET}"
    read choix
    case $choix in
        1) manage_mode "OpenSSH" install_openssh uninstall_openssh ;;
        2) manage_mode "Dropbear" install_dropbear uninstall_dropbear ;;
        3) manage_mode "SlowDNS" install_slowdns uninstall_slowdns ;;
        4) manage_mode "UDP Custom" install_udp_custom uninstall_udp_custom ;;
        5) manage_mode "SOCKS/Python" install_socks_python uninstall_socks_python ;;
        6) manage_mode "SSL/TLS" install_ssl_tls uninstall_ssl_tls ;;
        7) manage_mode "BadVPN" install_badvpn uninstall_badvpn ;;
        8) manage_mode "Proxy WS" install_proxy_ws uninstall_proxy_ws ;;
        9) manage_mode "Hysteria" install_hysteria uninstall_hysteria ;;
        10) manage_mode "Tunnel WS/WSS SSH" install_ws_wss uninstall_ws_wss ;;
        0) echo -e "${RED}🚪 Sortie du panneau de contrôle.${RESET}" ; exit 0 ;;
        *) echo -e "${RED}❌ Option invalide.${RESET}" ;;
    esac
done
