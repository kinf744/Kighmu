#!/bin/bash
# socks_python.sh
# Activation du SOCKS Python avec persistance via systemd

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
        SCRIPT_PATH="/usr/local/bin/KIGHMUPROXY.py"
        LOG_FILE="/var/log/socks_python.log"
        SERVICE_FILE="/etc/systemd/system/socks_python.service"

        echo "Vérification du port $PROXY_PORT..."
        if sudo lsof -i :$PROXY_PORT >/dev/null; then
            echo "Port $PROXY_PORT occupé, veuillez libérer ce port ou modifier le script pour utiliser un autre port."
            exit 1
        fi

        # Création du fichier service systemd
        sudo tee $SERVICE_FILE > /dev/null << EOF
[Unit]
Description=SOCKS Python Proxy Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/env python3 $SCRIPT_PATH $PROXY_PORT
Restart=always
RestartSec=5
User=root
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

[Install]
WantedBy=multi-user.target
EOF

        # Recharge systemd, active et démarre le service
        sudo systemctl daemon-reload
        sudo systemctl enable socks_python.service
        sudo systemctl start socks_python.service

        # Vérification du démarrage
        if systemctl is-active --quiet socks_python.service; then
            echo "Proxy SOCKS Python démarré et activé au démarrage automatique."
            echo "Logs disponibles dans $LOG_FILE"
        else
            echo "ERREUR : Le proxy SOCKS Python n'a pas pu démarrer via systemd."
            exit 1
        fi
        ;;
    [nN][oO]|[nN])
        echo "Démarrage annulé."
        ;;
    *)
        echo "Réponse invalide. Annulation."
        ;;
esac
