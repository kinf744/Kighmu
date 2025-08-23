#!/bin/bash
# menu3.sh - Affichage des utilisateurs en ligne et de leur limite dans un panneau dynamique

USER_FILE="/etc/kighmu/users.list"
WIDTH=60

# Couleurs
CYAN="\e[36m"    # lignes
YELLOW="\e[33m"  # titres
RESET="\e[0m"

# Fonctions d'affichage
line_full() { echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
content_line() { printf "| %-56s |\n" "$1"; }
center_line() {
    local text="$1"
    local padding=$(( (WIDTH - ${#text}) / 2 ))
    printf "|%*s%s%*s|\n" "$padding" "" "$text" "$padding" ""
}

# Vérifier nombre de connexions actives pour un utilisateur
connected_count() {
    local user="$1"
    # Compte les connexions SSH/Dropbear/UDP/SOCKS
    who | awk '{print $1}' | grep -c "^$user$"
}

# Panneau d'accueil
clear
line_full
center_line "${YELLOW}UTILISATEURS EN LIGNE${RESET}"
line_full

if [ ! -f "$USER_FILE" ]; then
    content_line "Aucun utilisateur trouvé."
    line_full
    exit 0
fi

# En-tête tableau
line_simple
content_line "UTILISATEUR             CONNECTÉS   LIMITE"
line_simple

# Parcours des utilisateurs et affichage dynamique
while IFS="|" read -r username password limite expire_date rest; do
    count=$(connected_count "$username")
    content_line "$(printf '%-22s %-10s %-10s' "$username" "$count" "$limite")"
done < "$USER_FILE"

line_simple
center_line "${YELLOW}FIN DE LA LISTE DES UTILISATEURS${RESET}"
line_full
