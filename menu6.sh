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

        echo "Arrêt et désactivation des services et processus..."

        # Stop et disable systemd services (ouvre ssh, dropbear)
        systemctl stop ssh
        systemctl disable ssh
        systemctl stop dropbear
        systemctl disable dropbear

        # Tuer les processus lancés manuellement
        pkill -f slowdns.sh 2>/dev/null
        pkill -f udp_custom.sh 2>/dev/null
        pkill -f socks_python.sh 2>/dev/null
        pkill -f proxy_wss.py 2>/dev/null

        # Supprimer éventuelles tâches cron ou autre qui relanceraient ces processus au démarrage
        # Exemple pour retirer une tâche cron (à adapter selon votre script d'installation)
        crontab -l | grep -v 'slowdns.sh' | crontab -
        crontab -l | grep -v 'udp_custom.sh' | crontab -
        crontab -l | grep -v 'socks_python.sh' | crontab -
        crontab -l | grep -v 'proxy_wss.py' | crontab -

        # Supprimer le dossier du script (avec tous les fichiers)
        SCRIPT_DIR="$(dirname "$(realpath "$0")")"
        rm -rf "$SCRIPT_DIR"

        echo "Script désinstallé avec succès."

        echo "Redémarrage du VPS dans 2 secondes..."
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
