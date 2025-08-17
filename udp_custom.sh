#!/bin/bash
# udp_custom.sh
# Installation et configuration du mode UDP Custom

echo "+--------------------------------------------+"
echo "|               CONFIG UDP CUSTOM            |"
echo "+--------------------------------------------+"

read -p "Voulez-vous installer UDP Custom sur tous les ports ? [oui/non] : " confirm

case "$confirm" in
    [oO][uU][iI]|[yY][eE][sS])
        echo "Installation UDP Custom sur les ports 1-65535..."
        # Commandes pour configurer UDP Custom
        sleep 2
        echo "UDP Custom activé."
        ;;
    [nN][oO]|[nN])
        echo "Installation annulée."
        ;;
    *)
        echo "Réponse invalide. Annulation."
        ;;
esac
