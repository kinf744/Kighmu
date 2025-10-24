#!/bin/bash
# socks_python.sh
# Gestion dynamique du port SOCKS, nettoyage complet du config, installation pysocks, UFW et systemd

set -euo pipefail

echo "+--------------------------------------------+"
echo "|             CONFIG SOCKS/PYTHON            |"
echo "+--------------------------------------------+"

# Variables globales
CONF_DIR="/etc/socks_python"
SCRIPT_PATH="/usr/local/bin/KIGHMUPROXY.py"
SCRIPT_URL="https://raw.githubusercontent.com/kinf744/Kighmu/main/KIGHMUPROXY.py"
LOG_FILE="/var/log/socks_python.log"
CONFIG_PORT_FILE="$CONF_DIR/socks_port.conf"
DOWNLOAD_SCRIPT=true

# Création du dossier config si nécessaire
sudo mkdir -p "$CONF_DIR"
sudo chown "$USER":"$USER" "$CONF_DIR"

ask_port() {
  local port_input=""
  while true; do
    read -e -p "Saisissez le port SOCKS à utiliser pour cette installation (entre 1024 et 65535, aucun défaut) : " port_input
    if [[ "$port_input" =~ ^[0-9]+$ ]] && [ "$port_input" -ge 1024 ] && [ "$port_input" -le 65535 ]; then
      echo "$port_input"
      return
    else
      echo "Port invalide. Saisissez un nombre entre 1024 et 65535."
    fi
  done
}

cleanup_port() {
  local port=$1
  echo "Nettoyage complet du port $port..."

  # Tuer tous processus écoutant sur le port
  local PIDS
  PIDS=$(sudo lsof -ti :$port 2>/dev/null || true)
  if [ -n "$PIDS" ]; then
    echo "Arrêt des processus occupés sur le port $port (PID: $PIDS)..."
    sudo kill -9 $PIDS || true
  else
    echo "Aucun processus sur le port $port détecté."
  fi

  # Désactiver et arrêter le service systemd socks_python.service s'il existe
  if systemctl list-units --full -all | grep -q "socks_python.service"; then
    echo "Arrêt et désactivation du service systemd socks_python.service..."
    sudo systemctl stop socks_python.service || true
    sudo systemctl disable socks_python.service || true
    sudo systemctl daemon-reload
  else
    echo "Aucun service systemd socks_python.service actif trouvé."
  fi

  sleep 3

  # Vérification finale port libre
  if sudo lsof -ti :$port >/dev/null 2>&1; then
    echo "Attention : le port $port est encore occupé après tentative de nettoyage."
    return 1
  else
    echo "Le port $port est désormais libre."
    return 0
  fi
}

install_pysocks() {
  echo "Installation du module Python pysocks..."

  sudo mkdir -p "$CONF_DIR"
  sudo chown "$USER":"$USER" "$CONF_DIR"

  if sudo apt-get update -y && sudo apt-get install -y python3-socks; then
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
  echo "Installation de pysocks via pip dans l'environnement virtuel..."
  if ! pip install --upgrade pip setuptools && pip install pysocks; then
    echo "Échec de l'installation de pysocks via pip dans l'environnement virtuel."
    deactivate
    return 1
  fi

  deactivate
  echo "Module pysocks installé avec succès dans l'environnement virtuel $VENV_DIR."
  echo "Pour l'utiliser, activez cet environnement avec : source $VENV_DIR/bin/activate"
  return 0
}

create_systemd_service() {
  SERVICE_PATH="/etc/systemd/system/socks_python.service"
  local port=$1
  echo "Création du fichier systemd socks_python.service..."
  if [ -f "$SERVICE_PATH" ]; then
    sudo rm -f "$SERVICE_PATH"
  fi

  sudo tee "$SERVICE_PATH" > /dev/null <<EOF
[Unit]
Description=Proxy SOCKS Python
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 $SCRIPT_PATH $port
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
        # Saisie du port à chaque installation
        PROXY_PORT="$(ask_port)"

        echo "Nettoyage complet du fichier socks_port.conf..."
        sudo rm -f "$CONFIG_PORT_FILE"
        echo "$PROXY_PORT" | sudo tee "$CONFIG_PORT_FILE" > /dev/null

        if ! cleanup_port "$PROXY_PORT"; then
          echo "Erreur : échec de nettoyage du port. Abandon."
          exit 1
        fi

        echo "Vérification du module pysocks..."
        if ! python3 -c "import socks" &> /dev/null; then
            echo "Module pysocks non trouvé, installation en cours..."
            if ! install_pysocks; then
                echo "Erreur lors de l'installation des modules Python. Abandon."
                exit 1
            fi
        else
            echo "Module pysocks déjà installé."
        fi

        if [ ! -f "$SCRIPT_PATH" ]; then
            echo "Script proxy absent, téléchargement en cours..."
            sudo mkdir -p "$(dirname "$SCRIPT_PATH")"
            sudo wget -q -O "$SCRIPT_PATH" "$SCRIPT_URL"
            if [ $? -ne 0 ]; then
                echo "Erreur : téléchargement du script proxy échoué."
                exit 1
            fi
            sudo chmod +x "$SCRIPT_PATH"
            echo "Script proxy téléchargé et rendu exécutable."
        else
            echo "Script proxy trouvé : $SCRIPT_PATH"
        fi

        echo "Recherche d'instances précédentes du proxy SOCKS à arrêter..."
        PIDS=$(pgrep -f "python3 $SCRIPT_PATH" || true)
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

        echo "Configuration du firewall UFW pour autoriser le port $PROXY_PORT..."
        sudo ufw allow $PROXY_PORT/tcp
        echo "Port $PROXY_PORT autorisé dans UFW."

        echo "Vérification du port $PROXY_PORT..."
        if sudo lsof -i :$PROXY_PORT >/dev/null 2>&1; then
            echo "Le port $PROXY_PORT est occupé. Veuillez libérer ce port ou modifier la configuration."
            exit 1
        fi

        echo "Démarrage du proxy SOCKS/Python sur le port $PROXY_PORT..."
        nohup sudo python3 "$SCRIPT_PATH" "$PROXY_PORT" > "$LOG_FILE" 2>&1 &

        sleep 4

        if pgrep -f "python3 $SCRIPT_PATH" > /dev/null; then
            echo "Proxy SOCKS/Python démarré sur le port $PROXY_PORT."
            echo "Vérifiez les logs dans : $LOG_FILE"
            create_systemd_service "$PROXY_PORT"
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
