#!/bin/bash
# menu6.sh
# Désinstaller le script avec confirmation

echo "+--------------------------------------------+"
echo "|            DÉSINSTALLER LE SCRIPT         |"
echo "+--------------------------------------------+"

read -p "Voulez-vous vraiment désinstaller le script ? [oui/non] : " confirm

case "$confirm" in
    [oO][uU][iI]|[yY][eE][sS])
        echo "Désinstallation en cours..."

        # Supprimer tous les fichiers du script
        SCRIPT_DIR="$(dirname "$(realpath "$0")")"
        rm -rf "$SCRIPT_DIR"

        echo "Script désinstallé avec succès."
        ;;
    [nN][oO]|[nN])
        echo "Désinstallation annulée."
        ;;
    *)
        echo "Réponse invalide. Désinstallation annulée."
        ;;
esac
