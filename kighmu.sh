#!/bin/bash
# ==============================================
# Kighmu VPS Manager - Version Dynamique Corrigée
# ==============================================

# Vérifier si root
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_FILE="/etc/kighmu/users.list"
AUTH_LOG="/var/log/auth.log"
OPENVPN_STATUS="/etc/openvpn/openvpn-status.log"
WIREGUARD_CMD="wg"

# ... (les fonctions restent inchangées) ...

while true; do
    clear
    OS_INFO=$(if [ -f /etc/os-release ]; then . /etc/os-release; echo "$NAME $VERSION_ID"; else uname -s; fi)
    IP=$(hostname -I | awk '{print $1}')
    
    TOTAL_RAM=$(free -m | awk 'NR==2{print $2 " Mo"}')
    CPU_FREQ=$(lscpu | grep "MHz" | head -1 | awk '{print $3 " MHz"}')
    
    RAM_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2}')
    CPU_USAGE=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.2f%%", usage}')
    
    if declare -f get_user_ips_by_service > /dev/null; then
        mapfile -t ssh_ips < <(get_user_ips_by_service 22 2>/dev/null || echo "")
    else
        ssh_ips=()
    fi

    if declare -f get_dropbear_user_ips > /dev/null; then
        mapfile -t dropbear_ips < <(get_dropbear_user_ips 2>/dev/null || echo "")
    else
        dropbear_ips=()
    fi

    if declare -f get_openvpn_user_ips > /dev/null; then
        mapfile -t openvpn_ips < <(get_openvpn_user_ips 2>/dev/null || echo "")
    else
        openvpn_ips=()
    fi

    if declare -f get_wireguard_user_ips > /dev/null; then
        mapfile -t wireguard_ips < <(get_wireguard_user_ips 2>/dev/null || echo "")
    else
        wireguard_ips=()
    fi

    all_ips=("${ssh_ips[@]}" "${dropbear_ips[@]}" "${openvpn_ips[@]}" "${wireguard_ips[@]}")
    total_connected=$(printf "%s\n" "${all_ips[@]}" | awk '{print $2}' | sort -u | wc -l)

    SSH_USERS_COUNT=$(awk -F: '/\/home\// {print $1}' /etc/passwd | wc -l)

    echo -e "${CYAN}+======================================================+${RESET}"
    echo -e "${BOLD}${MAGENTA}|                  🚀 KIGHMU MANAGER 🇨🇲 🚀           |${RESET}"
    echo -e "${CYAN}+======================================================+${RESET}"

    printf " OS: %-20s | IP: %-15s\n" "$OS_INFO" "$IP"
    
    echo -e "${CYAN} Taille RAM: ${GREEN}$TOTAL_RAM${RESET}"
    echo -e "${CYAN} CPU fréquence: ${YELLOW}$CPU_FREQ${RESET}"
    printf " RAM utilisée: ${GREEN}%-6s${RESET} | CPU utilisé: ${YELLOW}%-6s${RESET}\n" "$RAM_USAGE" "$CPU_USAGE"

    echo -e "${CYAN}+======================================================+${RESET}"

    printf " Utilisateurs SSH: ${BLUE}%-4d${RESET} | Appareils connectés: ${MAGENTA}%-4d${RESET}\n" "$SSH_USERS_COUNT" "$total_connected"

    echo -e "${CYAN}+======================================================+${RESET}"

    echo -e "${BOLD}${YELLOW}|                    MENU PRINCIPAL:                 |${RESET}"
    echo -e "${CYAN}+======================================================+${RESET}"
    echo -e "${GREEN}${BOLD}[01]${RESET} ${YELLOW}Créer un utilisateur SSH${RESET}"
    echo -e "${GREEN}${BOLD}[02]${RESET} ${YELLOW}Créer un test utilisateur${RESET}"
    echo -e "${GREEN}${BOLD}[03]${RESET} ${YELLOW}Voir les utilisateurs en ligne${RESET}"
    echo -e "${GREEN}${BOLD}[04]${RESET} ${YELLOW}Modifier durée / mot de passe utilisateur${RESET}"
    echo -e "${GREEN}${BOLD}[05]${RESET} ${YELLOW}Supprimer un utilisateur${RESET}"
    echo -e "${GREEN}${BOLD}[06]${RESET} ${YELLOW}Message du serveur${RESET}"
    echo -e "${GREEN}${BOLD}[07]${RESET} ${YELLOW}Installation de mode${RESET}"
    echo -e "${GREEN}${BOLD}[08]${RESET} ${YELLOW}V2ray slowdns mode${RESET}"
    echo -e "${GREEN}${BOLD}[09]${RESET} ${YELLOW}Désinstaller le script${RESET}"
    echo -e "${GREEN}${BOLD}[10]${RESET} ${YELLOW}Blocage de torrents${RESET}"
    echo -e "${RED}[00] Quitter${RESET}"
    echo -e "${CYAN}+======================================================+${RESET}"
    echo -ne "${BOLD}${YELLOW} Entrez votre choix [1-10]: ${RESET}"
    read -r choix
    echo -e "${CYAN}+------------------------------------------------------+${RESET}"

    case $choix in
        1) bash "$SCRIPT_DIR/menu1.sh" ;;
        2) bash "$SCRIPT_DIR/menu2.sh" ;;
        3) bash "$SCRIPT_DIR/menu3.sh" ;;
        4) bash "$SCRIPT_DIR/menu_4.sh" ;;
        5) bash "$SCRIPT_DIR/menu4.sh" ;;
        6) bash "$SCRIPT_DIR/menu4_2.sh" ;;  # Assurez-vous que c'est le bon script banner
        7) bash "$SCRIPT_DIR/menu5.sh" ;;
        8) bash "$SCRIPT_DIR/menu_5.sh" ;;
        9)
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
        10) bash "$SCRIPT_DIR/menu7.sh" ;;
        00)
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
