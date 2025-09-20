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
echo -e "${CYAN}+=====================================================+${RESET}"
echo -e "|           🚀 PANNEAU DE CONTROLE DES MODES 🚀       |"
echo -e "${CYAN}+=====================================================+${RESET}"

# Détection IP et uptime
HOST_IP=$(curl -s https://api.ipify.org)
UPTIME=$(uptime -p)
echo -e "${CYAN} IP: ${GREEN}$HOST_IP${RESET} | ${CYAN}Uptime: ${GREEN}$UPTIME${RESET}"
echo ""

# Fonctions SlowDNS
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

# Fonctions OpenSSH
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

# Fonctions Dropbear
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

# UDP Custom
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

# SOCKS Python
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

# SSL/TLS et BadVPN - à compléter
install_ssl_tls() { echo ">>> Installation SSL/TLS (à compléter)"; }
uninstall_ssl_tls() { echo ">>> Désinstallation SSL/TLS (à compléter)"; }
install_badvpn() { echo ">>> Installation BadVPN (à compléter)"; }
uninstall_badvpn() { echo ">>> Désinstallation BadVPN (à compléter)"; }

# Gestion du sous-menu des modes avec coloration appliquée
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

# Menu principal avec coloration appliquée
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
    echo -e "${GREEN}${BOLD}[00]${RESET} ${YELLOW}Quitter${RESET}"
    echo -e "${CYAN}+======================================================+${RESET}"
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
        0) echo -e "${RED}🚪 Sortie du panneau de contrôle.${RESET}" ; exit 0 ;;
        *) echo -e "${RED}❌ Option invalide, réessayez.${RESET}" ;;
    esac
done
