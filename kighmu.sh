#!/bin/bash

# Kighmu VPS Manager - Version complète avec couleurs et titre stylé

# Couleurs ANSI
DARK_BOLD="\033[1;30m"
BLUE="\033[1;34m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RESET="\033[0m"

# Récupérer le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while true; do
    clear

    # Titre en grand et gras foncé avec figlet si disponible
    if command -v figlet >/dev/null 2>&1; then
        figlet -c "KIGHMU MANAGER" | while IFS= read -r line; do
            echo -e "${DARK_BOLD}${line}${RESET}"
        done
    else
        echo -e "${DARK_BOLD}+==================================================+${RESET}"
        echo -e "${DARK_BOLD}|            K I G H M U   M A N A G E R           |${RESET}"
        echo -e "${DARK_BOLD}+==================================================+${RESET}"
    fi

    # Récupération infos système
    IP=$(hostname -I | awk '{print $1}')
    RAM_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }')
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{printf "%.2f%%", $2+$4}')

    # Fonctions compter utilisateurs et appareils (adapter chemins)
    get_users_count() {
      ls /etc/xray/users/ 2>/dev/null | wc -l
    }

    get_devices_count() {
      netstat -ntu | grep ESTABLISHED | wc -l
    }

    USERS_COUNT=$(get_users_count)
    DEVICES_COUNT=$(get_devices_count)

    echo -e "${GREEN} IP: ${RESET}${IP} ${GREEN}| RAM utilisée: ${RESET}${RAM_USAGE} ${GREEN}| CPU utilisé: ${RESET}${CPU_USAGE}"
    echo -e "${YELLOW}+--------------------------------------------------+${RESET}"
    echo -e "${YELLOW}|                  ${BLUE}MENU PRINCIPAL${RESET}                  ${YELLOW}|${RESET}"
    echo -e "${YELLOW}+--------------------------------------------------+${RESET}"
    echo -e "${GREEN}|${RESET} [01] Créer un utilisateur                        ${GREEN}|${RESET}"
    echo -e "${GREEN}|${RESET}  Créer un test utilisateur                   ${GREEN}|${RESET}"
    echo -e "${GREEN}|${RESET}  Voir les utilisateurs en ligne              ${GREEN}|${RESET}"
    echo -e "${GREEN}|${RESET}  Supprimer utilisateur                       ${GREEN}|${RESET}"
    echo -e "${GREEN}|${RESET}  Installation de mode                        ${GREEN}|${RESET}"
    echo -e "${GREEN}|${RESET}  Xray mode                                   ${GREEN}|${RESET}"
    echo -e "${GREEN}|${RESET}  Désinstaller le script                      ${GREEN}|${RESET}"
    echo -e "${GREEN}|${RESET}  Blocage de torrents                         ${GREEN}|${RESET}"
    echo -e "${GREEN}|${RESET}  Quitter                                     ${GREEN}|${RESET}"
    echo -e "${YELLOW}+--------------------------------------------------+${RESET}"
    echo -ne "${BLUE}Entrez votre choix [1-9] : ${RESET}"

    read -r choix

    case $choix in
      1) bash "$SCRIPT_DIR/menu1.sh" ;;
      2) bash "$SCRIPT_DIR/menu2.sh" ;;
      3) bash "$SCRIPT_DIR/menu3.sh" ;;
      4) bash "$SCRIPT_DIR/menu4.sh" ;;
      5) bash "$SCRIPT_DIR/menu5.sh" ;;
      6) bash "$SCRIPT_DIR/menu_6.sh" ;;
      7) bash "$SCRIPT_DIR/menu7.sh" ;;
      8) bash "$SCRIPT_DIR/menu8.sh" ;;
      9) echo "Au revoir !" ; exit 0 ;;
      *) echo -e "${RED}Choix invalide !${RESET}" ;;
    esac

    read -p "Appuyez sur Entrée pour revenir au menu..."
done
