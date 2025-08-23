#!/bin/bash
# menu1.sh - Création d'un utilisateur SSH avec panneau dynamique

USER_FILE="/etc/kighmu/users.list"

# Couleurs
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

draw_frame() {
    local text="$1"
    local width=60
    echo -e "${CYAN}+$(printf '%.0s-' $(seq 1 $width))+${RESET}"
    printf "|%*s%*s|\n" $(( (width + ${#text})/2 )) "$text" $(( (width - ${#text})/2 )) ""
    echo -e "${CYAN}+$(printf '%.0s-' $(seq 1 $width))+${RESET}"
}

clear
draw_frame "${YELLOW}${BOLD}CRÉATION D'UTILISATEUR SSH${RESET}"

# Demande des informations
read -p "Nom d'utilisateur : " username
read -s -p "Mot de passe : " password
echo ""
read -p "Nombre d'appareils autorisés : " limite
read -p "Durée de validité (en minutes) : " minutes

expire_date=$(date -d "+$minutes minutes" '+%Y-%m-%d %H:%M:%S')

# Création utilisateur système
useradd -M -s /bin/false "$username"
echo "$username:$password" | chpasswd

# Sauvegarde dans le fichier users.list
mkdir -p /etc/kighmu
touch "$USER_FILE"
chmod 600 "$USER_FILE"
echo "$username|$password|$limite|$expire_date" >> "$USER_FILE"

# Affichage résumé
draw_frame "${GREEN}${BOLD}RÉSUMÉ DE L'UTILISATEUR${RESET}"
echo -e "${CYAN}Utilisateur:${RESET} $username"
echo -e "${CYAN}Mot de passe:${RESET} $password"
echo -e "${CYAN}Limite appareils:${RESET} $limite"
echo -e "${CYAN}Date d'expiration:${RESET} $expire_date"
draw_frame "${GREEN}${BOLD}COMPTE CRÉÉ AVEC SUCCÈS${RESET}"
