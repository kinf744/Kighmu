#!/bin/bash
# ==============================================
# menu3.sh - Voir les utilisateurs en ligne
# ==============================================

WIDTH=60

# Couleurs pour lignes
CYAN="\e[36m"
RESET="\e[0m"

# Fonctions d'affichage
line_full() { echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
content_line() { printf "| %-56s |\n" "$1"; }

center_line() {
    local text="$1"
    local clean_text=$(echo -e "$text" | sed 's/\x1B\[[0-9;]*[mK]//g')
    local padding=$(( (WIDTH - ${#clean_text}) / 2 ))
    printf "|%*s%s%*s|\n" "$padding" "" "$text" "$padding" ""
}

# Début du panneau
clear
line_full
center_line "UTILISATEURS EN LIGNE"
line_full

# Liste des utilisateurs SSH
ssh_users=$(awk -F: '/\/home/ {print $1}' /etc/passwd)

if [ -z "$ssh_users" ]; then
    center_line "Aucun utilisateur SSH trouvé"
else
    line_simple
    printf "| %-4s %-20s %-15s %-15s |\n" "No." "Utilisateur" "Connecté" "Expiré"
    line_simple

    i=1
    for u in $ssh_users; do
        # Vérifie si l'utilisateur est connecté
        if who | awk '{print $1}' | grep -qw "$u"; then
            connected="Oui"
        else
            connected="Non"
        fi

        # Date d'expiration
        expire_date=$(chage -l "$u" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
        [ -z "$expire_date" ] && expire_date="Jamais"

        printf "| %-4s %-20s %-15s %-15s |\n" "$i" "$u" "$connected" "$expire_date"
        i=$((i+1))
    done
    line_simple
fi

echo ""
read -p "Appuyez sur Entrée pour revenir au menu..."
