#!/bin/bash
# ==============================================
# Kighmu VPS Manager - Version Dynamique
# ==============================================

# Vérifier si l'utilisateur est root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "\e[31m[ERREUR]\e[0m Veuillez exécuter ce script en root."
    exit 1
fi

# Couleurs
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# Répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fonctions d'état

get_ssh_users_count() {
    grep -cE "/home" /etc/passwd
}

# Fonction: Récupère les IP par port et protocole (tcp/udp)
get_port_ips() {
    local port=$1
    local proto=$2
    ss -n -"$proto" sport = :$port 2>/dev/null | awk 'NR>1{print $5}' | cut -d: -f1 | sort -u
}

# Dropbear: IP connectées
get_dropbear_ips() {
    local auth_log="/var/log/auth.log"
    ps ax | grep dropbear | grep -v grep | awk '{print $1}' | while read pid; do
        entry=$(grep "Password auth succeeded" $auth_log | grep "dropbear\[$pid\]")
        if [[ $entry ]]; then
            ip=$(echo $entry | awk -F'from ' '{print $2}' | awk '{print $1}')
            echo "$ip"
        fi
    done | sort -u
}

# OpenVPN: IP connectées (si status file existe)
get_openvpn_ips() {
    local status_file="/etc/openvpn/openvpn-status.log"
    if [ -f "$status_file" ]; then
        grep 'CLIENT_LIST' "$status_file" | awk -F',' '{print $3}' | sort -u
    fi
}

# WireGuard: IP connectées
get_wireguard_ips() {
    command -v wg >/dev/null 2>&1 || return
    wg show | awk '/endpoint:/{print $2}' | cut -d: -f1 | sort -u
}

# Récupère la charge moyenne CPU
get_cpu_usage() {
    grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.2f%%", usage}'
}

# Récupère les infos système OS
get_os_info() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$NAME $VERSION_ID"
    else
        uname -s
    fi
}

# Calcule le nombre total d'appareils connectés (SSH, Dropbear, VPN, SlowDNS, UDP custom, SOCKS)
count_all_connected_devices() {
    local ips
    ips=$(get_port_ips 22 t)
    ips+=" "$(get_dropbear_ips)
    ips+=" "$(get_openvpn_ips)
    ips+=" "$(get_wireguard_ips)
    ips+=" "$(get_port_ips 5300 u)
    ips+=" "$(get_port_ips 54000 u)
    ips+=" "$(get_port_ips 8080 t)
    echo "$ips" | tr ' ' '\n' | grep -v "^$" | sort -u | wc -l
}

while true; do
    clear
    OS_INFO=$(get_os_info)
    IP=$(hostname -I | awk '{print $1}')
    RAM_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2}')
    CPU_USAGE=$(get_cpu_usage)
    SSH_USERS_COUNT=$(get_ssh_users_count)
    DEVICES_COUNT=$(count_all_connected_devices)

    echo -e "${CYAN}+==================================================+${RESET}"
    echo -e "${BOLD}${MAGENTA}|                🚀 KIGHMU MANAGER 🇨🇲 🚀             |${RESET}"
    echo -e "${CYAN}+==================================================+${RESET}"

    # Ligne compacte OS et IP
    printf " OS: %-20s | IP: %-15s\n" "$OS_INFO" "$IP"

    # Ligne RAM et CPU (ajout couleurs)
    printf " RAM utilisée: ${GREEN}%-6s${RESET} | CPU utilisé: ${YELLOW}%-6s${RESET}\n" "$RAM_USAGE" "$CPU_USAGE"

    echo -e "${CYAN}+--------------------------------------------------+${RESET}"

    # Utilisateurs SSH et appareils (nombre d'IP SSH uniques) en couleurs différentes
    printf " Utilisateurs SSH: ${BLUE}%-4d${RESET} | Appareils connectés: ${MAGENTA}%-4d${RESET}\n" "$SSH_USERS_COUNT" "$DEVICES_COUNT"

    echo -e "${CYAN}+--------------------------------------------------+${RESET}"

    echo -e "${BOLD}${YELLOW}|                  MENU PRINCIPAL:                 |${RESET}"
    echo -e "${CYAN}+--------------------------------------------------+${RESET}"
    echo -e "${GREEN}[01]${RESET} Créer un utilisateur SSH"
    echo -e "${GREEN}[02]${RESET} Créer un test utilisateur"
    echo -e "${GREEN}[03]${RESET} Voir les utilisateurs en ligne"
    echo -e "${GREEN}[04]${RESET} Modifier durée / mot de passe utilisateur"
    echo -e "${GREEN}[05]${RESET} Supprimer un utilisateur"
    echo -e "${GREEN}[06]${RESET} Installation de mode"
    echo -e "${GREEN}[07]${RESET} V2ray slowdns mode"
    echo -e "${GREEN}[08]${RESET} Désinstaller le script"
    echo -e "${GREEN}[09]${RESET} Blocage de torrents"
    echo -e "${RED}[10] Quitter${RESET}"
    echo -e "${CYAN}+--------------------------------------------------+${RESET}"
    echo -ne "${BOLD}${YELLOW} Entrez votre choix [1-10]: ${RESET}"
    read -r choix
    echo -e "${CYAN}+--------------------------------------------------+${RESET}"

    case $choix in
        1) bash "$SCRIPT_DIR/menu1.sh" ;;
        2) bash "$SCRIPT_DIR/menu2.sh" ;;
        3) bash "$SCRIPT_DIR/menu3.sh" ;;
        4) bash "$SCRIPT_DIR/menu_4.sh" ;;
        5) bash "$SCRIPT_DIR/menu4.sh" ;;
        6) bash "$SCRIPT_DIR/menu5.sh" ;;
        7) bash "$SCRIPT_DIR/menu_5.sh" ;;  
        8)
            echo -e "${YELLOW}⚠️  Vous êtes sur le point de désinstaller le script.${RESET}"
            read -p "Voulez-vous vraiment continuer ? (o/N): " confirm
            if [[ "$confirm" =~ ^[Oo]$ ]]; then
                echo -e "${RED}Désinstallation en cours...${RESET}"
                rm -rf "$SCRIPT_DIR"
                clear
                echo -e "${RED}✅ Script désinstallé avec succès.${RESET}"
                echo -e "${CYAN}Le panneau de contrôle est maintenant désactivé.${RESET}"
                exit 0
            else
                echo -e "${GREEN}Opération annulée, retour au menu...${RESET}"
            fi
            ;;
        9) bash "$SCRIPT_DIR/menu7.sh" ;;
        10)
            clear
            echo -e "${RED}Au revoir !${RESET}"
            exit 0
            ;;
        *)
            echo -e "${RED}Choix invalide !${RESET}" ;;
    esac

    echo ""
    read -p "Appuyez sur Entrée pour revenir au menu..."
done
