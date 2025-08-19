#!/bin/bash
# menu5.sh
# Affichage dynamique état modes + installation interactive mode choisi

INSTALL_DIR="$HOME/Kighmu"

echo "+--------------------------------------------+"
echo "|              ÉTAT DES MODES                |"
echo "+--------------------------------------------+"

print_status() {
    local name="$1"
    local check_cmd="$2"

    if eval "$check_cmd" >/dev/null 2>&1; then
        printf "%-35s [%s]\n" "$name" "installé"
    else
        printf "%-35s [%s]\n" "$name" "non installé"
    fi
}

show_modes_status() {
    clear
    echo "+--------------------------------------------+"
    echo "|              ÉTAT DES MODES                |"
    echo "+--------------------------------------------+"

    print_status "OpenSSH Server" "systemctl is-active --quiet ssh"
    print_status "Dropbear SSH" "systemctl is-active --quiet dropbear"
    print_status "SlowDNS" "pgrep -f dns-server"
    print_status "UDP Custom" "pgrep -f udp_custom.sh"
    print_status "SOCKS/Python" "pgrep -f KIGHMUPROXY.py"
    print_status "SSL/TLS" "systemctl is-active --quiet nginx"
    print_status "BadVPN" "pgrep -f badvpn"

    echo "+--------------------------------------------+"
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
            # Ajoute ici les commandes pour installer/configurer SSL/TLS
            ;;
        7)
            echo "Installation BadVPN..."
            # Ajoute ici les commandes pour installer/configurer BadVPN
            ;;
        *)
            echo "Choix invalide."
            ;;
    esac
}

while true; do
    show_modes_status

    echo "Menu installation modes :"
    echo "1) OpenSSH Server"
    echo "2) Dropbear SSH"
    echo "3) SlowDNS"
    echo "4) UDP Custom"
    echo "5) SOCKS/Python"
    echo "6) SSL/TLS"
    echo "7) BadVPN"
    echo "8) Retour menu principal"
    echo ""

    read -p "Choisissez un mode à installer (ou 8 pour quitter) : " choix

    if [ "$choix" == "8" ]; then
        echo "Retour au menu principal..."
        break
    fi

    install_mode "$choix"

    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
done
