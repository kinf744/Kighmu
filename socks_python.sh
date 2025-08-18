#!/bin/bash
# socks_python.sh
# Activation du SOCKS Python avec WebSocket HTTP/2

echo "+--------------------------------------------+"
echo "|             CONFIG SOCKS/PYTHON            |"
echo "+--------------------------------------------+"

read -p "Voulez-vous démarrer le proxy SOCKS/Python avec WS HTTP/2 ? [oui/non] : " confirm

case "$confirm" in
    [oO][uU][iI]|[yY][eE][sS])
        echo "Démarrage du proxy SOCKS/Python..."

        # Exemple de commande de lancement, à adapter selon ton vrai serveur Python
        # S'assurer d'écouter sur 0.0.0.0 pour accepter les connexions extérieures
        # et pas uniquement localhost
        nohup python3 -m websocks --host 0.0.0.0 --port 80 --http2 > /var/log/socks_python.log 2>&1 &

        sleep 2

        # Vérifie si le processus tourne
        if pgrep -f "python3 -m websocks" > /dev/null; then
            echo "Proxy SOCKS/Python démarré avec HTTP/2 sur le port 80."
        else
            echo "Échec du démarrage du proxy SOCKS/Python."
        fi
        ;;
    [nN][oO]|[nN])
        echo "Démarrage annulé."
        ;;
    *)
        echo "Réponse invalide. Annulation."
        ;;
esac
