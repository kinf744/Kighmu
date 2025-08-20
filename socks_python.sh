#!/bin/bash
# socks_python.sh
# Activation du proxy SOCKS basé sur KIGHMUSSH Python

echo "+--------------------------------------------+"
echo "|             CONFIG PROXY KIGHMUSSH         |"
echo "+--------------------------------------------+"

read -p "Voulez-vous démarrer le proxy KIGHMUSSH Python SOCKS sur le port 8080 ? [oui/non] : " confirm

case "$confirm" in
    [oO][uU][iI]|[yY][eE][sS])
        echo "Vérification de Python3..."
        if ! command -v python3 >/dev/null 2>&1; then
            echo "Python3 non trouvé, installation en cours..."
            sudo apt update
            sudo apt install -y python3 python3-pip
        else
            echo "Python3 déjà installé."
        fi

        PROXY_PORT=8080
        PROXY_SCRIPT="/usr/local/bin/KIGHMUSSH.py"
        LOG_FILE="/var/log/kighmussh.log"

        # Téléchargement du script proxy SOCKS KIGHMUSSH
        echo "Téléchargement du script proxy SOCKS KIGHMUSSH..."
        sudo wget -q -O "$PROXY_SCRIPT" "https://raw.githubusercontent.com/kinf744/Kighmu/main/KIGHMUSSH.py"
        sudo chmod +x "$PROXY_SCRIPT"

        echo "Vérification du port $PROXY_PORT..."
        if sudo lsof -i :$PROXY_PORT >/dev/null; then
            echo "Port $PROXY_PORT occupé, veuillez libérer ce port ou modifier le script pour utiliser un autre port."
            exit 1
        fi

        echo "Arrêt des anciens processus KIGHMUSSH..."
        sudo pkill -f "$PROXY_SCRIPT" || true

        echo "Démarrage du proxy KIGHMUSSH SOCKS sur le port $PROXY_PORT..."
        nohup sudo python3 "$PROXY_SCRIPT" $PROXY_PORT > "$LOG_FILE" 2>&1 &

        sleep 3

        if pgrep -f "$PROXY_SCRIPT" > /dev/null; then
            echo "Proxy KIGHMUSSH SOCKS lancé avec succès sur le port $PROXY_PORT."
            echo "Logs disponibles dans $LOG_FILE"
        else
            echo "Échec du démarrage du proxy KIGHMUSSH SOCKS. Consultez $LOG_FILE"
        fi
        ;;
    [nN][oO]|[nN])
        echo "Démarrage annulé."
        ;;
    *)
        echo "Réponse invalide. Annulation."
        ;;
esac
