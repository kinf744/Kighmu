#!/bin/bash
# menu4.sh - Supprimer un utilisateur avec gestion complète

USER_FILE="/etc/kighmu/users.list"
WIDTH=60

# Couleurs
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# Fonctions d'affichage
line_full() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
center_line() {
    local text="$1"
    local padding=$(( (WIDTH - ${#text}) / 2 ))
    printf "|%*s%s%*s|\n" "$padding" "" "$text" "$padding" ""
}
content_line() { printf "| %-56s |\n" "$1"; }

# Vérifier fichier utilisateur
if [ ! -f "$USER_FILE" ]; then
    clear
    line_full
    center_line "${RED}AUCUN UTILISATEUR TROUVÉ${RESET}"
    line_full
    read -p "Appuyez sur Entrée pour revenir au menu..."
    exit 0
fi

# Affichage des utilisateurs existants
clear
line_full
center_line "${YELLOW}SUPPRIMER UN UTILISATEUR${RESET}"
line_full
center_line "${CYAN}UTILISATEURS EXISTANTS${RESET}"
line_simple
cut -d'|' -f1 "$USER_FILE" | nl -w2 -s'. '
line_simple

# Choix utilisateur à supprimer
read -p "Entrez le nom de l'utilisateur à supprimer : " username
if [ -z "$username" ]; then
    echo -e "${RED}Nom utilisateur invalide.${RESET}"
    exit 1
fi

# Fonction de nettoyage
cleanup_user_files() {
    echo "Nettoyage des fichiers de l'utilisateur $1..."
    [ -d "/home/$1" ] && sudo rm -rf "/home/$1" && echo "Dossier /home/$1 supprimé"
    for mailpath in "/var/mail/$1" "/var/spool/mail/$1"; do
        [ -f "$mailpath" ] && sudo rm -f "$mailpath" && echo "Mail $mailpath supprimé"
    done
    sudo find / -user "$1" -exec rm -rf {} + 2>/dev/null
}

# Suppression utilisateur
if id "$username" &>/dev/null; then
    cleanup_user_files "$username"
    if sudo userdel -r "$username"; then
        echo -e "${GREEN}Utilisateur système $username supprimé avec succès.${RESET}"
        # Suppression dans users.list
        grep -v "^$username|" "$USER_FILE" | sudo tee "$USER_FILE" >/dev/null
        echo -e "${GREEN}$username retiré de la liste utilisateurs.${RESET}"
    else
        echo -e "${RED}Erreur lors de la suppression de $username.${RESET}"
        exit 1
    fi
else
    echo -e "${YELLOW}Utilisateur système $username non trouvé.${RESET}"
    # Supprimer quand même dans users.list
    if grep -q "^$username|" "$USER_FILE"; then
        grep -v "^$username|" "$USER_FILE" | sudo tee "$USER_FILE" >/dev/null
        echo -e "${GREEN}$username retiré de la liste utilisateurs.${RESET}"
    fi
fi

line_full
center_line "${YELLOW}SUPPRESSION TERMINÉE${RESET}"
line_full
read -p "Appuyez sur Entrée pour revenir au menu..."
