#!/bin/bash

DOMAIN="votre.domaine.com"
PROXY_PORT=80
NGINX_PORT=81
APP_DIR="/root/custom-http"

# Installer dépendances
apt update && apt install -y python3 python3-pip nginx git
pip3 install --upgrade paramiko websocket-client

# Cloner ou mettre à jour le dépôt proxy
if [ ! -d "$APP_DIR" ]; then
  git clone https://github.com/tavgar/Custom-http.git "$APP_DIR"
else
  cd "$APP_DIR" && git pull
fi

# Créer le fichier de config personnalisé
cat > "$APP_DIR/config.py" << EOF
CONFIG = {
    'DOMAIN': '$DOMAIN',
    'PROXY_HOST': '0.0.0.0',
    'PROXY_PORT': $PROXY_PORT,
    'SSH_HOST': '127.0.0.1',
    'SSH_PORT': 22,
    'SSH_USER': 'utilisateur_ssh',
    'SSH_PASS': 'motdepasse_ssh',
    'PAYLOAD_TEMPLATE': (
        "GET /ws/ HTTP/1.1\\r\\n"
        "Host: $DOMAIN\\r\\n"
        "User-Agent: CustomClient/1.0\\r\\n"
        "Upgrade: websocket\\r\\n"
        "Connection: Upgrade\\r\\n"
        "Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==\\r\\n"
        "Sec-WebSocket-Version: 13\\r\\n"
        "\\r\\n"
    ),
    'SOCKS_LOCAL_PORT': 1080,
}
EOF

# Configurer NGINX en reverse proxy websocket sur le port 81
cat > /etc/nginx/sites-available/ssh_ws_proxy << EOF
server {
    listen $NGINX_PORT;
    server_name $DOMAIN;

    location /ws/ {
        proxy_pass http://127.0.0.1:$PROXY_PORT;
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

ln -sf /etc/nginx/sites-available/ssh_ws_proxy /etc/nginx/sites-enabled/ssh_ws_proxy

# Assurer le paramètre map dans nginx.conf
if ! grep -q "map \$http_upgrade \$connection_upgrade" /etc/nginx/nginx.conf; then
  sed -i '/http {/a \
map $http_upgrade $connection_upgrade {\n\
    default upgrade;\n\
    ""      close;\n\
}' /etc/nginx/nginx.conf
fi

# Tester et recharger nginx
nginx -t && systemctl reload nginx

# Lancer le proxy Python en arrière-plan
nohup python3 "$APP_DIR/main.py" > "$APP_DIR/proxyws.log" 2>&1 &

echo "Tunnel SSH HTTP WS personnalisé actif sur ws://$DOMAIN:$NGINX_PORT/ws/"
echo "Modifiez utilisateur_ssh et motdepasse_ssh dans $APP_DIR/config.py"
