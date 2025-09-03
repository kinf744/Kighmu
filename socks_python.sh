#!/bin/bash
# socks_python.sh
# Activation du SOCKS Python avec nettoyage des anciennes instances

echo "+--------------------------------------------+"
echo "|             CONFIG SOCKS/PYTHON            |"
echo "+--------------------------------------------+"

read -p "Voulez-vous démarrer le proxy SOCKS/Python ? [oui/non] : " confirm

case "$confirm" in
    [oO][uU][iI]|[yY][eE][sS])
        echo "Vérification du module pysocks..."
        if ! python3 -c "import socks" &> /dev/null; then
            echo "Module pysocks non trouvé, installation en cours..."
            sudo pip3 install --upgrade pip
            sudo pip3 install pysocks python-socks requests[socks]
            if [ $? -ne 0 ]; then
                echo "Erreur lors de l'installation des modules Python. Abandon."
                exit 1
            fi
        else
            echo "Module pysocks déjà installé."
        fi

        PROXY_PORT=8080
        SCRIPT_PATH="/usr/local/bin/KIGHMUPROXY.py"
        SCRIPT_URL="https://raw.githubusercontent.com/kinf744/Kighmu/main/KIGHMUPROXY.py"
        LOG_FILE="/var/log/socks_python.log"

        # Vérifier si le script proxy est présent, sinon le télécharger
        if [ ! -f "$SCRIPT_PATH" ]; then
            echo "Le script proxy $SCRIPT_PATH est introuvable. Téléchargement en cours..."
            sudo wget -q -O "$SCRIPT_PATH" "$SCRIPT_URL"
            if [ $? -ne 0 ]; then
                echo "Erreur : impossible de télécharger le script proxy. Abandon."
                exit 1
            fi
            sudo chmod +x "$SCRIPT_PATH"
            echo "Script proxy téléchargé et rendu exécutable."
        else
            echo "Script proxy trouvé : $SCRIPT_PATH"
        fi

        echo "Recherche d'instances précédentes du proxy SOCKS à arrêter..."
        PIDS=$(pgrep -f "python3 $SCRIPT_PATH")
        if [ -n "$PIDS" ]; then
            echo "Arrêt des instances proxy existantes (PID: $PIDS)..."
            sudo kill $PIDS
            sleep 3
            echo "Instances précédentes arrêtées."
        else
            echo "Aucune instance précédente détectée."
        fi

        echo "Vérification du port $PROXY_PORT..."
        if sudo lsof -i :$PROXY_PORT >/dev/null; then
            echo "Port $PROXY_PORT occupé, veuillez libérer ce port ou modifier le script pour utiliser un autre port."
            exit 1
        fi

        echo "Démarrage du proxy SOCKS/Python sur le port $PROXY_PORT..."
        nohup sudo python3 "$SCRIPT_PATH" "$PROXY_PORT" > "$LOG_FILE" 2>&1 &

        sleep 3

        if pgrep -f "python3 $SCRIPT_PATH" > /dev/null; then
            echo "Proxy SOCKS/Python démarré sur le port $PROXY_PORT."
            echo "Logs disponibles dans $LOG_FILE"
        else
            echo "Échec du démarrage du proxy SOCKS/Python."
            echo "Consultez les logs : $LOG_FILE"
        fi
        ;;
    [nN][oO]|[nN])
        echo "Démarrage annulé."
        ;;
    *)
        echo "Réponse invalide. Annulation."
        ;;
esac
