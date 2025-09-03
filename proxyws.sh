#!/bin/bash

# proxyws.sh - Tunnel SSH WebSocket avec arrêt port 80, config NGINX, demande domaine

if [[ $EUID -ne 0 ]]; then
   echo "Ce script doit être exécuté avec sudo ou root."
   exit 1
fi

# Demande du domaine à utiliser
read -p "Entrez le domaine/IP public à utiliser pour le tunnel SSH HTTP WS (ex: exemple.com) : " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo "Erreur : domaine obligatoire."
  exit 1
fi

SCRIPT_PATH="./ws_proxy.py"
SCRIPT_URL="https://raw.githubusercontent.com/votreuser/votre-repo/main/ws_proxy.py"
NGINX_CONF="/etc/nginx/sites-available/ssh_ws_proxy"
NGINX_ENABLED="/etc/nginx/sites-enabled/ssh_ws_proxy"

# Téléchargement du script Python si absent
if [ ! -f "$SCRIPT_PATH" ]; then
  echo "Script $SCRIPT_PATH introuvable. Téléchargement en cours..."
  curl -fsSL -o "$SCRIPT_PATH" "$SCRIPT_URL"
  if [ $? -ne 0 ]; then
    echo "Erreur téléchargement de $SCRIPT_PATH."
    exit 1
  fi
  chmod +x "$SCRIPT_PATH"
  echo "Téléchargement terminé."
fi

# Arrêter tous les processus utilisant le port 80
echo "Arrêt de tous les processus sur le port 80..."
pids=$(lsof -ti tcp:80)
if [ -n "$pids" ]; then
  echo "Processus détectés: $pids"
  kill -9 $pids
  echo "Processus arrêtés."
else
  echo "Aucun processus sur le port 80."
fi

# Création configuration NGINX
cat > $NGINX_CONF << EOF
server {
    listen 80;
    server_name $DOMAIN;

    location /ws/ {
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;

        proxy_pass http://127.0.0.1:8765;
    }
}
EOF

echo "Activation configuration NGINX..."
ln -sf $NGINX_CONF $NGINX_ENABLED

echo "Test de la configuration NGINX..."
nginx -t || { echo "Erreur configuration NGINX"; exit 1; }

echo "Reload NGINX..."
systemctl reload nginx

# Lancer le serveur Python SSH WebSocket
nohup python3 "$SCRIPT_PATH" -b 127.0.0.1 -p 8765 > proxyws.log 2>&1 &

sleep 2

echo "Tunnel SSH WebSocket actif sur ws://$DOMAIN/ws/"
echo "Logs : proxyws.log"
