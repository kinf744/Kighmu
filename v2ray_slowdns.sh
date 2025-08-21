#!/bin/bash
# v2ray_slowdns.sh - Gestion V2Ray SlowDNS

INSTALL_DIR="$HOME/Kighmu"
WIDTH=60

# Couleurs
RESET="\e[0m"
BOLD="\e[1m"
CYAN="\e[36m"
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
MAGENTA="\e[35m"

# Fonctions d'affichage
line_full() { echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
content_line() { printf "| %-56s |\n" "$1"; }

center_line() {
    local text="$1"
    local visible_text=$(echo -e "$text" | sed 's/\x1B\[[0-9;]*[mK]//g')
    local padding=$(( (WIDTH - ${#visible_text}) / 2 ))
    printf "|%*s%s%*s|\n" "$padding" "" "$text" "$padding" ""
}

# Menu V2Ray SlowDNS
while true; do
    clear
    line_full
    center_line "${BOLD}${MAGENTA}V2Ray SlowDNS Management${RESET}"
    line_full
    content_line "1) Installer le tunnel V2Ray SlowDNS"
    content_line "2) Créer un utilisateur V2Ray SlowDNS"
    content_line "3) Supprimer un utilisateur V2Ray SlowDNS"
    content_line "4) Retour au menu précédent"
    line_simple
    echo ""

    read -p "Votre choix : " choice
    echo ""

    case $choice in
        1)
            echo -e "${CYAN}Installation du tunnel V2Ray SlowDNS...${RESET}"
            bash "$INSTALL_DIR/v2ray_slowdns_install.sh"
            ;;
        2)
            echo -e "${GREEN}Création d'un utilisateur V2Ray SlowDNS...${RESET}"
            bash "$INSTALL_DIR/v2ray_slowdns_add_user.sh"
            ;;
        3)
            echo -e "${RED}Suppression d'un utilisateur V2Ray SlowDNS...${RESET}"
            bash "$INSTALL_DIR/v2ray_slowdns_del_user.sh"
            ;;
        4)
            echo -e "${YELLOW}Retour au menu précédent...${RESET}"
            sleep 1
            break
            ;;
        *)
            echo -e "${RED}Choix invalide.${RESET}" ;;
    esac

    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
done
