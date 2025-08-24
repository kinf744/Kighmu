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

# Vérification de l'existence système
if id "$username" &>/dev/null; then
    # Suppression de l'utilisateur système et son home
    if sudo userdel -r "$username"; then
        echo "Utilisateur système $username supprimé avec succès."

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
