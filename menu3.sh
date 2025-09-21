#!/bin/bash
# menu3.sh
# Afficher nom d'utilisateur, limite, et nombre total d'appareils connectés (méthode DarkSSH)

# Couleurs pour cadre et mise en forme
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

USER_FILE="/etc/kighmu/users.list"

clear
echo -e "${CYAN}+==============================================+${RESET}"
echo -e "|            UTILISATEURS ET CONNEXIONS        |"
echo -e "${CYAN}+==============================================+${RESET}"

if [ ! -f "$USER_FILE" ]; then
    echo -e "${RED}Aucun utilisateur trouvé.${RESET}"
    exit 0
fi

printf "${BOLD}%-20s %-10s %-10s${RESET}\n" "UTILISATEUR" "LIMITÉ" "APPAREILS"
echo -e "${CYAN}----------------------------------------------${RESET}"

while IFS="|" read -r username password limite expire_date hostip domain slowdns_ns; do
    
    # Compter connexions sshd pour cet utilisateur
    ssh_connexions=$(ps aux | grep "sshd: $username@" | grep -v grep | wc -l)
    
    # Affichage utilisateur, limite, nombre de connexions
    printf "%-20s %-10s %-10d\n" "$username" "$limite" "$ssh_connexions"

done < "$USER_FILE"

echo -e "${CYAN}+==============================================+${RESET}"

read -p "Appuyez sur Entrée pour revenir au menu..."
