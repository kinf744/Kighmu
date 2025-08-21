#!/bin/bash
# menu5.sh
# Affichage dynamique état modes + installation/désinstallation interactive

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
    print_status "SlowDNS"   "systemctl is-active --quiet slowdns"  "5300"
    print_status "UDP Custom" "systemctl is-active --quiet udp-custom" "54000"
    print_status "SOCKS/Python" "systemctl is-active --quiet socks-python" "8080"
    print_status "SSL/TLS"   "systemctl is-active --quiet nginx"    "444"
    print_status "BadVPN"    "systemctl is-active --quiet badvpn"   "7303"

    line_simple
    echo ""
}

# Créer un service systemd
create_service() {
    local service_name="$1"
    local exec_cmd="$2"

    cat > "/etc/systemd/system/$service_name.service" <<EOF
[Unit]
Description=$service_name Service
After=network.target

[Service]
ExecStart=$exec_cmd
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$service_name"
    systemctl restart "$service_name"
}

# Désinstaller un service systemd
remove_service() {
    local service_name="$1"

    systemctl disable --now "$service_name" 2>/dev/null
    rm -f "/etc/systemd/system/$service_name.service"
    systemctl daemon-reload
    echo -e "${YELLOW}Service $service_name désinstallé.${RESET}"
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
            bash "$INSTALL_DIR/slowdns.sh"
            create_service "slowdns" "/bin/bash $INSTALL_DIR/slowdns.sh"
            ;;
        4)
            echo -e "${CYAN}Installation UDP Custom...${RESET}"
            bash "$INSTALL_DIR/udp_custom.sh"
            create_service "udp-custom" "/bin/bash $INSTALL_DIR/udp_custom.sh"
            ;;
        5)
            echo -e "${CYAN}Installation SOCKS/Python...${RESET}"
            bash "$INSTALL_DIR/socks_python.sh"
            create_service "socks-python" "/usr/bin/python3 $INSTALL_DIR/KIGHMUPROXY.py"
            ;;
        6)
            echo -e "${CYAN}Installation SSL/TLS...${RESET}"
            apt-get install -y nginx
            systemctl enable nginx && systemctl restart nginx
            ;;
        7)
            echo -e "${CYAN}Installation BadVPN...${RESET}"
            create_service "badvpn" "/usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7303 --max-clients 500"
            ;;
        *)
            echo -e "${RED}Choix invalide.${RESET}"
            ;;
    esac
}

# Désinstaller un mode
uninstall_mode() {
    case $1 in
        1)
            echo -e "${YELLOW}Suppression OpenSSH Server...${RESET}"
            systemctl disable --now ssh
            apt-get remove -y openssh-server
            ;;
        2)
            echo -e "${YELLOW}Suppression Dropbear SSH...${RESET}"
            systemctl disable --now dropbear
            apt-get remove -y dropbear
            ;;
        3)
            echo -e "${YELLOW}Suppression SlowDNS...${RESET}"
            remove_service "slowdns"
            ;;
        4)
            echo -e "${YELLOW}Suppression UDP Custom...${RESET}"
            remove_service "udp-custom"
            ;;
        5)
            echo -e "${YELLOW}Suppression SOCKS/Python...${RESET}"
            remove_service "socks-python"
            ;;
        6)
            echo -e "${YELLOW}Suppression SSL/TLS (nginx)...${RESET}"
            systemctl disable --now nginx
            apt-get remove -y nginx
            ;;
        7)
            echo -e "${YELLOW}Suppression BadVPN...${RESET}"
            remove_service "badvpn"
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
    center_line "${BOLD}${MAGENTA}MENU GESTION DES MODES${RESET}"
    line_full
    content_line "1) Installer un mode"
    content_line "2) Désinstaller un mode"
    content_line "3) Retour menu principal"
    line_simple
    echo ""

    read -p "Votre choix : " action
    echo ""

    case $action in
        1)
            echo -e "${CYAN}Choisissez un mode à installer :${RESET}"
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
            echo -e "${YELLOW}Choisissez un mode à désinstaller :${RESET}"
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
            echo -e "${YELLOW}Retour au menu principal...${RESET}"
            sleep 1
            bash "$INSTALL_DIR/kighmu.sh"
            exit 0
            ;;
        *)
            echo -e "${RED}Choix invalide.${RESET}"
            ;;
    esac

    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
done
