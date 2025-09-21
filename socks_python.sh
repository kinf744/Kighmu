#!/bin/bash
set -e

LOG_FILE="/var/log/socks_python.log"
LOGROTATE_CONF="/etc/logrotate.d/socks_python"

echo "+--------------------------------------------+"
echo "|             CONFIG SOCKS/PYTHON            |"
echo "+--------------------------------------------+"

install_pysocks() {
  echo "Installation du module Python pysocks..."

  if sudo apt-get install -y python3-socks; then
    echo "Module pysocks installé via apt avec succès."
    return 0
  fi

  echo "Le paquet python3-socks n'est pas disponible via apt ou l'installation a échoué."

  if ! dpkg -s python3-venv &> /dev/null; then
    echo "Installation de python3-venv..."
    sudo apt-get install -y python3-venv
  fi

  VENV_DIR="$HOME/socksenv"
  if [[ ! -d "$VENV_DIR" ]]; then
    echo "Création de l'environnement virtuel Python dans $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
  fi

  source "$VENV_DIR/bin/activate"

  echo "Installation de pysocks via pip dans l'environnement virtuel..."
  pip install --upgrade pip setuptools
  pip install pysocks

  deactivate
  echo "Module pysocks installé avec succès dans $VENV_DIR."
}

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

  sudo systemctl daemon-reload
  sudo systemctl enable socks_python.service
  sudo systemctl restart socks_python.service
  echo "Service socks_python activé et démarré."
}

create_logrotate_config() {
  if [ ! -f "$LOG_FILE" ]; then
    sudo touch "$LOG_FILE"
    sudo chown root:root "$LOG_FILE"
    sudo chmod 640 "$LOG_FILE"
    echo "Fichier log $LOG_FILE créé et permissions définies."
  fi

  sudo tee "$LOGROTATE_CONF" > /dev/null <<EOF
$LOG_FILE {
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
    create 0640 root root
    sharedscripts
    postrotate
        systemctl restart socks_python.service > /dev/null 2>&1 || true
    endscript
}
EOF
  echo "Configuration logrotate écrite dans $LOGROTATE_CONF"
}

read -p "Voulez-vous démarrer le proxy SOCKS/Python ? [oui/non] : " confirm
case "$confirm" in
  [oO][uU][iI]|[yY][eE][sS])
    if ! python3 -c "import socks" &> /dev/null; then
      echo "Module pysocks non trouvé, installation en cours..."
      install_pysocks
    else
      echo "Module pysocks déjà installé."
    fi

    PROXY_PORT=8080
    SCRIPT_PATH="/usr/local/bin/KIGHMUPROXY.py"
    SCRIPT_URL="https://raw.githubusercontent.com/kinf744/Kighmu/main/KIGHMUPROXY.py"

    sudo ufw allow $PROXY_PORT/tcp
    echo "Port $PROXY_PORT autorisé dans UFW."

    DOWNLOAD_SCRIPT=false
    if [ ! -f "$SCRIPT_PATH" ]; then
      DOWNLOAD_SCRIPT=true
    else
      FILE_AGE=$(( $(date +%s) - $(stat -c %Y "$SCRIPT_PATH") ))
      if [ $FILE_AGE -ge 86400 ]; then
        DOWNLOAD_SCRIPT=true
      fi
    fi

    if $DOWNLOAD_SCRIPT; then
      sudo wget -q -O "$SCRIPT_PATH" "$SCRIPT_URL"
      sudo chmod +x "$SCRIPT_PATH"
      echo "Script proxy téléchargé et rendu exécutable."
    else
      echo "Script proxy trouvé et valide : $SCRIPT_PATH"
    fi

    PIDS=$(pgrep -f "python3 $SCRIPT_PATH")
    if [ -n "$PIDS" ]; then
      sudo kill -9 $PIDS
      sleep 5
    fi

    if sudo lsof -i :$PROXY_PORT >/dev/null; then
      echo "Le port $PROXY_PORT est occupé, veuillez libérer ou modifier la configuration."
      exit 1
    fi

    nohup sudo python3 "$SCRIPT_PATH" "$PROXY_PORT" > "$LOG_FILE" 2>&1 &

    sleep 4

    if pgrep -f "python3 $SCRIPT_PATH" >/dev/null; then
      echo "Proxy SOCKS/Python démarré sur le port $PROXY_PORT."
      echo "Vérifiez les logs dans : $LOG_FILE"
      create_systemd_service
      create_logrotate_config
    else
      echo "Échec du démarrage du proxy SOCKS/Python."
    fi
    ;;
  *)
    echo "Démarrage annulé."
    ;;
esac
