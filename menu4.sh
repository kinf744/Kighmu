#!/bin/bash
# menu4.sh - Supprimer un utilisateur avec gestion robuste et sudo mv pour update liste

USER_FILE="/etc/kighmu/users.list"

# Couleur bleu marine pour les cadres
BLUE="\e[34m"
RESET="\e[0m"

# Fonction pour encadrer un texte
draw_frame() {
    local text="$1"
    local width=60
    echo -e "${BLUE}+$(printf '%.0s-' $(seq 1 $width))+${RESET}"
    printf "|%*s%*s|\n" $(( (width + ${#text})/2 )) "$text" $(( (width - ${#text})/2 )) ""
    echo -e "${BLUE}+$(printf '%.0s-' $(seq 1 $width))+${RESET}"
}

# Affichage du panneau d’accueil
clear
draw_frame "SUPPRIMER UN UTILISATEUR"

if [ ! -f "$USER_FILE" ]; then
    echo "Aucun utilisateur trouvé."
    draw_frame "FIN DU PANNEL"
    exit 0
fi

draw_frame "UTILISATEURS EXISTANTS"
cut -d'|' -f1 "$USER_FILE"
echo "------------------------------------------------------------"

read -p "Nom de l'utilisateur à supprimer : " username

# Fonction nettoyage fichiers liés à l'utilisateur
cleanup_user_files() {
    echo "Nettoyage des fichiers restants de l'utilisateur $1..."

    if [ -d "/home/$1" ]; then
        echo "Suppression du dossier home /home/$1"
        sudo rm -rf "/home/$1"
    fi

    for mailpath in "/var/mail/$1" "/var/spool/mail/$1"; do
        if [ -f "$mailpath" ]; then
            echo "Suppression du fichier mail $mailpath"
            sudo rm -f "$mailpath"
        fi
    done

    echo "Recherche et suppression des fichiers appartenant à $1 dans le système..."
    sudo find / -user "$1" -exec rm -rf {} + 2>/dev/null
}

# Vérification de l'existence système
if id "$username" &>/dev/null; then
    cleanup_user_files "$username"

    if sudo userdel -r "$username"; then
        echo "Utilisateur système $username supprimé avec succès."

        if grep -v "^$username|" "$USER_FILE" > "${USER_FILE}.tmp"; then
            if sudo mv "${USER_FILE}.tmp" "$USER_FILE"; then
                echo "Utilisateur $username supprimé de la liste utilisateurs."
            else
                echo "Erreur critique : impossible de remplacer le fichier ${USER_FILE}. Vérifiez les permissions."
                exit 1
            fi
        else
            echo "Erreur critique : impossible de créer le fichier temporaire ${USER_FILE}.tmp."
            exit 1
        fi
    else
        echo "Erreur lors de la suppression de l'utilisateur système $username."
        exit 1
    fi
else
    echo "Attention : utilisateur système $username non trouvé ou déjà supprimé."
    cleanup_user_files "$username"

    if grep -q "^$username|" "$USER_FILE"; then
        if grep -v "^$username|" "$USER_FILE" > "${USER_FILE}.tmp"; then
            if sudo mv "${USER_FILE}.tmp" "$USER_FILE"; then
                echo "Utilisateur $username retiré de la liste utilisateurs."
            else
                echo "Erreur critique : impossible de remplacer le fichier ${USER_FILE}. Vérifiez les permissions."
                exit 1
            fi
        else
            echo "Erreur critique : impossible de créer le fichier temporaire ${USER_FILE}.tmp."
            exit 1
        fi
    else
        echo "Utilisateur $username n'est pas dans la liste utilisateurs."
    fi
fi

draw_frame "FIN DE LA SUPPRESSION"
read -p "Appuyez sur Entrée pour revenir au menu..."
