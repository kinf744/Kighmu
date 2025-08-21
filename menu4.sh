#!/bin/bash
# menu4.sh - Supprimer un utilisateur avec gestion robuste et sudo mv pour update liste

USER_FILE="/etc/kighmu/users.list"

echo "+--------------------------------------------+"
echo "|            SUPPRIMER UN UTILISATEUR       |"
echo "+--------------------------------------------+"

if [ ! -f "$USER_FILE" ]; then
    echo "Aucun utilisateur trouvé."
    exit 0
fi

echo "Utilisateurs existants :"
cut -d'|' -f1 "$USER_FILE"

read -p "Nom de l'utilisateur à supprimer : " username

# Fonction nettoyage fichiers liés à l'utilisateur
cleanup_user_files() {
    echo "Nettoyage des fichiers restants de l'utilisateur $1..."

    # Suppression manuelle du dossier home
    if [ -d "/home/$1" ]; then
        echo "Suppression du dossier home /home/$1"
        sudo rm -rf "/home/$1"
    fi

    # Suppression des boîtes mail classiques
    for mailpath in "/var/mail/$1" "/var/spool/mail/$1"; do
        if [ -f "$mailpath" ]; then
            echo "Suppression du fichier mail $mailpath"
            sudo rm -f "$mailpath"
        fi
    done

    # Suppression de tous les fichiers appartenant à l'utilisateur restants
    echo "Recherche et suppression des fichiers appartenant à $1 dans le système..."
    sudo find / -user "$1" -exec rm -rf {} + 2>/dev/null
}

# Vérification de l'existence système
if id "$username" &>/dev/null; then
    # Suppression manuelle des fichiers avant userdel pour éviter warnings
    cleanup_user_files "$username"

    # Suppression de l'utilisateur système
    if sudo userdel -r "$username"; then
        echo "Utilisateur système $username supprimé avec succès."

        # Suppression dans users.list avec sudo mv
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

    # Nettoyage manuel même si utilisateur absent
    cleanup_user_files "$username"

    # Suppression dans users.list avec sudo mv
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

read -p "Appuyez sur Entrée pour revenir au menu..."
