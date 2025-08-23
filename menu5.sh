#!/bin/bash
# menu5.sh - Gestion complète des modes avec installation/désinstallation + sous-menu V2Ray SlowDNS

INSTALL_DIR="$HOME/Kighmu"
WIDTH=60

# Couleur bleue uniquement pour les lignes
CYAN="\e[36m"
RESET="\e[0m"

# Fonctions d'affichage
line_full() { echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
content_line() { printf "| %-56s |\n" "$1"; }

center_line() {
    local text="$1"
    local padding=$(( (WIDTH - ${#text}) / 2 ))
    printf "|%*s%s%*s|\n" "$padding" "" "$text" "$padding" ""
}

# Affichage des statuts
print_status() {
    local name="$1"
    local cmd="$2"
    local port="$3"
    if eval "$cmd" >/dev/null 2>&1; then
        content_line "$(printf "%-18s [installé] Port: %s" "$name" "$port")"
    else
        content_line "$(printf "%-18s [non installé] Port: %s" "$name" "$port")"
    fi
}

show_modes_status() {
    clear
    line_full
    center_line "Kighmu Control Panel"
    line_full
    center_line "Statut des modes installés et ports utilisés"
    line_simple
    print_status "OpenSSH" "systemctl is-active --quiet ssh" "22"
    print_status "Dropbear" "systemctl is-active --quiet dropbear" "90"
    print_status "SlowDNS" "systemctl is-active --quiet slowdns" "5300"
    print_status "UDP Custom" "systemctl is-active --quiet udp-custom" "54000"
    print_status "SOCKS/Python" "systemctl is-active --quiet socks-python" "8080"
    print_status "SSL/TLS" "systemctl is-active --quiet nginx" "444"
    print_status "BadVPN" "systemctl is-active --quiet badvpn" "7303"
    line_simple
    echo ""
}

# Création service systemd
create_service() {
    local name="$1"
    local cmd="$2"
    cat > "/etc/systemd/system/$name.service" <<EOF
[Unit]
Description=$name Service
After=network.target

[Service]
ExecStart=$cmd
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$name"
    systemctl restart "$name"
}

remove_service() {
    local name="$1"
    systemctl disable --now "$name" 2>/dev/null
    rm -f "/etc/systemd/system/$name.service"
    systemctl daemon-reload
    echo "Service $name désinstallé."
}

# Installation
install_mode() {
    case $1 in
        1) apt-get install -y openssh-server && systemctl enable ssh && systemctl restart ssh ;;
        2) apt-get install -y dropbear && systemctl enable dropbear && systemctl restart dropbear ;;
        3) [[ -x "$INSTALL_DIR/slowdns.sh" ]] && bash "$INSTALL_DIR/slowdns.sh" && create_service "slowdns" "/bin/bash $INSTALL_DIR/slowdns.sh" || echo "slowdns.sh introuvable." ;;
        4) [[ -x "$INSTALL_DIR/udp_custom.sh" ]] && bash "$INSTALL_DIR/udp_custom.sh" && create_service "udp-custom" "/bin/bash $INSTALL_DIR/udp_custom.sh" || echo "udp_custom.sh introuvable." ;;
        5) [[ -x "$INSTALL_DIR/socks_python.sh" ]] && bash "$INSTALL_DIR/socks_python.sh" && create_service "socks-python" "/usr/bin/python3 $INSTALL_DIR/KIGHMUPROXY.py" || echo "socks_python.sh introuvable." ;;
        6) apt-get install -y nginx && systemctl enable nginx && systemctl restart nginx ;;
        7) create_service "badvpn" "/usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7303 --max-clients 500" ;;
        *) echo "Choix invalide." ;;
    esac
}

# Désinstallation
uninstall_mode() {
    case $1 in
        1) systemctl disable --now ssh && apt-get remove -y openssh-server ;;
        2) systemctl disable --now dropbear && apt-get remove -y dropbear ;;
        3) remove_service "slowdns" ;;
        4) remove_service "udp-custom" ;;
        5) remove_service "socks-python" ;;
        6) systemctl disable --now nginx && apt-get remove -y nginx ;;
        7) remove_service "badvpn" ;;
        *) echo "Choix invalide." ;;
    esac
}

# Boucle menu principal des modes
while true; do
    show_modes_status
    line_full
    center_line "MENU GESTION DES MODES"
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
            echo "Choix invalide." ;;
    esac

    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
done
