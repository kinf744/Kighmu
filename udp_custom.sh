#!/bin/bash
# udp_custom.sh
# Installation et configuration du mode UDP Custom

echo "+--------------------------------------------+"
echo "|               CONFIG UDP CUSTOM            |"
echo "+--------------------------------------------+"

read -p "Voulez-vous installer UDP Custom sur tous les ports (1-65535) ? [oui/non] : " confirm

case "$confirm" in
    [oO][uU][iI]|[yY][eE][sS])
        echo "Installation UDP Custom sur les ports 1-65535..."

        # Exemple : vérification présence binaire udp-custom (ajuste selon ton dépôt)
        if ! command -v udp-custom &> /dev/null; then
            echo "udp-custom non trouvé, téléchargement et installation..."
            # Exemple d’installation, adapte selon ta source
            wget -O /usr/local/bin/udp-custom https://example.com/udp-custom
            chmod +x /usr/local/bin/udp-custom
        fi

        # Ouvrir la plage de ports UDP dans le pare-feu
        sudo ufw allow 1:65535/udp
        sudo iptables -I INPUT -p udp --dport 1:65535 -j ACCEPT

        # Kill ancien processus udp-custom éventuel
        fuser -k 1-65535/udp || true

        # Exemple de lancement du serveur UDP Custom sur la plage complète
        nohup udp-custom --port-range 1-65535 > /var/log/udp_custom.log 2>&1 &

        sleep 2

        if pgrep -f "udp-custom" > /dev/null; then
            echo "UDP Custom démarré sur les ports 1-65535."
        else
            echo "Échec du démarrage du service UDP Custom."
        fi
        ;;
    [nN][oO]|[nN])
        echo "Installation annulée."
        ;;
    *)
        echo "Réponse invalide. Annulation."
        ;;
esac
