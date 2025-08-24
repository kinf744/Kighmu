#!/bin/bash
# menu3.sh
# Afficher les utilisateurs en ligne avec nombre d'appareils et limite + IP connectées

USER_FILE="/etc/kighmu/users.list"

echo "+--------------------------------------------+"
echo "|         UTILISATEURS EN LIGNE             |"
echo "+--------------------------------------------+"

if [ ! -f "$USER_FILE" ]; then
    echo "Aucun utilisateur trouvé."
    exit 0
fi

printf "%-15s %-10s %-10s %-25s\n" "UTILISATEUR" "CONNECTÉS" "LIMITE" "ADRESSES IP CONNECTÉES"
echo "------------------------------------------------------------------------------------------"

while IFS="|" read -r username password limite expire_date rest; do
    # Compter le nombre de connexions SSH/Dropbear/UDP/SOCKS pour cet utilisateur
    # Exemple simple avec SSH (utiliser who et filtrer par utilisateur)
    connected=$(who | awk '{print $1}' | grep -c "^$username$")
    
    # Extraire les IP connectées pour cet utilisateur
    ips=$(who | awk -v user="$username" '$1 == user {print $5}' | tr -d '()' | paste -sd "," -)
    [ -z "$ips" ] && ips="Aucune"

    printf "%-15s %-10s %-10s %-25s\n" "$username" "$connected" "$limite" "$ips"
done < "$USER_FILE"
