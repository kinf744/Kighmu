#!/bin/bash
# socks_python.sh
# Activation du SOCKS Python avec nettoyage des anciennes instances, configuration UFW et service systemd

echo "+--------------------------------------------+"
echo "|             CONFIG SOCKS/PYTHON            |"
echo "+--------------------------------------------+"

create_systemd_service() {
  SERVICE_PATH="/etc/systemd/system/socks_python.service"
  PROXY_PORT=8080
  SCRIPT_PATH="/usr/local/bin/KIGHMUPROXY.py"

  echo "Création du fichier systemd socks_python.service..."

  sudo tee "$SERVICE_PATH" > /dev/null <<EOF
[Unit]
Description=Proxy SOCKS Python
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 $SCRIPT_PATH $PROXY_PORT
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=socks-python-proxy

[Install]
WantedBy=multi-user.target
EOF

  echo "Reload systemd, enable and start the service socks_python..."
  sudo systemctl daemon-reload
  sudo systemctl enable socks_python.service
  sudo systemctl restart socks_python.service
  echo "Service socks_python activé et démarré."
}

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

        echo "Configuration du firewall UFW pour autoriser le port $PROXY_PORT..."
        sudo ufw allow $PROXY_PORT/tcp
        echo "Port $PROXY_PORT autorisé dans UFW."

        DOWNLOAD_SCRIPT=false
        if [ ! -f "$SCRIPT_PATH" ]; then
            echo "Script proxy absent, téléchargement en cours..."
            DOWNLOAD_SCRIPT=true
        else
            FILE_AGE=$(( $(date +%s) - $(stat -c %Y "$SCRIPT_PATH") ))
            if [ $FILE_AGE -ge 86400 ]; then
                echo "Script proxy date dépassée (plus d'un jour), re-téléchargement..."
                DOWNLOAD_SCRIPT=true
            fi
        fi

        if $DOWNLOAD_SCRIPT; then
            sudo wget -q -O "$SCRIPT_PATH" "$SCRIPT_URL"
            if [ $? -ne 0 ]; then
                echo "Erreur : téléchargement du script proxy échoué."
                exit 1
            fi
            sudo chmod +x "$SCRIPT_PATH"
            echo "Script proxy téléchargé et rendu exécutable."
        else
            echo "Script proxy trouvé et valide : $SCRIPT_PATH"
        fi

        echo "Recherche d'instances précédentes du proxy SOCKS à arrêter..."
        PIDS=$(pgrep -f "python3 $SCRIPT_PATH")
        if [ -n "$PIDS" ]; then
            echo "Arrêt des instances proxy (PID: $PIDS)..."
            sudo kill -9 $PIDS
            sleep 5
            if pgrep -f "python3 $SCRIPT_PATH" > /dev/null; then
                echo "Certaines instances n'ont pas été arrêtées, veuillez vérifier."
                exit 1
            fi
            echo "Instances arrêtées."
        else
            echo "Aucune instance précédente détectée."
        fi

        echo "Vérification du port $PROXY_PORT..."
        if sudo lsof -i :$PROXY_PORT >/dev/null; then
            echo "Le port $PROXY_PORT est occupé. Veuillez libérer ce port ou modifier la configuration."
            exit 1
        fi

        echo "Démarrage du proxy SOCKS/Python sur le port $PROXY_PORT..."
        nohup sudo python3 "$SCRIPT_PATH" "$PROXY_PORT" > "$LOG_FILE" 2>&1 &

        sleep 4

        if pgrep -f "python3 $SCRIPT_PATH" > /dev/null; then
            echo "Proxy SOCKS/Python démarré sur le port $PROXY_PORT."
            echo "Vérifiez les logs dans : $LOG_FILE"
            create_systemd_service
        else
            echo "Échec du démarrage du proxy SOCKS/Python."
            echo "Consultez les logs pour diagnostic : $LOG_FILE"
        fi
        ;;
    [nN][oO]|[nN])
        echo "Démarrage annulé."
        ;;
    *)
        echo "Réponse invalide. Abandon."
        ;;
esac
