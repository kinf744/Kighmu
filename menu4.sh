#!/bin/bash
# menu4.sh
# Supprimer un utilisateur

USER_FILE="/etc/kighmu/users.list"

echo "+--------------------------------------------+"
echo "|            SUPPRIMER UN UTILISATEUR       |"
echo "+--------------------------------------------+"

if [ ! -f "$USER_FILE" ]; then
    echo "Aucun utilisateur trouvé."
    exit 0
fi

# Afficher la liste des utilisateurs
echo "Utilisateurs existants :"
cut -d'|' -f1 "$USER_FILE"

# Demander le nom de l'utilisateur à supprimer
read -p "Nom de l'utilisateur à supprimer : " username

# Vérifier si l'utilisateur est dans la liste users.list
if ! grep -q "^$username|" "$USER_FILE"; then
    echo "Utilisateur $username introuvable dans la liste des utilisateurs."
    exit 1
fi

# Vérifier que l'utilisateur système existe avant suppression
if id "$username" &>/dev/null; then
    # Supprimer l'utilisateur système et son dossier home
    if sudo userdel -r "$username"; then
        echo "Utilisateur système $username supprimé avec succès."
    else
        echo "Erreur lors de la suppression de l'utilisateur système $username."
        exit 1
    fi
else
    echo "Attention : utilisateur système $username non trouvé ou déjà supprimé."
fi

# Mettre à jour le fichier users.list en supprimant l'utilisateur
if grep -v "^$username|" "$USER_FILE" > "${USER_FILE}.tmp"; then
    mv "${USER_FILE}.tmp" "$USER_FILE"
    echo "Utilisateur $username supprimé de la liste utilisateurs."
else
    echo "Erreur lors de la mise à jour de la liste des utilisateurs."
    exit 1
fi

echo "Suppression de l'utilisateur $username terminée."

read -p "Appuyez sur Entrée pour revenir au menu..."
