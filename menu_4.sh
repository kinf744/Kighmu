#!/bin/bash
# ==============================================
# menu_4.sh - Gestion des utilisateurs SSH
# ==============================================

# Vérifier si l'utilisateur est root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "\e[31m[ERREUR]\e[0m Veuillez exécuter ce script en root."
    exit 1
fi

# Couleurs
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

# Récupérer tous les utilisateurs SSH (/home)
users=$(awk -F: '/\/home/ {print $1}' /etc/passwd)

while true; do
    clear
    echo -e "${CYAN}+=====================================+${RESET}"
    echo -e "${GREEN}      Gestion des utilisateurs SSH     ${RESET}"
    echo -e "${CYAN}+=====================================+${RESET}"
    
    # Affichage des utilisateurs avec expiration
    printf "%-4s %-20s %-15s\n" "No." "Utilisateur" "Expiration"
    echo "-----------------------------------------"
    i=1
    for u in $users; do
        expire_date=$(chage -l "$u" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
        [ -z "$expire_date" ] && expire_date="Jamais"
        printf "%-4s %-20s %-15s\n" "$i" "$u" "$expire_date"
        i=$((i+1))
    done
    
    echo -e "${CYAN}+-------------------------------------+${RESET}"
    echo -e "${YELLOW}[0] Retour au menu principal${RESET}"
    echo -ne "Sélectionnez un utilisateur (numéro) : "
    read user_choice

    if [ "$user_choice" == "0" ]; then
        exit 0
    fi

    # Vérifier choix valide
    selected_user=$(echo "$users" | sed -n "${user_choice}p")
    if [ -z "$selected_user" ]; then
        echo -e "${RED}Choix invalide !${RESET}"
        sleep 2
        continue
    fi

    # Menu pour cet utilisateur
    echo -e "${CYAN}+-------------------------------------+${RESET}"
    echo -e "Utilisateur sélectionné : ${GREEN}$selected_user${RESET}"
    echo -e "[1] Modifier le mot de passe"
    echo -e "[2] Modifier la durée/expiration"
    echo -e "[0] Retour"
    echo -ne "Votre choix : "
    read action_choice

    case $action_choice in
        1)
            echo -ne "Entrez le nouveau mot de passe pour $selected_user : "
            read -s new_pass
            echo
            echo -ne "Confirmez le mot de passe : "
            read -s new_pass2
            echo
            if [ "$new_pass" == "$new_pass2" ]; then
                echo "$selected_user:$new_pass" | chpasswd
                echo -e "${GREEN}Mot de passe modifié avec succès !${RESET}"
            else
                echo -e "${RED}Les mots de passe ne correspondent pas.${RESET}"
            fi
            sleep 2
            ;;
        2)
            echo -ne "Entrez la nouvelle durée (en jours) pour $selected_user : "
            read days
            if [[ "$days" =~ ^[0-9]+$ ]]; then
                chage -E $(date -d "+$days days" +"%Y-%m-%d") "$selected_user"
                echo -e "${GREEN}Expiration modifiée avec succès !${RESET}"
            else
                echo -e "${RED}Durée invalide.${RESET}"
            fi
            sleep 2
            ;;
        0) continue ;;
        *) echo -e "${RED}Choix invalide !${RESET}" ; sleep 2 ;;
    esac
done
