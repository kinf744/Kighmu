#!/bin/bash
# kighmu-manager.sh
# Panneau principal KIGHMU MANAGER

# Charger la configuration globale si elle existe
if [ -f ./config.sh ]; then
    source ./config.sh
fi

# Codes couleurs ANSI pour style
BG_BLUE="\e[44m"
FG_WHITE="\e[97m"
FG_CYAN="\e[96m"
RESET="\e[0m"
BOLD="\e[1m"
WIDTH=44

# Fonction pour afficher une ligne vide dans le cadre
empty_line() {
    echo -e "${BG_BLUE}${FG_WHITE}|${RESET}$(printf "%-${WIDTH}s" " ")${BG_BLUE}${FG_WHITE}|${RESET}"
}

# Fonction pour afficher une ligne de texte centrée dans le cadre
center_line() {
    local text="$1"
    local padding=$(( (WIDTH - ${#text}) / 2 ))
    local line=$(printf "%${padding}s%s%$((WIDTH - padding - ${#text}))s" " " "$text" " ")
    echo -e "${BG_BLUE}${FG_WHITE}|${RESET}${line}${BG_BLUE}${FG_WHITE}|${RESET}"
}

# Nouvelle fonction affichage système stylée
display_system_info() {
    IP=$(curl -s https://api.ipify.org)
    RAM_USAGE=$(free -m | awk 'NR==2{printf "%.2f", $3*100/$2 }')
    CPU_USAGE=$(mpstat 1 1 | awk '/Average/ {printf "%.2f", 100-$12}')
    
    echo -e "${BG_BLUE}${FG_WHITE}${BOLD}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"
    center_line "K I G H M U   M A N A G E R"
    echo -e "${BG_BLUE}${FG_WHITE}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"

    info="IP: $IP | RAM: ${RAM_USAGE}% | CPU: ${CPU_USAGE}%"
    center_line "${FG_CYAN}${info}${FG_WHITE}"

    echo -e "${BG_BLUE}${FG_WHITE}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"
    empty_line
}

# Fonction menu principal modifiée pour cadre
main_menu() {
    while true; do
        display_system_info
        center_line "MENU PRINCIPAL:"
        empty_line

        center_line "1. Créer un utilisateur"
        center_line "2. Créer un test utilisateur"
        center_line "3. Voir les utilisateurs en ligne"
        center_line "4. Supprimer utilisateur"
        center_line "5. Installation de modes spéciaux"
        center_line "6. Désinstaller le script"
        center_line "7. Blocage de torrents"
        center_line "8. Quitter"

        empty_line
        echo -e "${BG_BLUE}${FG_CYAN}$(printf "%-${WIDTH}s" " Entrez votre choix [1-8]: ")${RESET}"
        read -p "> " choice

        case $choice in
            1) ./menu1.sh ;;
            2) ./menu2.sh ;;
            3) ./menu3.sh ;;
            4) ./menu4.sh ;;
            5) ./install_modes.sh ;;
            6) ./menu6.sh ;;
            7) ./menu7.sh ;;
            8) echo "Au revoir !"; exit 0 ;;
            *) echo "Choix invalide. Réessayez." ;;
        esac
        echo ""
        read -p "Appuyez sur Entrée pour revenir au menu principal..."
        clear
    done
}

# Lancer le menu principal
clear
main_menu
