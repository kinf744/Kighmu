#!/bin/bash
# ==============================================
# menu5.sh - Gestion complète des modes (installation/désinstallation)
# ==============================================

INSTALL_DIR="$HOME/Kighmu"
WIDTH=60
CYAN="\e[36m"
RESET="\e[0m"

# Fonctions d'affichage
line_full() { echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
content_line() { printf "| %-56s |\n" "$1"; }
center_line() {
    local text="$1"
    local clean_text=$(echo -e "$text" | sed 's/\x1B\[[0-9;]*[mK]//g')
    local padding=$(( (WIDTH - ${#clean_text}) / 2 ))
    printf "|%*s%s%*s|\n" "$padding" "" "$text" "$padding" ""
}

# Vérification du statut des services
service_status() {
    local svc="$1"
    if systemctl list-unit-files | grep -q "^$svc.service"; then
        systemctl is-active --quiet "$svc" && echo "[ACTIF]" || echo "[INACTIF]"
    else
        echo "[NON INSTALLÉ]"
    fi
}

show_modes_status() {
    clear
    line_full
    center_line "GESTION DES MODES"
    line_full
    center_line "Statut des modes installés et ports"
    line_simple
    content_line "OpenSSH     : 22 $(service_status ssh)"
    content_line "Dropbear    : 90 $(service_status dropbear)"
    content_line "SlowDNS     : 5300 $(service_status slowdns)"
    content_line "UDP Custom  : 54000 $(service_status udp-custom)"
    content_line "SOCKS/Python: 8080 $(service_status socks-python)"
    content_line "SSL/TLS     : 443 $(service_status nginx)"
    content_line "BadVPN      : 7303 $(service_status badvpn)"
    line_simple
}

install_mode() {
    case $1 in
        1) apt-get install -y openssh-server && systemctl enable --now ssh ;;
        2) apt-get install -y dropbear && systemctl enable --now dropbear ;;
        3) [[ -x "$INSTALL_DIR/slowdns.sh" ]] && bash "$INSTALL_DIR/slowdns.sh" || echo "slowdns.sh introuvable" ;;
        4) [[ -x "$INSTALL_DIR/udp_custom.sh" ]] && bash "$INSTALL_DIR/udp_custom.sh" || echo "udp_custom.sh introuvable" ;;
        5) [[ -x "$INSTALL_DIR/socks_python.sh" ]] && bash "$INSTALL_DIR/socks_python.sh" || echo "socks_python.sh introuvable" ;;
        6) apt-get install -y nginx && systemctl enable --now nginx ;;
        7) create_service "badvpn" "/usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7303 --max-clients 500" ;;
        *) echo "Choix invalide" ;;
    esac
}

uninstall_mode() {
    case $1 in
        1) systemctl disable --now ssh && apt-get remove -y openssh-server ;;
        2) systemctl disable --now dropbear && apt-get remove -y dropbear ;;
        3) systemctl disable --now slowdns ;;
        4) systemctl disable --now udp-custom ;;
        5) systemctl disable --now socks-python ;;
        6) systemctl disable --now nginx && apt-get remove -y nginx ;;
        7) systemctl disable --now badvpn ;;
        *) echo "Choix invalide" ;;
    esac
}

# Menu principal des modes
while true; do
    show_modes_status
    line_full
    content_line "1) Installer un mode"
    content_line "2) Désinstaller un mode"
    content_line "0) Retour au menu principal"
    line_simple

    read -p "Votre choix : " action
    case $action in
        1)
            echo "Choisissez un mode à installer :"
            echo "1) OpenSSH Server"
            echo "2) Dropbear SSH"
            echo "3) SlowDNS"
            echo "4) UDP Custom"
            echo "5) SOCKS/Python"
            echo "6) SSL/TLS"
            echo "7) BadVPN"
            read -p "Numéro du mode : " choix
            install_mode "$choix"
            ;;
        2)
            echo "Choisissez un mode à désinstaller :"
            echo "1) OpenSSH Server"
            echo "2) Dropbear SSH"
            echo "3) SlowDNS"
            echo "4) UDP Custom"
            echo "5) SOCKS/Python"
            echo "6) SSL/TLS"
            echo "7) BadVPN"
            read -p "Numéro du mode : " choix
            uninstall_mode "$choix"
            ;;
        0) break ;;
        *) echo "Choix invalide" ; read -p "Appuyez sur Entrée pour continuer..." ;;
    esac
done
