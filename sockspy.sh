#!/bin/bash
# sockspy.sh
# Installation / activation du proxy SOCKS Python WebSocket via systemd

echo "+--------------------------------------------+"
echo "|        CONFIG SOCKS/PYTHON WS              |"
echo "+--------------------------------------------+"

# Port par défaut
DEFAULT_PORT=80
PORT=${2:-$DEFAULT_PORT}

# Gestion paramètre auto bypass prompt
if [ "$1" == "auto" ]; then
    confirm="oui"
else
    read -p "Voulez-vous démarrer le proxy SOCKS/PYTHON WS sur le port $PORT ? [oui/non] : " confirm
fi

install_pysocks() {
  echo "Installation du module Python pysocks..."

  if sudo apt-get install -y python3-socks; then
    echo "Module pysocks installé via apt avec succès."
    return 0
  fi

  echo "Le paquet python3-socks n'est pas disponible via apt ou l'installation a échoué."

  if ! dpkg -s python3-venv &> /dev/null; then
    echo "Installation de python3-venv..."
    if ! sudo apt-get install -y python3-venv; then
      echo "Échec de l'installation de python3-venv, abandon."
      return 1
    fi
  fi

  VENV_DIR="$HOME/socksenv"
  if [[ ! -d "$VENV_DIR" ]]; then
    echo "Création de l'environnement virtuel Python dans $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
  fi

  source "$VENV_DIR/bin/activate"

  if ! pip install --upgrade pip setuptools && pip install pysocks; then
    echo "Échec de l'installation de pysocks via pip."
    deactivate
    return 1
  fi

  deactivate
  echo "Module pysocks installé dans l'environnement virtuel $VENV_DIR."
  echo "Activez-le avec : source $VENV_DIR/bin/activate"
  return 0
}

check_ufw() {
  if ! command -v ufw &> /dev/null; then
    echo "UFW non détecté. Voulez-vous installer UFW ? [oui/non]"
    read -r ans
    if [[ "$ans" =~ ^(o|oui|y|yes)$ ]]; then
      sudo apt-get update
      sudo apt-get install -y ufw
      sudo ufw enable
      sudo ufw allow ssh
    else
      echo "Attention : UFW non installé. Le port $PORT ne sera pas autorisé automatiquement."
    fi
  fi
}

create_systemd_service() {
  SERVICE_PATH="/etc/systemd/system/socks_python_ws.service"
  SCRIPT_PATH="/usr/local/bin/ws2_proxy.py"

  echo "Création du service systemd socks_python_ws.service..."

  sudo tee "$SERVICE_PATH" > /dev/null <<EOF
[Unit]
Description=Proxy SOCKS/PYTHON WS - port $PORT
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 $SCRIPT_PATH $PORT
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=socks-python-ws-proxy

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable socks_python_ws.service
  sudo systemctl restart socks_python_ws.service
  echo "Service socks_python_ws activé et démarré sur le port $PORT."
}

kill_old_instances() {
  PIDS=$(pgrep -f "ws2_proxy.py")
  if [ -n "$PIDS" ]; then
    echo "Arrêt des anciennes instances du proxy WS (PID: $PIDS)..."
    sudo kill -9 $PIDS
    sleep 3
  fi
}

case "$confirm" in
  [oO][uU][iI]|[yY][eE][sS])
    echo "Vérification du module pysocks..."
    if ! python3 -c "import socks" &> /dev/null; then
      echo "Module pysocks absent, installation requise."
      if ! install_pysocks; then
        echo "Erreur installation pysocks, abandon."
        exit 1
      fi
    else
      echo "Module pysocks déjà installé."
    fi

    check_ufw

    echo "Autorisation du port $PORT dans le firewall UFW..."
    sudo ufw allow "$PORT"/tcp

    SCRIPT_PATH="/usr/local/bin/ws2_proxy.py"
    SCRIPT_URL="https://raw.githubusercontent.com/kinf744/Kighmu/main/ws2_proxy.py"

    if [ ! -f "$SCRIPT_PATH" ] || [ $(( $(date +%s) - $(stat -c %Y "$SCRIPT_PATH") )) -ge 86400 ]; then
      echo "Téléchargement / mise à jour du script proxy..."
      sudo wget -q -O "$SCRIPT_PATH" "$SCRIPT_URL" || { echo "Erreur téléchargement."; exit 1; }
      sudo chmod +x "$SCRIPT_PATH"
      echo "Script proxy prêt à l'emploi."
    else
      echo "Script proxy à jour : $SCRIPT_PATH"
    fi

    kill_old_instances

    if sudo lsof -i :"$PORT" >/dev/null; then
      echo "Le port $PORT est déjà utilisé, veuillez le libérer."
      exit 1
    fi

    create_systemd_service

    echo "Vérifier les logs : sudo journalctl -u socks_python_ws.service"
    ;;
  *)
    echo "Installation annulée."
    exit 1
    ;;
esac
