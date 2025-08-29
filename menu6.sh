#!/bin/bash
# Désinstallation complète des services tunnels VPS

echo "+--------------------------------------------+"
echo "|         DÉSINSTALLATION DES SERVICES       |"
echo "+--------------------------------------------+"

read -p "Voulez-vous vraiment désinstaller tous les services tunnel ? [oui/non] : " confirm

case "$confirm" in
    [oO][uU][iI]|[yY][eE][sS])

        echo "Arrêt et désactivation des services systemd..."

        SERVICES=(
            slowdns.service
            socks_python.service
            udp_custom.service
            # Ajoutez ici tous les autres services .service installés
        )

        for service in "${SERVICES[@]}"; do
            if systemctl list-unit-files | grep -q "^$service"; then
                echo "Arrêt, désactivation, masquage et suppression de $service..."
                sudo systemctl stop "$service"
                sudo systemctl disable "$service"
                sudo systemctl mask "$service"
                sudo rm -f "/etc/systemd/system/$service"
                sudo rm -f "/lib/systemd/system/$service"
            else
                echo "$service non trouvé."
            fi
        done

        echo "Rechargement de la configuration systemd..."
        sudo systemctl daemon-reload
        sudo systemctl reset-failed

        echo "Arrêt des processus en cours liés aux services..."

        pkill -f slowdns.sh
        pkill -f sldns-server
        pkill -f socks_python.sh
        pkill -f KIGHMUPROXY.py
        pkill -f udp_custom.sh
        # Ajoutez d'autres kills selon vos scripts/processus

        echo "Suppression des fichiers et dossiers des scripts..."

        SCRIPT_DIR="$(dirname "$(realpath "$0")")"
        sudo rm -rf "$SCRIPT_DIR"

        echo "Tous les services tunnel ont été désinstallés."
        echo "Redémarrage du VPS dans 3 secondes..."
        sleep 3
        sudo reboot
        ;;
    [nN][oO]|[nN])
        echo "Désinstallation annulée."
        ;;
    *)
        echo "Réponse invalide. Désinstallation annulée."
        ;;
esac
