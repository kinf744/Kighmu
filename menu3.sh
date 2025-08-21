#!/bin/bash
# menu3_color.sh
# Afficher les utilisateurs en ligne avec nombre d'appareils et limite

# Couleurs
RESET="\e[0m"
BOLD="\e[1m"
CYAN="\e[36m"
MAGENTA="\e[35m"
YELLOW="\e[33m"
GREEN="\e[32m"

USER_FILE="/etc/kighmu/users.list"
WIDTH=50

line_full() {
    echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"
}

center_line() {
    local text="$1"
    local padding=$(( (WIDTH - ${#text}) / 2 ))
    printf "|%*s%s%*s|\n" $padding "" "$text" $padding ""
}

line_simple() {
    echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"
}

# Cadre en-tête
line_full
center_line "${BOLD}${MAGENTA}UTILISATEURS EN LIGNE${RESET}"
line_full

# Vérification du fichier
if [ ! -f "$USER_FILE" ]; then
    center_line "${RED}Aucun utilisateur trouvé${RESET}"
    line_full
    exit 0
fi

# Affichage tableau
printf "| %-15s %-10s %-10s |\n" "UTILISATEUR" "CONNECTÉS" "LIMITE"
line_simple

while IFS="|" read -r username password limite expire_date rest; do
    # Compter le nombre de connexions SSH/Dropbear/UDP/SOCKS pour cet utilisateur
    connected=$(who | awk '{print $1}' | grep -c "^$username$")
    
    printf "| %-15s %-10s %-10s |\n" "$username" "$connected" "$limite"
done < "$USER_FILE"

line_full
