#!/bin/bash
# menu4.sh - Suppression des utilisateurs SSH

WIDTH=60
BLUE="\e[34m"   # Bleu marine
RESET="\e[0m"

# Fonctions d'affichage
line_full() { echo -e "${BLUE}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${BLUE}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
content_line() { printf "| %-56s |\n" "$1"; }
center_line() {
    local text="$1"
    local visible_text=$(echo -e "$text" | sed 's/\x1B\[[0-9;]*[mK]//g')
    local padding=$(( (WIDTH - ${#visible_text}) / 2 ))
    printf "|%*s%s%*s|\n" "$padding" "" "$text" "$padding" ""
}

# Vérification root
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERREUR] Veuillez exécuter ce script en root."
    exit 1
fi

# Liste des utilisateurs SSH
get_ssh_users() {
    awk -F: '/\/home/ {print $1}' /etc/passwd
}

delete_user() {
    local user="$1"
    if id "$user" >/dev/null 2>&1; then
        userdel -r "$user"
        echo "Utilisateur $user supprimé."
    else
        echo "Utilisateur $user inexistant."
    fi
}

delete_all_users() {
    for u in $(get_ssh_users); do
        userdel -r "$u"
        echo "Utilisateur $u supprimé."
    done
}

# Menu principal
while true; do
    clear
    line_full
    center_line "SUPPRESSION UTILISATEURS SSH"
    line_full

    users=($(get_ssh_users))
    if [ ${#users[@]} -eq 0 ]; then
        content_line "Aucun utilisateur SSH trouvé."
    else
        content_line "Utilisateurs existants :"
        for u in "${users[@]}"; do
            content_line " - $u"
        done
    fi
    line_full

    echo "1) Supprimer un utilisateur"
    echo "2) Supprimer tous les utilisateurs"
    echo "0) Retour"
    line_simple
    read -p "Votre choix : " choix

    case $choix in
        1)
            read -p "Entrez le nom de l'utilisateur à supprimer : " user_to_del
            delete_user "$user_to_del"
            read -p "Appuyez sur Entrée pour continuer..."
            ;;
        2)
            read -p "Confirmer la suppression de tous les utilisateurs ? (o/N) : " confirm
            if [[ "$confirm" =~ ^[Oo]$ ]]; then
                delete_all_users
            else
                echo "Opération annulée."
            fi
            read -p "Appuyez sur Entrée pour continuer..."
            ;;
        0) break ;;
        *) echo "Choix invalide." ; read -p "Appuyez sur Entrée pour continuer..." ;;
    esac
done
