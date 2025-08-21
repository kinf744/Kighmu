#!/bin/bash
# ==============================================
# Kighmu VPS Manager
# Copyright (c) 2025 Kinf744
# Licence MIT (version française)
# Voir le fichier LICENSE pour plus de détails
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
get_ssh_users_count() { grep -cE "/home" /etc/passwd; }
get_xray_users_count() { ls /etc/xray/users/ 2>/dev/null | wc -l; }
get_devices_count() { ss -ntu state established 2>/dev/null | grep -c ESTAB; }
get_cpu_usage() { grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.2f%%", usage}'; }

while true; do
    clear
    IP=$(hostname -I | awk '{print $1}')
    RAM_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }')
    CPU_USAGE=$(get_cpu_usage)
    SSH_USERS_COUNT=$(get_ssh_users_count)
    XRAY_USERS_COUNT=$(get_xray_users_count)
    DEVICES_COUNT=$(get_devices_count)

    echo -e "${CYAN}+==================================================+${RESET}"
    echo -e "${BOLD}${MAGENTA}|                🚀 KIGHMU MANAGER 🚀               |${RESET}"
    echo -e "${CYAN}+==================================================+${RESET}"
    printf "${GREEN} IP: %-17s${RESET}| ${YELLOW}RAM utilisée:${RESET} %-7s \n" "$IP" "$RAM_USAGE"
    printf "${BLUE} CPU utilisé: %-38s${RESET}\n" "$CPU_USAGE"
    echo -e "${CYAN}+--------------------------------------------------+${RESET}"
    printf " ${MAGENTA}Utilisateurs SSH:${RESET} %-4d | ${MAGENTA}Xray:${RESET} %-4d | ${MAGENTA}Appareils:${RESET} %-6d \n" \
        "$SSH_USERS_COUNT" "$XRAY_USERS_COUNT" "$DEVICES_COUNT"
    echo -e "${CYAN}+--------------------------------------------------+${RESET}"
    echo -e "${BOLD}${YELLOW}|                  MENU PRINCIPAL:                 |${RESET}"
    echo -e "${CYAN}+--------------------------------------------------+${RESET}"
    echo -e "${GREEN}[01]${RESET} Créer un utilisateur SSH"
    echo -e "${GREEN}[02]${RESET} Créer un test utilisateur"
    echo -e "${GREEN}[03]${RESET} Voir les utilisateurs en ligne"
    echo -e "${GREEN}[04]${RESET} Supprimer un utilisateur"
    echo -e "${GREEN}[05]${RESET} Installation de mode"
    echo -e "${GREEN}[06]${RESET} Xray mode"
    echo -e "${GREEN}[07]${RESET} Désinstaller le script"
    echo -e "${GREEN}[08]${RESET} Blocage de torrents"
    echo -e "${RED}[09] Quitter${RESET}"
    echo -e "${CYAN}+--------------------------------------------------+${RESET}"
    echo -ne "${BOLD}${YELLOW} Entrez votre choix [1-9]: ${RESET}"
    read -r choix
    echo -e "${CYAN}+--------------------------------------------------+${RESET}"

    case $choix in
        1) bash "$SCRIPT_DIR/menu1.sh" ;;
        2) bash "$SCRIPT_DIR/menu2.sh" ;;
        3) bash "$SCRIPT_DIR/menu3.sh" ;;
        4) bash "$SCRIPT_DIR/menu4.sh" ;;
        5) bash "$SCRIPT_DIR/menu5.sh" ;;
        6) bash "$SCRIPT_DIR/menu_6.sh" ;;
        7)
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
        8) bash "$SCRIPT_DIR/menu7.sh" ;;
        9)
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
