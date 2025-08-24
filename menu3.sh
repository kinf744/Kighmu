#!/bin/bash
# menu3.sh - Affichage des utilisateurs en ligne avec limites

USER_FILE="/etc/kighmu/users.list"
WIDTH=60

# Couleurs
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# Fonctions d'affichage
line_full() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
center_line() {
    local text="$1"
    local padding=$(( (WIDTH - ${#text}) / 2 ))
    printf "|%*s%s%*s|\n" "$padding" "" "$text" "$padding" ""
}
content_line() { printf "| %-56s |\n" "$1"; }

# Vérifier existence du fichier utilisateur
if [ ! -f "$USER_FILE" ]; then
    clear
    line_full
    center_line "${RED}AUCUN UTILISATEUR TROUVÉ${RESET}"
    line_full
    read -p "Appuyez sur Entrée pour revenir au menu..."
    exit 0
fi

# Fonction pour compter les connexions SSH/Dropbear/UDP/SOCKS
connected_count() {
    local user="$1"
    who | awk '{print $1}' | grep -c "^$user$"
}

# Affichage panneau principal
clear
line_full
center_line "${YELLOW}UTILISATEURS EN LIGNE${RESET}"
line_full
printf "| %-5s %-20s %-15s %-10s |\n" "No." "Utilisateur" "Connectés" "Limite"
line_simple

i=1
while IFS="|" read -r username password limite expire_date rest; do
    if [ -z "$username" ]; then
        continue
    fi
    connected=$(connected_count "$username")
    printf "| %-5s %-20s %-15s %-10s |\n" "$i" "$username" "$connected" "$limite"
    i=$((i+1))
done < "$USER_FILE"

line_full
read -p "Appuyez sur Entrée pour revenir au menu..."
