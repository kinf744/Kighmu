#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "Ce script doit être exécuté en root ou avec sudo."
   exit 1
fi

read -p "Entrez le domaine/IP public pour le tunnel SSH HTTP WS (ex: exemple.com) : " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo "Erreur : domaine obligatoire."
  exit 1
fi

APP_DIR="/root/custom-http"
NGINX_CONF="/etc/nginx/sites-available/ssh_ws_proxy"
NGINX_ENABLED="/etc/nginx/sites-enabled/ssh_ws_proxy"
NGINX_MAIN_CONF="/etc/nginx/nginx.conf"

# Cloner ou mettre à jour dépôt
if [ ! -d "$APP_DIR" ]; then
  git clone https://github.com/tavgar/Custom-http.git "$APP_DIR"
else
  cd "$APP_DIR" && git pull
fi

# Installer dépendances Python manuellement
pip3 install --upgrade paramiko websocket-client

# Arrêter processus sur port 80
pids=$(lsof -ti tcp:80)
if [ -n "$pids" ]; then
  echo "Arrêt des processus sur port 80: $pids"
  kill -9 $pids
fi

# Ajouter map connection_upgrade dans /etc/nginx/nginx.conf si absente
if ! grep -q "map \$http_upgrade \$connection_upgrade" "$NGINX_MAIN_CONF"; then
  sed -i '/http {/a \
map $http_upgrade $connection_upgrade {\n\
    default upgrade;\n\
    ""      close;\n\
}\n' "$NGINX_MAIN_CONF"
fi

# Écrire config NGINX pour proxy WebSocket HTTP custom
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

# Tester et recharger NGINX
nginx -t || { echo "Erreur config nginx"; exit 1; }
if systemctl is-active --quiet nginx; then
  systemctl reload nginx
else
  systemctl start nginx
fi

# Lancer le proxy Python du dépôt
nohup python3 "$APP_DIR/main.py" > "$APP_DIR/proxyws.log" 2>&1 &

echo "Tunnel SSH HTTP WS custom payload actif sur ws://$DOMAIN/ws/"
echo "Consultez $APP_DIR/proxyws.log pour les logs."
