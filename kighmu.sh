#!/bin/bash
# ==============================================
# Kighmu VPS Manager (affichage coloré RAM/CPU/Users)
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
CYAN="\e[36m"
MAGENTA="\e[35m"
BOLD="\e[1m"
RESET="\e[0m"

# Répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fonctions
get_ssh_users_count() { grep -cE "/home" /etc/passwd; }
get_devices_count() { ss -ntu state established 2>/dev/null | grep -c ESTAB; }
get_cpu_usage() { grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.2f", usage}'; }

# Détection OS
get_os_info() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$NAME $VERSION_ID"
    else
        uname -s
    fi
}

# Fonction de couleur selon utilisation %
colorize_usage() {
    local usage=$1
    if (( $(echo "$usage < 50" | bc -l) )); then
        echo -e "${GREEN}${usage}%${RESET}"
    elif (( $(echo "$usage < 80" | bc -l) )); then
        echo -e "${YELLOW}${usage}%${RESET}"
    else
        echo -e "${RED}${usage}%${RESET}"
    fi
}

while true; do
    clear
    OS_INFO=$(get_os_info)
    IP=$(hostname -I | awk '{print $1}')
    RAM_USAGE=$(free -m | awk 'NR==2{printf "%.2f", $3*100/$2 }')
    CPU_USAGE=$(get_cpu_usage)
    SSH_USERS_COUNT=$(get_ssh_users_count)
    DEVICES_COUNT=$(get_devices_count)

    RAM_COLORED=$(colorize_usage "$RAM_USAGE")
    CPU_COLORED=$(colorize_usage "$CPU_USAGE")

    if [ "$SSH_USERS_COUNT" -gt 0 ]; then
        SSH_COLORED="${GREEN}${SSH_USERS_COUNT}${RESET}"
    else
        SSH_COLORED="${RED}${SSH_USERS_COUNT}${RESET}"
    fi

    if [ "$DEVICES_COUNT" -gt 0 ]; then
        DEVICES_COLORED="${GREEN}${DEVICES_COUNT}${RESET}"
    else
        DEVICES_COLORED="${RED}${DEVICES_COUNT}${RESET}"
    fi

    echo -e "${CYAN}+==================================================+${RESET}"
    echo -e "${BOLD}${MAGENTA}|                🚀 KIGHMU MANAGER 🚀               |${RESET}"
    echo -e "${CYAN}+==================================================+${RESET}"

    # Ligne OS et IP
    printf " OS: %-20s | IP: %-15s\n" "$OS_INFO" "$IP"

    # Ligne RAM et CPU (colorée)
    printf " RAM utilisée: %-6s | CPU utilisé: %-6s\n" "$RAM_COLORED" "$CPU_COLORED"

    echo -e "${CYAN}+--------------------------------------------------+${RESET}"
    printf " Utilisateurs SSH: %-4s | Appareils: %-4s\n" "$SSH_COLORED" "$DEVICES_COLORED"
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
