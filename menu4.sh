#!/bin/bash
# menu4.sh - Supprimer un utilisateur avec gestion robuste et mise à jour users.list

USER_FILE="/etc/kighmu/users.list"
WIDTH=60

# Couleurs
CYAN="\e[36m"
YELLOW="\e[33m"
RESET="\e[0m"

# Fonctions d'affichage
line_full() { echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
content_line() { printf "| %-56s |\n" "$1"; }
center_line() { local text="$1"; local padding=$(( (WIDTH - ${#text}) / 2 )); printf "|%*s%s%*s|\n" "$padding" "" "$text" "$padding" ""; }

# Fonction pour compter connexions
connected_count() { who | awk '{print $1}' | grep -c "^$1$"; }

# Fonction nettoyage fichiers liés à l'utilisateur
cleanup_user_files() {
    echo "Nettoyage des fichiers restants de l'utilisateur $1..."
    if [ -d "/home/$1" ]; then
        echo "Suppression du dossier home /home/$1"
        sudo rm -rf "/home/$1"
    fi
    for mailpath in "/var/mail/$1" "/var/spool/mail/$1"; do
        [ -f "$mailpath" ] && sudo rm -f "$mailpath"
    done
    sudo find / -user "$1" -exec rm -rf {} + 2>/dev/null
}

# Affichage du panneau
clear
line_full
center_line "${YELLOW}SUPPRIMER UN UTILISATEUR${RESET}"
line_full

# Vérification du fichier utilisateur
if [ ! -f "$USER_FILE" ]; then
    content_line "Aucun utilisateur trouvé."
    line_full
    exit 0
fi

# Afficher la liste des utilisateurs existants
line_simple
center_line "UTILISATEURS EXISTANTS"
line_simple
while IFS="|" read -r username _ limite _ _ _ _; do
    connected=$(connected_count "$username")
    content_line "$(printf '%-20s Connexions: %-3s Limite: %-3s' "$username" "$connected" "$limite")"
done < "$USER_FILE"
line_simple

# Demande utilisateur à supprimer
read -p "Nom de l'utilisateur à supprimer : " del_user

# Suppression et nettoyage
if id "$del_user" &>/dev/null; then
    cleanup_user_files "$del_user"
    if sudo userdel -r "$del_user"; then
        content_line "Utilisateur système $del_user supprimé avec succès."
    else
        content_line "Erreur lors de la suppression du compte système $del_user."
    fi
else
    content_line "Utilisateur système $del_user non trouvé ou déjà supprimé."
    cleanup_user_files "$del_user"
fi

# Mise à jour du fichier users.list
if grep -q "^$del_user|" "$USER_FILE"; then
    grep -v "^$del_user|" "$USER_FILE" > "${USER_FILE}.tmp" && sudo mv "${USER_FILE}.tmp" "$USER_FILE"
    content_line "Utilisateur $del_user retiré de la liste utilisateurs."
else
    content_line "Utilisateur $del_user non présent dans la liste."
fi

line_full
center_line "${YELLOW}FIN DE LA SUPPRESSION${RESET}"
line_full
read -p "Appuyez sur Entrée pour revenir au menu..."
