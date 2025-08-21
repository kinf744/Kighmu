#!/bin/bash
# menu_4.sh - Gestion des utilisateurs SSH

RESET="\e[0m"; BOLD="\e[1m"; CYAN="\e[36m"; YELLOW="\e[33m"; GREEN="\e[32m"; RED="\e[31m"

while true; do
    clear
    echo -e "${CYAN}+--------------------------------------------------+${RESET}"
    echo -e "${CYAN}|         ${BOLD}GESTION UTILISATEURS SSH${RESET}${CYAN}                |${RESET}"
    echo -e "${CYAN}+--------------------------------------------------+${RESET}"
    echo -e "${YELLOW}1) Modifier durée (expiration) d’un utilisateur${RESET}"
    echo -e "${YELLOW}2) Modifier mot de passe d’un utilisateur${RESET}"
    echo -e "${YELLOW}3) Retour menu principal${RESET}"
    echo -e "${CYAN}+--------------------------------------------------+${RESET}"
    echo ""

    read -p "Votre choix : " choix

    case $choix in
        1)
            read -p "Nom de l’utilisateur : " user
            if id "$user" &>/dev/null; then
                read -p "Durée en jours : " jours
                sudo chage -E $(date -d "+$jours days" +"%Y-%m-%d") "$user"
                echo -e "${GREEN}Expiration de $user modifiée à $jours jours.${RESET}"
            else
                echo -e "${RED}Utilisateur introuvable.${RESET}"
            fi
            ;;
        2)
            read -p "Nom de l’utilisateur : " user
            if id "$user" &>/dev/null; then
                read -p "Nouveau mot de passe : " mdp
                echo "$user:$mdp" | sudo chpasswd
                echo -e "${GREEN}Mot de passe de $user modifié avec succès.${RESET}"
            else
                echo -e "${RED}Utilisateur introuvable.${RESET}"
            fi
            ;;
        3)
            echo -e "${YELLOW}Retour au menu principal...${RESET}"
            sleep 1
            bash "$HOME/Kighmu/kighmu.sh"
            exit 0
            ;;
        *)
            echo -e "${RED}Choix invalide !${RESET}"
            ;;
    esac

    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
done
