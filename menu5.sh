#!/bin/bash
# menu5.sh - Gestion complète des modes avec installation/désinstallation

INSTALL_DIR="$HOME/Kighmu"
WIDTH=60

# Couleurs
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# Fonctions d'affichage
line_full() { echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
center_line() {
    local text="$1"
    local padding=$(( (WIDTH - ${#text}) / 2 ))
    printf "|%*s%s%*s|\n" "$padding" "" "$text" "$padding" ""
}
content_line() { printf "| %-56s |\n" "$1"; }

# Vérifie si un service est installé et actif
service_status() {
    local svc="$1"
    if systemctl list-unit-files | grep -q "^$svc.service"; then
        if systemctl is-active --quiet "$svc"; then
            echo "[actif]"
        else
            echo "[installé mais inactif]"
        fi
    else
        echo "[non installé]"
    fi
}

# Affichage dynamique des statuts
show_modes_status() {
    clear
    line_full
    center_line "${YELLOW}GESTION DES MODES${RESET}"
    line_full
    content_line "Statut des modes installés et ports utilisés"
    line_simple
    content_line "OpenSSH       : 22 $(service_status ssh)"
    content_line "Dropbear      : 90 $(service_status dropbear)"
    content_line "SlowDNS       : 5300 $(service_status slowdns)"
    content_line "UDP Custom    : 54000 $(service_status udp-custom)"
    content_line "SOCKS/Python  : 8080 $(service_status socks-python)"
    content_line "SSL/TLS       : 443 $(service_status nginx)"
    content_line "BadVPN 1      : 7200 $(service_status badvpn)"
    content_line "BadVPN 2      : 7300 $(service_status badvpn)"
    line_simple
}

# Installation d'un mode
install_mode() {
    case $1 in
        1) apt-get install -y openssh-server && systemctl enable ssh && systemctl restart ssh ;;
        2) apt-get install -y dropbear && systemctl enable dropbear && systemctl restart dropbear ;;
        3) [[ -x "$INSTALL_DIR/slowdns.sh" ]] && bash "$INSTALL_DIR/slowdns.sh" && systemctl enable --now slowdns ;;
        4) [[ -x "$INSTALL_DIR/udp_custom.sh" ]] && bash "$INSTALL_DIR/udp_custom.sh" && systemctl enable --now udp-custom ;;
        5) [[ -x "$INSTALL_DIR/socks_python.sh" ]] && bash "$INSTALL_DIR/socks_python.sh" && systemctl enable --now socks-python ;;
        6) apt-get install -y nginx && systemctl enable nginx && systemctl restart nginx ;;
        7) systemctl enable --now badvpn ;;
        *) echo -e "${RED}Choix invalide.${RESET}" ;;
    esac
}

# Désinstallation d'un mode
uninstall_mode() {
    case $1 in
        1) systemctl disable --now ssh && apt-get remove -y openssh-server ;;
        2) systemctl disable --now dropbear && apt-get remove -y dropbear ;;
        3) systemctl disable --now slowdns ;;
        4) systemctl disable --now udp-custom ;;
        5) systemctl disable --now socks-python ;;
        6) systemctl disable --now nginx && apt-get remove -y nginx ;;
        7) systemctl disable --now badvpn ;;
        *) echo -e "${RED}Choix invalide.${RESET}" ;;
    esac
}

# Boucle principale
while true; do
    show_modes_status
    line_full
    center_line "${YELLOW}MENU GESTION DES MODES${RESET}"
    line_full
    content_line "1) Installer un mode"
    content_line "2) Désinstaller un mode"
    content_line "3) Retour menu principal"
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
        3)
            echo "Retour au menu principal..."
            sleep 1
            bash "$INSTALL_DIR/kighmu.sh"
            exit 0
            ;;
        *)
            echo -e "${RED}Choix invalide.${RESET}" ;;
    esac

    read -p "Appuyez sur Entrée pour continuer..."
done
