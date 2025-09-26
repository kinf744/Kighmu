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

clear

afficher_modes_ports() {
    local any_active=0

    if systemctl is-active --quiet ssh || pgrep -x sshd >/dev/null 2>&1; then
        any_active=1
    fi

    if systemctl is-active --quiet dropbear || pgrep -x dropbear >/dev/null 2>&1; then
        any_active=1
    fi

    if systemctl is-active --quiet slowdns.service || pgrep -f "sldns-server" >/dev/null 2>&1 || screen -list | grep -q slowdns_session; then
        any_active=1
    fi

    if systemctl is-active --quiet udp_custom.service || pgrep -f udp-custom-linux-amd64 >/dev/null 2>&1 || screen -list | grep -q udp_custom; then
        any_active=1
    fi

    if systemctl is-active --quiet socks_python.service || pgrep -f KIGHMUPROXY.py >/dev/null 2>&1 || screen -list | grep -q socks_python; then
        any_active=1
    fi

    if systemctl is-active --quiet socks_python_ws.service || pgrep -f ws2_proxy.py >/dev/null 2>&1; then
        any_active=1
    fi

    if systemctl is-active --quiet stunnel4.service || pgrep -f stunnel >/dev/null 2>&1; then
        any_active=1
    fi

    if systemctl is-active --quiet hysteria.service || pgrep -f hysteria >/dev/null 2>&1; then
        any_active=1
    fi

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
        echo -e "  - SlowDNS: ${GREEN}ports UDP 5300, 5400${RESET}"
    fi

    if systemctl is-active --quiet udp_custom.service || pgrep -f udp-custom-linux-amd64 >/dev/null 2>&1 || screen -list | grep -q udp_custom; then
        echo -e "  - UDP Custom: ${GREEN}port UDP 54000${RESET}"
    fi

    if systemctl is-active --quiet socks_python.service || pgrep -f KIGHMUPROXY.py >/dev/null 2>&1 || screen -list | grep -q socks_python; then
        echo -e "  - SOCKS Python: ${GREEN}ports TCP 8080, 9090${RESET}"
    fi

    if systemctl is-active --quiet socks_python_ws.service || pgrep -f ws2_proxy.py >/dev/null 2>&1; then
        if [ -f /etc/systemd/system/socks_python_ws.service ]; then
            PROXY_WS_PORT=$(grep "ExecStart=" /etc/systemd/system/socks_python_ws.service | awk '{print $NF}')
        else
            PROXY_WS_PORT=$(sudo lsof -Pan -p $(pgrep -f ws2_proxy.py | head -n1) -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $9}' | cut -d: -f2)
        fi
        PROXY_WS_PORT=${PROXY_WS_PORT:-80}
        echo -e "  - proxy ws: ${GREEN}port TCP $PROXY_WS_PORT${RESET}"
    fi

    if systemctl is-active --quiet stunnel4.service || pgrep -f stunnel >/dev/null 2>&1; then
        echo -e "  - Stunnel SSL/TLS: ${GREEN}port TCP 444${RESET}"
    fi

    if systemctl is-active --quiet hysteria.service || pgrep -f hysteria >/dev/null 2>&1; then
        echo -e "  - Hysteria UDP : ${GREEN}port UDP 22000${RESET}"
    fi
}

HOST_IP=$(curl -s https://api.ipify.org)
UPTIME=$(uptime -p)
echo -e "${CYAN}+=====================================================+${RESET}"
echo -e "|           🚀 PANNEAU DE CONTROLE DES MODES 🚀       |"
echo -e "${CYAN}+=====================================================+${RESET}"
echo -e "${CYAN} IP: ${GREEN}$HOST_IP${RESET} | ${CYAN}Up: ${GREEN}$UPTIME${RESET}"

afficher_modes_ports

# Fonctions d'installation/désinstallation des tunnels et services

install_slowdns() {
    echo ">>> Nettoyage avant installation SlowDNS..."
    pkill -f slowdns || true
    rm -rf $HOME/.slowdns
    rm -f /usr/local/bin/slowdns
    systemctl stop slowdns.service 2>/dev/null || true
    systemctl disable slowdns.service 2>/dev/null || true
    rm -f /etc/systemd/system/slowdns.service
    systemctl daemon-reload
    ufw delete allow 5300/udp 2>/dev/null || true
    echo ">>> Installation/configuration SlowDNS..."
    bash "$HOME/Kighmu/slowdns.sh" || echo "SlowDNS : script introuvable."
    ufw allow 5300/udp
}

uninstall_slowdns() {
    echo ">>> Désinstallation complète SlowDNS..."
    pkill -f slowdns || true
    rm -rf $HOME/.slowdns
    rm -f /usr/local/bin/slowdns
    systemctl stop slowdns.service 2>/dev/null || true
    systemctl disable slowdns.service 2>/dev/null || true
    rm -f /etc/systemd/system/slowdns.service
    systemctl daemon-reload
    ufw delete allow 5300/udp 2>/dev/null || true
    echo -e "${GREEN}[OK] SlowDNS désinstallé.${RESET}"
}

install_openssh() {
    echo ">>> Installation d'OpenSSH..."
    apt-get install -y openssh-server
    systemctl enable ssh
    systemctl start ssh
    echo -e "${GREEN}[OK] OpenSSH installé.${RESET}"
}

uninstall_openssh() {
    echo ">>> Désinstallation d'OpenSSH..."
    apt-get remove -y openssh-server
    systemctl disable ssh
    echo -e "${GREEN}[OK] OpenSSH supprimé.${RESET}"
}

install_dropbear() {
    echo ">>> Installation de Dropbear..."
    apt-get install -y dropbear
    systemctl enable dropbear
    systemctl start dropbear
    echo -e "${GREEN}[OK] Dropbear installé.${RESET}"
}

uninstall_dropbear() {
    echo ">>> Désinstallation de Dropbear..."
    apt-get remove -y dropbear
    systemctl disable dropbear
    echo -e "${GREEN}[OK] Dropbear supprimé.${RESET}"
}

install_udp_custom() {
    echo ">>> Installation UDP Custom via script..."
    bash "$HOME/Kighmu/udp_custom.sh" || echo "Script introuvable."
}

uninstall_udp_custom() {
    echo ">>> Désinstallation UDP Custom..."
    pids=$(pgrep -f udp-custom-linux-amd64)
    if [ ! -z "$pids" ]; then
        kill -15 $pids
        sleep 2
        pids=$(pgrep -f udp-custom-linux-amd64)
        if [ ! -z "$pids" ]; then
            kill -9 $pids
        fi
    fi
    if systemctl list-units --full -all | grep -Fq 'udp_custom.service'; then
        systemctl stop udp_custom.service
        systemctl disable udp_custom.service
        rm -f /etc/systemd/system/udp_custom.service
        systemctl daemon-reload
    fi
    rm -rf /root/udp-custom
    ufw delete allow 54000/udp 2>/dev/null || true
    iptables -D INPUT -p udp --dport 54000 -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -p udp --sport 54000 -j ACCEPT 2>/dev/null || true
    echo -e "${GREEN}[OK] UDP Custom désinstallé.${RESET}"
}

install_socks_python() {
    echo ">>> Installation SOCKS Python via script..."
    bash "$HOME/Kighmu/socks_python.sh" || echo "Script introuvable."
}

uninstall_socks_python() {
    echo ">>> Désinstallation SOCKS Python..."
    pids=$(pgrep -f KIGHMUPROXY.py)
    if [ ! -z "$pids" ]; then
        kill -15 $pids
        sleep 2
        pids=$(pgrep -f KIGHMUPROXY.py)
        if [ ! -z "$pids" ]; then
            kill -9 $pids
        fi
    fi
    if systemctl list-units --full -all | grep -Fq 'socks_python.service'; then
        systemctl stop socks_python.service
        systemctl disable socks_python.service
        rm -f /etc/systemd/system/socks_python.service
        systemctl daemon-reload
    fi
    rm -f /usr/local/bin/KIGHMUPROXY.py
    ufw delete allow 8080/tcp 2>/dev/null || true
    ufw delete allow 9090/tcp 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -p tcp --sport 8080 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 9090 -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -p tcp --sport 9090 -j ACCEPT 2>/dev/null || true
    echo -e "${GREEN}[OK] SOCKS Python désinstallé.${RESET}"
}

install_proxy_ws() {
    echo ">>> Installation proxy ws via script sockspy.sh..."
    bash "$HOME/Kighmu/sockspy.sh" || echo "Script sockspy introuvable."
}

uninstall_proxy_ws() {
    echo ">>> Désinstallation proxy ws..."

    pids=$(pgrep -f ws2_proxy.py)
    if [ ! -z "$pids" ]; then
        kill -15 $pids
        sleep 2
        pids=$(pgrep -f ws2_proxy.py)
        if [ ! -z "$pids" ]; then
            kill -9 $pids
        fi
    fi

    if systemctl list-units --full -all | grep -Fq 'socks_python_ws.service'; then
        systemctl stop socks_python_ws.service
        systemctl disable socks_python_ws.service
        rm -f /etc/systemd/system/socks_python_ws.service
        systemctl daemon-reload
    fi

    rm -f /usr/local/bin/ws2_proxy.py

    ufw delete allow 80/tcp 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -p tcp --sport 80 -j ACCEPT 2>/dev/null || true

    echo -e "${GREEN}[OK] proxy ws désinstallé.${RESET}"
}

install_ssl_tls() {
    echo ">>> Lancement du script d'installation SSL/TLS externe..."
    bash "$HOME/Kighmu/ssl.sh" || echo "Script SSL/TLS introuvable ou erreur."
}

uninstall_ssl_tls() {
    echo ">>> Désinstallation complète de Stunnel SSL/TLS..."

    systemctl stop stunnel4 2>/dev/null || true
    systemctl disable stunnel4 2>/dev/null || true

    rm -f /etc/stunnel/stunnel.key /etc/stunnel/stunnel.crt /etc/stunnel/stunnel.pem
    rm -f /etc/stunnel/stunnel.conf
    rm -rf /etc/systemd/system/stunnel4.service.d

    systemctl daemon-reload

    echo "Suppression de la règle firewall UFW (port 444)..."
    if command -v ufw &> /dev/null; then
        ufw delete allow 444/tcp 2>/dev/null || true
        ufw reload
    else
        echo "UFW non détecté, vérifier firewall manuellement."
    fi

    echo -e "${GREEN}[OK] Stunnel SSL/TLS désinstallé proprement.${RESET}"
}

install_badvpn() {
    echo ">>> Installation BadVPN (à compléter)"
}

uninstall_badvpn() {
    echo ">>> Désinstallation BadVPN (à compléter)"
}

# Variables pour Hysteria
HYST_PORT=22000

install_hysteria() {
    echo ">>> Installation Hysteria..."
    bash "$HOME/Kighmu/hysteria.sh" || echo "Script hysteria introuvable ou erreur."
    ufw allow ${HYST_PORT}/udp 2>/dev/null || true
    echo -e "${GREEN}[OK] Hysteria installé.${RESET}"
}

uninstall_hysteria() {
    echo ">>> Désinstallation Hysteria..."
    if systemctl list-units --full -all | grep -Fq 'hysteria.service'; then
        systemctl stop hysteria.service
        systemctl disable hysteria.service
        rm -f /etc/systemd/system/hysteria.service
        systemctl daemon-reload
    fi
    pkill -f hysteria || true
    rm -f /usr/local/bin/hysteria
    ufw delete allow ${HYST_PORT}/udp 2>/dev/null || true
    echo -e "${GREEN}[OK] Hysteria désinstallé.${RESET}"
}

manage_mode() {
    MODE_NAME=$1
    INSTALL_FUNC=$2
    UNINSTALL_FUNC=$3

    while true; do
        echo ""
        echo -e "${CYAN}+======================================================+${RESET}"
        echo -e "|             🚀 Gestion du mode : $MODE_NAME 🚀          |"
        echo -e "${CYAN}+======================================================+${RESET}"
        echo -e "${GREEN}${BOLD}[1]${RESET} ${YELLOW}Installer${RESET}"
        echo -e "${GREEN}${BOLD}[2]${RESET} ${YELLOW}Désinstaller${RESET}"
        echo -e "${GREEN}${BOLD}[0]${RESET} ${YELLOW}Retour${RESET}"
        echo -e "${CYAN}+------------------------------------------------------+${RESET}"
        echo -ne "${BOLD}${YELLOW}👉 Choisissez une action : ${RESET}"
        read action
        case $action in
            1) $INSTALL_FUNC ;;
            2) $UNINSTALL_FUNC ;;
            0) break ;;
            *) echo -e "${RED}❌ Mauvais choix, réessayez.${RESET}" ;;
        esac
    done
}

while true; do
    echo ""
    echo -e "${CYAN}+======================================================+${RESET}"
    echo -e "|               🚀 MENU PRINCIPAL DES MODES 🚀         |"
    echo -e "${CYAN}+======================================================+${RESET}"
    echo -e "${GREEN}${BOLD}[01]${RESET} ${YELLOW}OpenSSH${RESET}"
    echo -e "${GREEN}${BOLD}[02]${RESET} ${YELLOW}Dropbear${RESET}"
    echo -e "${GREEN}${BOLD}[03]${RESET} ${YELLOW}SlowDNS${RESET}"
    echo -e "${GREEN}${BOLD}[04]${RESET} ${YELLOW}UDP Custom${RESET}"
    echo -e "${GREEN}${BOLD}[05]${RESET} ${YELLOW}SOCKS/Python${RESET}"
    echo -e "${GREEN}${BOLD}[06]${RESET} ${YELLOW}SSL/TLS${RESET}"
    echo -e "${GREEN}${BOLD}[07]${RESET} ${YELLOW}BadVPN${RESET}"
    echo -e "${GREEN}${BOLD}[08]${RESET} ${YELLOW}proxy ws${RESET}"
    echo -e "${GREEN}${BOLD}[09]${RESET} ${YELLOW}Hysteria${RESET}"
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
        8) manage_mode "proxy ws" install_proxy_ws uninstall_proxy_ws ;;
        9) manage_mode "Hysteria" install_hysteria uninstall_hysteria ;;
        0) echo -e "${RED}🚪 Sortie du panneau de contrôle.${RESET}" ; exit 0 ;;
        *) echo -e "${RED}❌ Option invalide, réessayez.${RESET}" ;;
    esac
done
