#!/bin/bash
# menu3.sh
# Afficher les utilisateurs en ligne avec nombre de connexions et consommation (Go)

# Couleurs
RESET="\e[0m"
BOLD="\e[1m"
CYAN="\e[36m"
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
MAGENTA="\e[35m"

WIDTH=70

line_full() {
    echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"
}

line_simple() {
    echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"
}

center_line() {
    local text="$1"
    local padding=$(( (WIDTH - ${#text}) / 2 ))
    printf "|%*s${BOLD}${MAGENTA}%s${RESET}%*s|\n" $padding "" "$text" $padding ""
}

USER_FILE="/etc/kighmu/users.list"

# Vérifier si le fichier existe
if [ ! -f "$USER_FILE" ]; then
    echo -e "${RED}Aucun utilisateur trouvé.${RESET}"
    exit 1
fi

# Vérifier ou créer la chaîne TRAFFIC
if ! iptables -L TRAFFIC &>/dev/null; then
    iptables -N TRAFFIC
else
    iptables -F TRAFFIC
fi

# Boucle d’affichage en temps réel
while true; do
    clear
    line_full
    center_line "UTILISATEURS EN LIGNE - EN TEMPS RÉEL"
    line_full
    printf "| %-15s %-10s %-10s |\n" "UTILISATEUR" "CONNECTÉS" "CONSOMMÉ (Go)"
    line_simple

    while IFS="|" read -r username password limite expire_date rest; do
        # Compter le nombre de connexions pour l'utilisateur
        connected=$(who | awk '{print $1}' | grep -c "^$username$")

        # Récupérer le trafic consommé depuis iptables (en Go)
        bytes=$(iptables -L TRAFFIC -v -n | grep "$username" | awk '{sum += $2} END {print sum}')
        bytes=${bytes:-0}
        gigabytes=$(echo "scale=2; $bytes/1024/1024/1024" | bc)

        printf "| %-15s %-10s %-10s |\n" "$username" "$connected" "$gigabytes"
    done < "$USER_FILE"

    line_full
    echo -e "${YELLOW}Actualisation toutes les 3 secondes. Appuyez sur Ctrl+C pour quitter ou q pour revenir au menu principal.${RESET}"
    
    # Attendre 3 secondes ou lecture de 'q' pour quitter
    read -t 3 -n 1 key
    if [[ $key == "q" ]]; then
        break
    fi
done

# Retour au menu principal
bash /chemin/vers/kighmu.sh
