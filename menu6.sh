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

        # Arrêt des services/processus de tunnel
        echo "Arrêt des services de tunnel..."

        # Exemple d'arrêt de services systemd - adapter aux services réels
        # systemctl stop slowdns.service
        # systemctl stop proxy-socks.service
        # systemctl stop udp-custom.service

        # Ou tuer les processus s'ils ne sont pas gérés via systemd
        killall slowdns 2>/dev/null
        killall proxy-socks 2>/dev/null
        killall udp-custom 2>/dev/null

        echo "Services de tunnel arrêtés."

        # Supprimer tous les fichiers du script
        SCRIPT_DIR="$(dirname "$(realpath "$0")")"
        rm -rf "$SCRIPT_DIR"

        echo "Script désinstallé avec succès."

        echo "Le serveur VPS va redémarrer automatiquement dans 2 secondes..."
        sleep 2
        reboot
        ;;
    [nN][oO]|[nN])
        echo "Désinstallation annulée."
        ;;
    *)
        echo "Réponse invalide. Désinstallation annulée."
        ;;
esac
