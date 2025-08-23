#!/bin/bash
# ==============================================
# menu_4.sh - Gestion des utilisateurs SSH
# Version panneau de contrôle dynamique avec dates en couleur
# ==============================================

# Vérifier si l'utilisateur est root
[ "$(id -u)" -ne 0 ] && { echo -e "\e[31m[ERREUR]\e[0m Veuillez exécuter ce script en root."; exit 1; }

# Couleurs
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

WIDTH=60

# Fonctions pour le cadre
line_full() { echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
content_line() { printf "| %-56s |\n" "$1"; }
center_line() { local text="$1"; local padding=$(( (WIDTH - ${#text}) / 2 )); printf "|%*s%s%*s|\n" "$padding" "" "$text" "$padding" ""; }

# Fonction pour afficher les utilisateurs avec expiration en couleur
show_users() {
    users=$(awk -F: '/\/home/ {print $1}' /etc/passwd)
    line_simple
    content_line "No.  Utilisateur           Expiration"
    line_simple
    i=1
    today=$(date +%s)
    for u in $users; do
        expire_date=$(chage -l "$u" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
        [ -z "$expire_date" ] && expire_date="Jamais"
        if [[ "$expire_date" != "Jamais" ]]; then
            exp_seconds=$(date -d "$expire_date" +%s 2>/dev/null)
            if [ "$exp_seconds" -lt "$today" ]; then
                expire_color="$RED$expire_date$RESET"
            else
                expire_color="$GREEN$expire_date$RESET"
            fi
        else
            expire_color="$GREEN$expire_date$RESET"
        fi
        printf "| %-4s %-20s %-25b |\n" "$i" "$u" "$expire_color"
        i=$((i+1))
    done
    line_simple
}

while true; do
    clear
    line_full
    center_line "${GREEN}GESTION DES UTILISATEURS SSH${RESET}"
    line_full

    show_users
    content_line "0) Retour au menu principal"
    line_simple

    echo -ne "Sélectionnez un utilisateur (numéro) : "
    read user_choice

    [ "$user_choice" == "0" ] && exit 0

    # Vérifier choix valide
    selected_user=$(awk -F: '/\/home/ {print $1}' /etc/passwd | sed -n "${user_choice}p")
    [ -z "$selected_user" ] && { echo -e "${RED}Choix invalide !${RESET}"; sleep 2; continue; }

    while true; do
        clear
        line_full
        center_line "${GREEN}UTILISATEUR SÉLECTIONNÉ: $selected_user${RESET}"
        line_full
        content_line "1) Modifier le mot de passe"
        content_line "2) Modifier la durée/expiration"
        content_line "0) Retour"
        line_simple
        echo -ne "Votre choix : "
        read action_choice

        case $action_choice in
            1)
                echo -ne "Entrez le nouveau mot de passe : "
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
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            2)
                echo -ne "Entrez la nouvelle durée (en jours) : "
                read days
                if [[ "$days" =~ ^[0-9]+$ ]]; then
                    chage -E $(date -d "+$days days" +"%Y-%m-%d") "$selected_user"
                    echo -e "${GREEN}Expiration modifiée avec succès !${RESET}"
                else
                    echo -e "${RED}Durée invalide.${RESET}"
                fi
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            0) break ;;
            *) echo -e "${RED}Choix invalide !${RESET}" ; sleep 2 ;;
        esac
    done
done
