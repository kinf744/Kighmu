#!/bin/bash
# ==============================================
# menu_4.sh - Gestion des utilisateurs SSH
# ==============================================

WIDTH=60
CYAN="\e[36m"
YELLOW="\e[33m"
GREEN="\e[32m"
RED="\e[31m"
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

# Vérification root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[ERREUR]${RESET} Veuillez exécuter ce script en root."
    exit 1
fi

while true; do
    clear
    line_full
    center_line "GESTION DES UTILISATEURS SSH"
    line_full

    # Liste des utilisateurs SSH
    users=($(awk -F: '/\/home/ {print $1}' /etc/passwd))
    if [ ${#users[@]} -eq 0 ]; then
        content_line "Aucun utilisateur SSH trouvé."
        line_full
        read -p "Appuyez sur Entrée pour revenir au menu..." dummy
        exit 0
    fi

    # Affichage des utilisateurs avec expiration
    content_line "No. Utilisateur        Expiration"
    line_simple
    i=1
    for u in "${users[@]}"; do
        expire_date=$(chage -l "$u" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
        [ -z "$expire_date" ] && expire_date="Jamais"
        content_line "$(printf "%-3s %-20s %-15s" "$i" "$u" "$expire_date")"
        i=$((i+1))
    done
    line_full
    content_line "0) Retour au menu principal"
    line_simple
    read -p "Sélectionnez un utilisateur (numéro) : " user_choice

    if [ "$user_choice" == "0" ]; then
        exit 0
    fi

    selected_user="${users[$((user_choice-1))]}"
    if [ -z "$selected_user" ]; then
        content_line "Choix invalide !"
        read -p "Appuyez sur Entrée pour continuer..." dummy
        continue
    fi

    # Menu pour l'utilisateur sélectionné
    while true; do
        clear
        line_full
        center_line "UTILISATEUR : $selected_user"
        line_full
        content_line "1) Modifier le mot de passe"
        content_line "2) Modifier la durée / expiration"
        content_line "0) Retour"
        line_simple
        read -p "Votre choix : " action_choice

        case $action_choice in
            1)
                read -s -p "Nouveau mot de passe : " new_pass
                echo
                read -s -p "Confirmez le mot de passe : " new_pass2
                echo
                if [ "$new_pass" == "$new_pass2" ]; then
                    echo "$selected_user:$new_pass" | chpasswd
                    content_line "${GREEN}Mot de passe modifié avec succès !${RESET}"
                else
                    content_line "${RED}Les mots de passe ne correspondent pas.${RESET}"
                fi
                read -p "Appuyez sur Entrée pour continuer..." dummy
                ;;
            2)
                read -p "Nouvelle durée (en jours) : " days
                if [[ "$days" =~ ^[0-9]+$ ]]; then
                    chage -E $(date -d "+$days days" +"%Y-%m-%d") "$selected_user"
                    content_line "${GREEN}Expiration modifiée avec succès !${RESET}"
                else
                    content_line "${RED}Durée invalide.${RESET}"
                fi
                read -p "Appuyez sur Entrée pour continuer..." dummy
                ;;
            0) break ;;
            *) content_line "${RED}Choix invalide !${RESET}"
               read -p "Appuyez sur Entrée pour continuer..." dummy ;;
        esac
    done
done
