#!/bin/bash
# menu5.sh - Gestion complète des modes avec installation/désinstallation + sous-menu V2Ray SlowDNS

INSTALL_DIR="$HOME/Kighmu"
WIDTH=60

# Couleurs
CYAN="\e[36m"
YELLOW="\e[33m"
RESET="\e[0m"

# Fonctions d'affichage
line_full() { echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
content_line() { printf "| %-56s |\n" "$1"; }
center_line() { local text="$1"; local padding=$(( (WIDTH - ${#text}) / 2 )); printf "|%*s%s%*s|\n" "$padding" "" "$text" "$padding" ""; }

# Affichage des statuts dynamiques
print_status() {
    local name="$1"
    local service="$2"
    local port="$3"

    if systemctl list-unit-files | grep -q "^$service.service"; then
        if systemctl is-active --quiet "$service"; then
            content_line "$(printf "%-18s [installé & actif] Port: %s" "$name" "$port")"
        else
            content_line "$(printf "%-18s [installé mais inactif] Port: %s" "$name" "$port")"
        fi
    else
        content_line "$(printf "%-18s [non installé] Port: %s" "$name" "$port")"
    fi
}

show_modes_status() {
    clear
    line_full
    center_line "${YELLOW}Kighmu Control Panel${RESET}"
    line_full
    center_line "${YELLOW}Statut des modes installés et ports utilisés${RESET}"
    line_simple
    print_status "OpenSSH" "ssh" "22"
    print_status "Dropbear" "dropbear" "90"
    print_status "SlowDNS" "slowdns" "5300"
    print_status "UDP Custom" "udp-custom" "54000"
    print_status "SOCKS/Python" "socks-python" "8080"
    print_status "SSL/TLS" "nginx" "444"
    print_status "BadVPN" "badvpn" "7303"
    line_simple
    echo ""
}

# Les fonctions install_mode et uninstall_mode restent identiques à ton script précédent

# Boucle principale
while true; do
    show_modes_status
    line_full
    center_line "${YELLOW}MENU GESTION DES MODES${RESET}"
    line_full
    content_line "1) Installer un mode"
    content_line "2) Désinstaller un mode"
    content_line "0) Retour menu principal"
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
        0)
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
