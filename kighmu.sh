#!/bin/bash
# ==============================================
# Kighmu VPS Manager
# Copyright (c) 2025 Kinf744
# Licence MIT (version française)
# Voir le fichier LICENSE pour plus de détails
# ==============================================

# Couleurs ANSI
BG_BLUE="\e[44m"
FG_WHITE="\e[97m"
FG_CYAN="\e[96m"
RESET="\e[0m"
BOLD="\e[1m"

# Largeur cadre
WIDTH=44

# Fonction affiche ligne vide dans cadre
empty_line() {
    echo -e "${BG_BLUE}${FG_WHITE}|${RESET}$(printf "%-${WIDTH}s" " ")${BG_BLUE}${FG_WHITE}|${RESET}"
}

# Fonction affiche ligne centrée dans cadre
center_line() {
    local text="$1"
    local padding=$(( (WIDTH - ${#text}) / 2 ))
    local line=$(printf "%${padding}s%s%$((WIDTH - padding - ${#text}))s" " " "$text" " ")
    echo -e "${BG_BLUE}${FG_WHITE}|${RESET}${line}${BG_BLUE}${FG_WHITE}|${RESET}"
}

# Récupérer le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while true; do
    clear

    echo -e "${BG_BLUE}${FG_WHITE}${BOLD}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"
    center_line "K I G H M U   M A N A G E R"
    echo -e "${BG_BLUE}${FG_WHITE}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"

    # Récupération IP, RAM et CPU
    IP=$(hostname -I | awk '{print $1}')
    RAM_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }')
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{printf "%.2f%%", $2+$4}')

    center_line "${FG_CYAN}IP: $IP | RAM utilisée: $RAM_USAGE | CPU utilisé: $CPU_USAGE${FG_WHITE}"

    echo -e "${BG_BLUE}${FG_WHITE}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"
    empty_line

    center_line "MENU PRINCIPAL:"
    empty_line

    center_line "1. Créer un utilisateur"
    center_line "2. Créer un test utilisateur"
    center_line "3. Voir les utilisateurs en ligne"
    center_line "4. Supprimer utilisateur"
    center_line "5. Installation de mode"
    center_line "6. Désinstaller le script"
    center_line "7. Blocage de torrents"
    center_line "8. Quitter"

    empty_line
    echo -ne "${BG_BLUE}${FG_CYAN} $(printf "%-${WIDTH}s" "Entrez votre choix [1-8]: ")${RESET}"
    read choix

    case $choix in
      1) bash "$SCRIPT_DIR/menu1.sh" ;;
      2) bash "$SCRIPT_DIR/menu2.sh" ;;
      3) bash "$SCRIPT_DIR/menu3.sh" ;;
      4) bash "$SCRIPT_DIR/menu4.sh" ;;
      5) bash "$SCRIPT_DIR/menu5.sh" ;;
      6) bash "$SCRIPT_DIR/menu6.sh" ;;
      7) bash "$SCRIPT_DIR/menu7.sh" ;;
      8) echo -e "\nAu revoir !${RESET}" ; exit 0 ;;
      *) echo -e "\nChoix invalide !${RESET}" ;;
    esac

    read -p "Appuyez sur Entrée pour revenir au menu..."
done
