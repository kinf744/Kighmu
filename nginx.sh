#!/bin/bash

# Demande du domaine à l'utilisateur
read -p "Merci de saisir le domaine à configurer (exemple: monsite.exemple.com) : " DOMAIN

if [ -z "$DOMAIN" ]; then
  echo "Erreur : le domaine ne peut pas être vide."
  exit 1
fi

# Mise à jour et installation de nginx
sudo apt update
sudo apt install -y nginx

# Création de la configuration nginx avec le domaine spécifié et proxy WebSocket sur port 81
cat << EOF | sudo tee /etc/nginx/sites-available/$DOMAIN
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:81;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
EOF

# Activation de la configuration
sudo ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

# Test de la configuration nginx
sudo nginx -t

# Reload nginx pour appliquer la configuration
sudo systemctl reload nginx

echo "Nginx installé et configuré avec proxy WebSocket pour le domaine $DOMAIN sur le port 81."
