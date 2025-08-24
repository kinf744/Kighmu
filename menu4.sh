#!/bin/bash
# ==============================================
# menu4.sh - Gestion des utilisateurs SSH
# ==============================================

WIDTH=60
CYAN="\e[36m"
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

# Fonction de nettoyage des fichiers utilisateurs
cleanup_user_files() {
    local username="$1"
    echo "Nettoyage des fichiers de $username..."
    [ -d "/home/$username" ] && sudo rm -rf "/home/$username"
    for mailpath in "/var/mail/$username" "/var/spool/mail/$username"; do
        [ -f "$mailpath" ] && sudo rm -f "$mailpath"
    done
    sudo find / -user "$username" -exec rm -rf {} + 2>/dev/null
}

# Boucle menu principal
while true; do
    clear
    line_full
    center_line "GESTION DES UTILISATEURS SSH"
    line_full

    ssh_users=$(awk -F: '/\/home/ {print $1}' /etc/passwd)
    if [ -z "$ssh_users" ]; then
        center_line "Aucun utilisateur SSH trouvé"
        line_simple
    else
        printf "| %-4s %-20s %-15s %-15s |\n" "No." "Utilisateur" "Connecté" "Expiré"
        line_simple
        i=1
        for u in $ssh_users; do
            connected=$(who | awk '{print $1}' | grep -qw "$u" && echo "Oui" || echo "Non")
            expire_date=$(chage -l "$u" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
            [ -z "$expire_date" ] && expire_date="Jamais"
            printf "| %-4s %-20s %-15s %-15s |\n" "$i" "$u" "$connected" "$expire_date"
            i=$((i+1))
        done
        line_simple
    fi

    echo ""
    echo "Options :"
    echo "1) Modifier mot de passe"
    echo "2) Modifier durée/expiration"
    echo "3) Supprimer utilisateur"
    echo "0) Retour au menu principal"
    read -p "Votre choix : " choice

    case $choice in
        1)
            read -p "Entrez le nom de l'utilisateur : " user
            read -s -p "Nouveau mot de passe : " newpass
            echo ""
            read -s -p "Confirmez le mot de passe : " newpass2
            echo ""
            if [ "$newpass" == "$newpass2" ]; then
                echo "$user:$newpass" | chpasswd
                echo "Mot de passe modifié avec succès !"
            else
                echo "Les mots de passe ne correspondent pas."
            fi
            read -p "Appuyez sur Entrée pour continuer..."
            ;;
        2)
            read -p "Entrez le nom de l'utilisateur : " user
            read -p "Durée de validité (en jours) : " days
            if [[ "$days" =~ ^[0-9]+$ ]]; then
                chage -E $(date -d "+$days days" +"%Y-%m-%d") "$user"
                echo "Expiration modifiée avec succès !"
            else
                echo "Durée invalide."
            fi
            read -p "Appuyez sur Entrée pour continuer..."
            ;;
        3)
            read -p "Nom de l'utilisateur à supprimer : " user
            if id "$user" &>/dev/null; then
                cleanup_user_files "$user"
                sudo userdel -r "$user"
                sudo sed -i "/^$user|/d" /etc/kighmu/users.list
                echo "Utilisateur $user supprimé."
            else
                echo "Utilisateur $user introuvable."
            fi
            read -p "Appuyez sur Entrée pour continuer..."
            ;;
        0) break ;;
        *) echo "Choix invalide !" ; read -p "Appuyez sur Entrée pour continuer..." ;;
    esac
done
