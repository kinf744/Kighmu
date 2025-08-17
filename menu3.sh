#!/bin/bash
# menu3.sh
# Afficher les utilisateurs en ligne avec nombre d'appareils et limite

echo "+--------------------------------------------+"
echo "|         UTILISATEURS EN LIGNE             |"
echo "+--------------------------------------------+"

# Récupérer tous les utilisateurs créés pour ce script
# On suppose qu'ils ont été ajoutés avec useradd et une limite stockée dans un fichier dédié
USER_FILE="./users_list.txt"

if [ ! -f $USER_FILE ]; then
    echo "Aucun utilisateur trouvé."
    exit 0
fi

printf "%-15s %-10s %-10s\n" "UTILISATEUR" "CONNECTÉS" "LIMITE"
echo "----------------------------------------------"

while IFS=: read -r username limite
do
    # Compter le nombre de connexions SSH/Dropbear/UDP/SOCKS pour cet utilisateur
    # Ici un exemple simple pour SSH et Dropbear
    connected=$(who | awk '{print $1}' | grep -c "^$username$")
    
    # Afficher
    printf "%-15s %-10s %-10s\n" "$username" "$connected" "$limite"
done < $USER_FILE
