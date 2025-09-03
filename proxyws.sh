#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "Ce script doit être exécuté avec sudo ou root."
   exit 1
fi

read -p "Entrez le domaine/IP public pour le tunnel SSH HTTP WS (ex: exemple.com) : " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo "Erreur : domaine obligatoire."
  exit 1
fi

SCRIPT_PATH="./ws_proxy.py"
SCRIPT_URL="https://raw.githubusercontent.com/kinf744/Kighmu/main/ws_proxy.py"
NGINX_CONF="/etc/nginx/sites-available/ssh_ws_proxy"
NGINX_ENABLED="/etc/nginx/sites-enabled/ssh_ws_proxy"
NGINX_CONF_MAIN="/etc/nginx/nginx.conf"

# Téléchargement script Python
if [ ! -f "$SCRIPT_PATH" ]; then
  echo "Script $SCRIPT_PATH introuvable. Téléchargement..."
  curl -fsSL -o "$SCRIPT_PATH" "$SCRIPT_URL" || { echo "Erreur téléchargement."; exit 1; }
  chmod +x "$SCRIPT_PATH"
fi

# Arrêt processus sur port 80
pids=$(lsof -ti tcp:80)
if [ -n "$pids" ]; then
  echo "Arrêt des processus sur port 80: $pids"
  kill -9 $pids
fi

# Ajout de la map pour gérer le header Connection dans nginx.conf s'il n'existe pas déjà
if ! grep -q "map \$http_upgrade \$connection_upgrade" "$NGINX_CONF_MAIN"; then
  echo "Ajout de la map \$connection_upgrade dans $NGINX_CONF_MAIN"
  sed -i '/http {/a \
map $http_upgrade $connection_upgrade {\n\
    default upgrade;\n\
    ""      close;\n\
}\n' "$NGINX_CONF_MAIN"
fi

# Ecriture config NGINX pour le reverse proxy WebSocket
cat > $NGINX_CONF << EOF
server {
    listen 80;
    server_name $DOMAIN;

    location /ws/ {
        proxy_pass http://127.0.0.1:80;
        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_buffering off;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
EOF

ln -sf $NGINX_CONF $NGINX_ENABLED

# Test et reload nginx
nginx -t || { echo "Erreur config nginx"; exit 1; }
if systemctl is-active --quiet nginx; then
    systemctl reload nginx
else
    systemctl start nginx
fi

# Démarrage script python websocket proxy
nohup python3 "$SCRIPT_PATH" > proxyws.log 2>&1 &

sleep 2

echo "Tunnel SSH WebSocket actif sur ws://$DOMAIN/ws/"
echo "Logs : proxyws.log"
