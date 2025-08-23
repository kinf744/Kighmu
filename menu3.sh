#!/bin/bash
# menu3.sh
# Afficher les utilisateurs en ligne avec nombre d'appareils et limite

USER_FILE="/etc/kighmu/users.list"

# Couleur bleu marine pour les cadres
BLUE="\e[34m"
RESET="\e[0m"

# Fonction pour encadrer un texte
draw_frame() {
    local text="$1"
    local width=60
    echo -e "${BLUE}+$(printf '%.0s-' $(seq 1 $width))+${RESET}"
    printf "|%*s%*s|\n" $(( (width + ${#text})/2 )) "$text" $(( (width - ${#text})/2 )) ""
    echo -e "${BLUE}+$(printf '%.0s-' $(seq 1 $width))+${RESET}"
}

# Affichage du panneau d’accueil
clear
draw_frame "PANEL UTILISATEURS EN LIGNE"

if [ ! -f "$USER_FILE" ]; then
    echo "Aucun utilisateur trouvé."
    draw_frame "FIN DE LA LISTE"
    exit 0
fi

# En-tête du tableau encadré
draw_frame "UTILISATEUR       CONNECTÉS       LIMITE"

# Parcourir la liste des utilisateurs
while IFS="|" read -r username password limite expire_date rest; do
    # Compter le nombre de connexions SSH/Dropbear/UDP/SOCKS pour cet utilisateur
    connected=$(who | awk '{print $1}' | grep -c "^$username$")
    
    printf "| %-16s | %-13s | %-6s |\n" "$username" "$connected" "$limite"
done < "$USER_FILE"

# Ligne de séparation et fin du panneau
echo -e "${BLUE}+------------------------------------------------------------+${RESET}"
draw_frame "FIN DE LA LISTE DES UTILISATEURS"
