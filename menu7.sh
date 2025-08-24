#!/bin/bash
# menu7.sh - Blocage des torrents, sites pornographiques et spam

WIDTH=60
CYAN="\e[36m"
YELLOW="\e[33m"
RED="\e[31m"
GREEN="\e[32m"
RESET="\e[0m"

line_full() { echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
center_line() {
    local text="$1"
    local padding=$(( (WIDTH - ${#text}) / 2 ))
    printf "|%*s%s%*s|\n" "$padding" "" "$text" "$padding" ""
}
content_line() { printf "| %-56s |\n" "$1"; }

# Vérifie si un blocage est actif
block_status() {
    local type="$1"
    case "$type" in
        torrents)
            iptables -L OUTPUT -n | grep -q 'tcp dpt:6881:6889' && echo "[actif]" || echo "[non actif]" ;;
        porn)
            iptables -L OUTPUT -n | grep -q 'porn_sites_block' && echo "[actif]" || echo "[non actif]" ;;
        spam)
            iptables -L INPUT -n | grep -q 'DROP.*spam' && echo "[actif]" || echo "[non actif]" ;;
    esac
}

# Applique les blocages
enable_block() {
    case "$1" in
        torrents)
            iptables -A OUTPUT -p tcp --dport 6881:6889 -j DROP
            iptables -A OUTPUT -p udp --dport 1024:65535 -j DROP ;;
        porn)
            # Exemple simple, remplacer par liste réelle de sites
            iptables -N porn_sites_block 2>/dev/null
            iptables -A OUTPUT -p tcp -m string --string "porn" --algo bm -j DROP
            iptables -I OUTPUT -j porn_sites_block ;;
        spam)
            iptables -A INPUT -m string --string "spam" --algo bm -j DROP ;;
    esac
}

disable_block() {
    case "$1" in
        torrents)
            iptables -D OUTPUT -p tcp --dport 6881:6889 -j DROP 2>/dev/null
            iptables -D OUTPUT -p udp --dport 1024:65535 -j DROP 2>/dev/null ;;
        porn)
            iptables -F porn_sites_block 2>/dev/null
            iptables -D OUTPUT -j porn_sites_block 2>/dev/null ;;
        spam)
            iptables -D INPUT -m string --string "spam" --algo bm -j DROP 2>/dev/null ;;
    esac
}

while true; do
    clear
    line_full
    center_line "${YELLOW}GESTION DES BLOCAGES${RESET}"
    line_full
    content_line "1) Blocage complet des torrents $(block_status torrents)"
    content_line "2) Blocage complet des sites pornographiques $(block_status porn)"
    content_line "3) Blocage complet des spams $(block_status spam)"
    content_line "4) Retour au menu principal"
    line_simple
    echo ""

    read -p "Votre choix : " choix

    case $choix in
        1)
            if [[ "$(block_status torrents)" == "[actif]" ]]; then
                disable_block torrents
                echo -e "${GREEN}Blocage torrents désactivé.${RESET}"
            else
                enable_block torrents
                echo -e "${GREEN}Blocage torrents activé.${RESET}"
            fi ;;
        2)
            if [[ "$(block_status porn)" == "[actif]" ]]; then
                disable_block porn
                echo -e "${GREEN}Blocage sites pornographiques désactivé.${RESET}"
            else
                enable_block porn
                echo -e "${GREEN}Blocage sites pornographiques activé.${RESET}"
            fi ;;
        3)
            if [[ "$(block_status spam)" == "[actif]" ]]; then
                disable_block spam
                echo -e "${GREEN}Blocage spam désactivé.${RESET}"
            else
                enable_block spam
                echo -e "${GREEN}Blocage spam activé.${RESET}"
            fi ;;
        4)
            bash "$HOME/Kighmu/kighmu.sh"
            exit 0 ;;
        *)
            echo -e "${RED}Choix invalide.${RESET}" ;;
    esac

    read -p "Appuyez sur Entrée pour continuer..."
done
