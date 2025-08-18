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

# Vérifier si l'utilisateur existe dans la liste
if ! grep -q "^$username|" "$USER_FILE"; then
    echo "Utilisateur $username introuvable."
    exit 1
fi

# Supprimer l'utilisateur système (avec suppression du dossier home si existe)
userdel -r "$username" 2>/dev/null || echo "Attention: utilisateur système non trouvé ou déjà supprimé."

# Supprimer l'utilisateur du fichier users.list
grep -v "^$username|" "$USER_FILE" > "${USER_FILE}.tmp" && mv "${USER_FILE}.tmp" "$USER_FILE"

echo "Utilisateur $username supprimé avec succès."
