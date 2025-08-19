#!/bin/bash
# menu5.sh
# Affichage dynamique état modes + installation interactive mode choisi dans un cadre

INSTALL_DIR="$HOME/Kighmu"
WIDTH=44

line_full() {
    echo "+$(printf '%0.s=' $(seq 1 $WIDTH))+"
}

line_simple() {
    echo "+$(printf '%0.s-' $(seq 1 $WIDTH))+"
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
    if eval "$check_cmd" >/dev/null 2>&1; then
        printf "%-30s [%s]\n" "$name" "installé"
    else
        printf "%-30s [%s]\n" "$name" "non installé"
    fi
}

show_modes_status() {
    clear
    line_full
    center_line "ÉTAT DES MODES"
    line_full

    # Afficher chaque ligne de statut dans le cadre
    while IFS= read -r line; do
        content_line "$line"
    done < <(
        print_status "OpenSSH Server" "systemctl is-active --quiet ssh"
        print_status "Dropbear SSH" "systemctl is-active --quiet dropbear"
        print_status "SlowDNS" "pgrep -f dns-server"
        print_status "UDP Custom" "pgrep -f udp_custom.sh"
        print_status "SOCKS/Python" "pgrep -f KIGHMUPROXY.py"
        print_status "SSL/TLS" "systemctl is-active --quiet nginx"
        print_status "BadVPN" "pgrep -f badvpn"
    )

    line_simple
    echo ""
}

install_mode() {
    case $1 in
        1)
            echo "Installation OpenSSH Server..."
            sudo apt-get install -y openssh-server
            sudo systemctl enable ssh
            sudo systemctl start ssh
            ;;
        2)
            echo "Installation Dropbear SSH..."
            sudo apt-get install -y dropbear
            sudo systemctl enable dropbear
            sudo systemctl start dropbear
            ;;
        3)
            echo "Installation SlowDNS..."
            bash "$INSTALL_DIR/slowdns.sh" || echo "SlowDNS : script non trouvé ou erreur."
            ;;
        4)
            echo "Installation UDP Custom..."
            bash "$INSTALL_DIR/udp_custom.sh" || echo "UDP Custom : script non trouvé ou erreur."
            ;;
        5)
            echo "Installation SOCKS/Python..."
            bash "$INSTALL_DIR/socks_python.sh" || echo "SOCKS/Python : script non trouvé ou erreur."
            ;;
        6)
            echo "Installation SSL/TLS..."
            # Ajoute ici les commandes d'installation/configuration SSL/TLS
            ;;
        7)
            echo "Installation BadVPN..."
            # Ajoute ici les commandes d'installation/configuration BadVPN
            ;;
        *)
            echo "Choix invalide."
            ;;
    esac
}

while true; do
    show_modes_status

    line_full
    center_line "MENU INSTALLATION DES MODES"
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
        echo "Retour au menu principal..."
        break
    fi

    install_mode "$choix"
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
done
