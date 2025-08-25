#!/bin/bash
# menu3.sh
# Afficher les utilisateurs en ligne avec nombre d'appareils et limite

USER_FILE="/etc/kighmu/users.list"

echo "+--------------------------------------------+"
echo "|         UTILISATEURS EN LIGNE             |"
echo "+--------------------------------------------+"

if [ ! -f "$USER_FILE" ]; then
    echo "Aucun utilisateur trouvé."
    exit 0
fi

printf "%-15s %-10s %-10s\n" "UTILISATEUR" "CONNECTÉS" "LIMITE"
echo "----------------------------------------------"

while IFS="|" read -r username password limite expire_date rest; do
    # Compter le nombre de connexions SSH actives pour cet utilisateur
    connected=$(who | awk -v user="$username" '$1 == user' | wc -l)
    
    printf "%-15s %-10s %-10s\n" "$username" "$connected" "$limite"
done < "$USER_FILE"
