#!/bin/bash
# menu4.sh - Supprimer un utilisateur avec gestion robuste et panneau coloré

USER_FILE="/etc/kighmu/users.list"

# Couleurs
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

clear

echo -e "${CYAN}+--------------------------------------------+${RESET}"
echo -e "${BOLD}|            SUPPRIMER UN UTILISATEUR       |${RESET}"
echo -e "${CYAN}+--------------------------------------------+${RESET}"

if [ ! -f "$USER_FILE" ]; then
    echo -e "${YELLOW}Aucun utilisateur trouvé.${RESET}"
    exit 0
fi

echo -e "${CYAN}Utilisateurs existants :${RESET}"
cut -d'|' -f1 "$USER_FILE"

read -rp "${BOLD}Nom de l'utilisateur à supprimer : ${RESET}" username

# Vérification dans users.list
if ! grep -q "^$username|" "$USER_FILE"; then
    echo -e "${RED}Utilisateur '$username' introuvable dans la liste.${RESET}"
    exit 1
fi

# Confirmation avant suppression
read -rp "${YELLOW}Confirmez suppression de l'utilisateur '${username}' ? (o/N) : ${RESET}" confirm
if [[ ! "$confirm" =~ ^[oO]$ ]]; then
    echo -e "${GREEN}Suppression annulée.${RESET}"
    exit 0
fi

# Vérification de l'existence système
if id "$username" &>/dev/null; then
    # Suppression de l'utilisateur système et son home
    if sudo userdel -r "$username"; then
        echo -e "${GREEN}Utilisateur système '${username}' supprimé avec succès.${RESET}"

        # Suppression dans users.list
        if grep -v "^$username|" "$USER_FILE" > "${USER_FILE}.tmp"; then
            mv "${USER_FILE}.tmp" "$USER_FILE"
            echo -e "${GREEN}Utilisateur '${username}' supprimé de la liste utilisateurs.${RESET}"
        else
            echo -e "${RED}Erreur : impossible de mettre à jour la liste des utilisateurs.${RESET}"
            exit 1
        fi
    else
        echo -e "${RED}Erreur lors de la suppression de l'utilisateur système '${username}'.${RESET}"
        exit 1
    fi
else
    echo -e "${YELLOW}Attention : utilisateur système '${username}' non trouvé ou déjà supprimé.${RESET}"
    # On peut quand même tenter de retirer de la liste users.list si présent
    if grep -q "^$username|" "$USER_FILE"; then
        if grep -v "^$username|" "$USER_FILE" > "${USER_FILE}.tmp"; then
            mv "${USER_FILE}.tmp" "$USER_FILE"
            echo -e "${GREEN}Utilisateur '${username}' retiré de la liste utilisateurs.${RESET}"
        else
            echo -e "${RED}Erreur : impossible de mettre à jour la liste des utilisateurs.${RESET}"
            exit 1
        fi
    fi
fi

read -rp "${BOLD}Appuyez sur Entrée pour revenir au menu...${RESET}"
