#!/bin/bash
# menu5_color.sh
# Affichage dynamique état modes + installation interactive mode choisi

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
    local padding=$(( (WIDTH - ${#text}) / 2 ))
    printf "|%*s%s%*s|\n" $padding "" "$text" $padding ""
}

# Vérifie état d’un service/mode
print_status() {
    local name="$1"
    local check_cmd="$2"
    local port="$3"
    if eval "$check_cmd" >/dev/null 2>&1; then
        content_line "$(printf "%-18s [%binstallé%b] Port: %s" "$name" "$GREEN" "$RESET" "$port")"
    else
        content_line "$(printf "%-18s [%bnon installé%b] Port: %s" "$name" "$RED" "$RESET" "$port")"
    fi
}

# Affichage statut des modes
show_modes_status() {
    clear
    line_full
    center_line "${BOLD}${MAGENTA}Kighmu Control Panel${RESET}"
    line_full
    center_line "${YELLOW}Statut des modes installés et ports utilisés${RESET}"
    line_simple

    print_status "OpenSSH"   "systemctl is-active --quiet ssh"       "22"
    print_status "Dropbear"  "systemctl is-active --quiet dropbear" "90"
    print_status "SlowDNS"   "pgrep -f dns-server"                  "5300"
    print_status "UDP Custom" "pgrep -f udp_custom.sh"              "54000"
    print_status "SOCKS/Python" "pgrep -f KIGHMUPROXY.py"           "8080"
    print_status "SSL/TLS"   "systemctl is-active --quiet nginx"    "444"
    print_status "BadVPN"    "pgrep -f badvpn"                      "7303"

    line_simple
    echo ""
}

# Installer un mode
install_mode() {
    case $1 in
        1)
            echo -e "${CYAN}Installation OpenSSH Server...${RESET}"
            apt-get install -y openssh-server
            systemctl enable ssh && systemctl restart ssh
            ;;
        2)
            echo -e "${CYAN}Installation Dropbear SSH...${RESET}"
            apt-get install -y dropbear
            systemctl enable dropbear && systemctl restart dropbear
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
            # Ajouter installation SSL/TLS ici
            ;;
        7)
            echo -e "${CYAN}Installation BadVPN...${RESET}"
            # Ajouter installation BadVPN ici
            ;;
        *)
            echo -e "${RED}Choix invalide.${RESET}"
            ;;
    esac
}

# Boucle menu
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

    read -p "Choisissez un mode à installer (ou 8 pour retour) : " choix
    echo ""

    if [ "$choix" == "8" ]; then
        echo -e "${YELLOW}Retour au menu principal...${RESET}"
        sleep 1
        bash "$INSTALL_DIR/kighmu.sh"
        exit 0
    fi

    install_mode "$choix"
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
done
