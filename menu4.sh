#!/bin/bash
# menu4.sh - Supprimer un utilisateur avec gestion robuste

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

# Vérification dans users.list
if ! grep -q "^$username|" "$USER_FILE"; then
    echo "Utilisateur $username introuvable dans la liste."
    exit 1
fi

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
    # Suppression de l'utilisateur système et de son home
    if sudo userdel -r "$username"; then
        echo "Utilisateur système $username supprimé avec succès."

        # Nettoyage supplémentaire si besoin
        cleanup_user_files "$username"

        # Suppression dans users.list
        if grep -v "^$username|" "$USER_FILE" > "${USER_FILE}.tmp"; then
            mv "${USER_FILE}.tmp" "$USER_FILE"
            echo "Utilisateur $username supprimé de la liste utilisateurs."
        else
            echo "Erreur : impossible de mettre à jour la liste des utilisateurs."
            exit 1
        fi
    else
        echo "Erreur lors de la suppression de l'utilisateur système $username."
        exit 1
    fi
else
    echo "Attention : utilisateur système $username non trouvé ou déjà supprimé."

    # Nettoyage manuel même s’il n’est plus présent en système
    cleanup_user_files "$username"

    # On peut quand même tenter de retirer de la liste users.list si présent
    if grep -q "^$username|" "$USER_FILE"; then
        if grep -v "^$username|" "$USER_FILE" > "${USER_FILE}.tmp"; then
            mv "${USER_FILE}.tmp" "$USER_FILE"
            echo "Utilisateur $username retiré de la liste utilisateurs."
        else
            echo "Erreur : impossible de mettre à jour la liste des utilisateurs."
            exit 1
        fi
    fi
fi

read -p "Appuyez sur Entrée pour revenir au menu..."
