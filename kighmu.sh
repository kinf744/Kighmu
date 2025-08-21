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

# Fonction pour compter les utilisateurs (adapte le chemin selon ta gestion)
get_users_count() {
  ls /etc/xray/users/ 2>/dev/null | wc -l
}

# Fonction pour compter les appareils connectés (adapte selon ta méthode)
get_devices_count() {
  ss -ntu state established 2>/dev/null | wc -l
}

# Fonction pour CPU usage plus précis
get_cpu_usage() {
  grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.2f%%", usage}'
}

while true; do
    clear
    IP=$(hostname -I | awk '{print $1}')
    RAM_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }')
    CPU_USAGE=$(get_cpu_usage)
    USERS_COUNT=$(get_users_count)
    DEVICES_COUNT=$(get_devices_count)

    echo -e "${CYAN}+==================================================+${RESET}"
    echo -e "${BOLD}${MAGENTA}|                🚀 KIGHMU MANAGER 🚀               |${RESET}"
    echo -e "${CYAN}+==================================================+${RESET}"
    printf "${GREEN} IP: %-17s${RESET}| ${YELLOW}RAM utilisée:${RESET} %-7s \n" "$IP" "$RAM_USAGE"
    printf "${BLUE} CPU utilisé: %-38s${RESET}\n" "$CPU_USAGE"
    echo -e "${CYAN}+--------------------------------------------------+${RESET}"
    printf " ${MAGENTA}Utilisateurs créés:${RESET} %-4d | ${MAGENTA}Appareils:${RESET} %-6d \n" "$USERS_COUNT" "$DEVICES_COUNT"
    echo -e "${CYAN}+--------------------------------------------------+${RESET}"
    echo -e "${BOLD}${YELLOW}|                  MENU PRINCIPAL:                 |${RESET}"
    echo -e "${CYAN}+--------------------------------------------------+${RESET}"
    echo -e "${GREEN}[01]${RESET} Créer un utilisateur"
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
      6) bash "$SCRIPT_DIR/menu6.sh" ;;
      7) bash "$SCRIPT_DIR/menu7.sh" ;;
      8) bash "$SCRIPT_DIR/menu8.sh" ;;
      9) echo -e "${RED}Au revoir !${RESET}" ; exit 0 ;;
      *) echo -e "${RED}Choix invalide !${RESET}" ;;
    esac

    echo ""
    read -p "Appuyez sur Entrée pour revenir au menu..."
done
