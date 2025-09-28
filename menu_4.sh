#!/bin/bash
# menu_4.sh - Modifier la durée ou le mot de passe d'un utilisateur

# Couleurs pour l'interface
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

USER_FILE="/etc/kighmu/users.list"

clear
echo -e "${CYAN}+--------------------------------------------+${RESET}"
echo             "|          MODIFIER DUREE / MOT DE PASSE    |"
echo -e "${CYAN}+--------------------------------------------+${RESET}"

if [ ! -f "$USER_FILE" ]; then
    echo -e "${RED}Aucun utilisateur trouvé.${RESET}"
    read -p "Appuyez sur Entrée pour revenir au menu..."
    exit 0
fi

echo -e "${BOLD}Utilisateurs existants :${RESET}"
cut -d'|' -f1 "$USER_FILE"

echo
read -p "Nom de l'utilisateur à modifier : " username

# Vérification que l'utilisateur est dans la liste
user_line=$(grep "^$username|" "$USER_FILE")
if [ -z "$user_line" ]; then
    echo -e "${RED}Utilisateur ${username} introuvable dans la liste.${RESET}"
    read -p "Appuyez sur Entrée pour revenir au menu..."
    exit 1
fi

# Affichage du menu des actions possibles avec style numéros entre crochets
echo
echo -e "${GREEN}${BOLD}[01]${RESET} ${YELLOW}Durée d'expiration du compte${RESET}"
echo -e "${GREEN}${BOLD}[02]${RESET} ${YELLOW}Mot de passe${RESET}"
echo -e "${GREEN}${BOLD}[00]${RESET} ${YELLOW}Retour au menu${RESET}"

read -p "Entrez votre choix [00-02] : " choice

# Récupération des champs actuels pour mise à jour
IFS="|" read -r user pass limite expire_date hostip domain slowdns_ns <<< "$user_line"

case $choice in
    1|01)
        echo
        read -p "Nouvelle durée d'expiration (en jours, 0 pour pas d'expiration) : " new_limit
        if ! [[ "$new_limit" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Valeur invalide.${RESET}"
            read -p "Appuyez sur Entrée pour revenir au menu..."
            exit 1
        fi
        # Calcul de la nouvelle date d'expiration si > 0
        if [ "$new_limit" -eq 0 ]; then
            new_expire="none"
        else
            new_expire=$(date -d "+$new_limit days" +%Y-%m-%d)
        fi

        # Mise à jour de la ligne dans le fichier users.list
        new_line="${user}|${pass}|${new_limit}|${new_expire}|${hostip}|${domain}|${slowdns_ns}"
        sed -i "s/^$user|.*/$new_line/" "$USER_FILE"

        echo -e "${GREEN}Durée modifiée avec succès.${RESET}"
        ;;
    2|02)
        echo
        # Lecture du mot de passe sans l'afficher
        read -s -p "Nouveau mot de passe : " pass1
        echo
        read -s -p "Confirmez le mot de passe : " pass2
        echo
        if [ "$pass1" != "$pass2" ]; then
            echo -e "${RED}Les mots de passe ne correspondent pas.${RESET}"
            read -p "Appuyez sur Entrée pour revenir au menu..."
            exit 1
        fi

        # Mise à jour du mot de passe dans le user_file (à adapter selon format de hash)
        new_line="${user}|${pass1}|${limite}|${expire_date}|${hostip}|${domain}|${slowdns_ns}"
        sed -i "s/^$user|.*/$new_line/" "$USER_FILE"

        # Mise à jour du mot de passe système (avec sudo)
        echo -e "$pass1\n$pass1" | sudo passwd "$user" >/dev/null 2>&1

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Mot de passe modifié avec succès.${RESET}"
        else
            echo -e "${RED}Erreur lors de la modification du mot de passe système.${RESET}"
        fi
        ;;
    0|00)
        echo "Retour au menu..."
        exit 0
        ;;
    *)
        echo -e "${RED}Choix invalide.${RESET}"
        ;;
esac

read -p "Appuyez sur Entrée pour revenir au menu..."
