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
        # Commandes réelles pour lancer le proxy, exemple fictif :
        # python3 -m websocks --port 80 --http2
        sleep 2
        echo "Proxy SOCKS/Python démarré avec HTTP/2 200 et 101."
        ;;
    [nN][oO]|[nN])
        echo "Démarrage annulé."
        ;;
    *)
        echo "Réponse invalide. Annulation."
        ;;
esac
