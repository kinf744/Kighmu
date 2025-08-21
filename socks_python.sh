#!/bin/bash
# socks_python.sh
# Activation du SOCKS Python avec configuration simple

echo "+--------------------------------------------+"
echo "|             CONFIG SOCKS/PYTHON            |"
echo "+--------------------------------------------+"

read -p "Voulez-vous démarrer le proxy SOCKS/Python ? [oui/non] : " confirm

case "$confirm" in
    [oO][uU][iI]|[yY][eE][sS])
        echo "Vérification du module pysocks..."
        if ! python3 -c "import socks" &> /dev/null; then
            echo "Module pysocks non trouvé, installation en cours..."
            sudo pip3 install pysocks python-socks
        else
            echo "Module pysocks déjà installé."
        fi

        PROXY_PORT=8080
        echo "Vérification du port $PROXY_PORT..."
        if sudo lsof -i :$PROXY_PORT >/dev/null; then
            echo "Port $PROXY_PORT occupé, veuillez libérer ce port ou modifier le script pour utiliser un autre port."
            exit 1
        fi

        echo "Démarrage du proxy SOCKS/Python sur le port $PROXY_PORT..."
        nohup python3 /chemin/vers/kighmu_proxy.py $PROXY_PORT > /var/log/socks_python.log 2>&1 &

        sleep 3

        if pgrep -f "python3 /chemin/vers/kighmu_proxy.py" > /dev/null; then
            echo "Proxy SOCKS/Python démarré sur le port $PROXY_PORT."
            echo "Logs disponibles dans /var/log/socks_python.log"
        else
            echo "Échec du démarrage du proxy SOCKS/Python."
            echo "Consultez les logs : /var/log/socks_python.log"
        fi
        ;;
    [nN][oO]|[nN])
        echo "Démarrage annulé."
        ;;
    *)
        echo "Réponse invalide. Annulation."
        ;;
esac
