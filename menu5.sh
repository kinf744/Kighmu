#!/bin/bash
# menu5_color.sh
# Affichage dynamique état modes + installation interactive mode choisi dans un cadre coloré

INSTALL_DIR="$HOME/Kighmu"
WIDTH=50

# Couleurs
RESET="\e[0m"
BOLD="\e[1m"
CYAN="\e[36m"
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
MAGENTA="\e[35m"

line_full() {
    echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"
}

line_simple() {
    echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"
}

content_line() {
    local text="$1"
    local padding=$((WIDTH - ${#text}))
    printf "| %s%*s |\n" "$text" $padding ""
}

center_line() {
    local text="$1"
    local padding=$(( (WIDTH - ${#text}) / 2 ))
    printf "|%*s%s%*s|\n" $padding "" "$text" $padding ""
}

print_status() {
    local name="$1"
    local check_cmd="$2"
    local port="$3"
    if eval "$check_cmd" >/dev/null 2>&1; then
        printf "%-20s [%s]  Port: %s\n" "$name" "$(echo -e "${GREEN}installé${RESET}")" "$port"
    else
        printf "%-20s [%s]  Port: %s\n" "$name" "$(echo -e "${RED}non installé${RESET}")" "$port"
    fi
}

show_modes_status() {
    clear
    line_full
    center_line "${BOLD}${MAGENTA}Kighmu Control Panel${RESET}"
    line_full

    # Section Ports et Statut
    echo -e "${YELLOW}Statut des modes installés et ports utilisés:${RESET}"
    line_simple

    while IFS= read -r line; do
        content_line "$line"
    done < <(
        print_status "OpenSSH" "systemctl is-active --quiet ssh" "22"
        print_status "Dropbear" "systemctl is-active --quiet dropbear" "443"
        print_status "SlowDNS" "pgrep -f dns-server" "5300"
        print_status "UDP Custom" "pgrep -f udp_custom.sh" "7300"
        print_status "SOCKS/Python" "pgrep -f KIGHMUPROXY.py" "1080"
        print_status "SSL/TLS" "systemctl is-active --quiet nginx" "443/80"
        print_status "BadVPN" "pgrep -f badvpn" "7300-7303"
    )

    line_simple
    echo ""
}

install_mode() {
    case $1 in
        1)
            echo -e "${CYAN}Installation OpenSSH Server...${RESET}"
            sudo apt-get install -y openssh-server
            sudo systemctl enable ssh
            sudo systemctl start ssh
            ;;
        2)
            echo -e "${CYAN}Installation Dropbear SSH...${RESET}"
            sudo apt-get install -y dropbear
            sudo systemctl enable dropbear
            sudo systemctl start dropbear
            ;;
        3)
            echo -e "${CYAN}Installation SlowDNS...${RESET}"
            bash "$INSTALL_DIR/slowdns.sh" || echo -e "${RED}Erreur SlowDNS.${RESET}"
            ;;
        4)
            echo -e "${CYAN}Installation UDP Custom...${RESET}"
            bash "$INSTALL_DIR/udp_custom.sh" || echo -e "${RED}Erreur UDP Custom.${RESET}"
            ;;
        5)
            echo -e "${CYAN}Installation SOCKS/Python...${RESET}"
            bash "$INSTALL_DIR/socks_python.sh" || echo -e "${RED}Erreur SOCKS/Python.${RESET}"
            ;;
        6)
            echo -e "${CYAN}Installation SSL/TLS...${RESET}"
            # Ajouter installation SSL/TLS
            ;;
        7)
            echo -e "${CYAN}Installation BadVPN...${RESET}"
            # Ajouter installation BadVPN
            ;;
        *)
            echo -e "${RED}Choix invalide.${RESET}"
            ;;
    esac
}

while true; do
    show_modes_status

    line_full
    center_line "${BOLD}${MAGENTA}MENU INSTALLATION DES MODES${RESET}"
    line_full

    content_line "1) OpenSSH Server"
    content_line "2) Dropbear SSH"
    content_line "3) SlowDNS"
    content_line "4) UDP Custom"
    content_line "5) SOCKS/Python"
    content_line "6) SSL/TLS"
    content_line "7) BadVPN"
    content_line "8) Retour menu principal"
    line_simple
    echo ""

    read -p "Choisissez un mode à installer (ou 8 pour quitter) : " choix
    echo ""

    if [ "$choix" == "8" ]; then
        echo -e "${YELLOW}Retour au menu principal...${RESET}"
        break
    fi

    install_mode "$choix"
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
done
