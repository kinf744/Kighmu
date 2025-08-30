#!/bin/bash

# Demander le domaine à configurer
read -p "Merci de saisir le domaine à configurer (exemple: monsite.exemple.com) : " DOMAIN

if [ -z "$DOMAIN" ]; then
  echo "Erreur : le domaine ne peut pas être vide."
  exit 1
fi

# Mise à jour du système et installation de nginx
sudo apt update
sudo apt install -y nginx

# Créer la configuration nginx pour écouter sur le port 81
cat << EOF | sudo tee /etc/nginx/sites-available/$DOMAIN
server {
    listen 81;
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

# Activer la configuration en créant un lien symbolique
sudo ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

# Tester la configuration nginx
sudo nginx -t

# Recharger nginx pour appliquer la nouvelle configuration
sudo systemctl reload nginx

# Ouvrir le port 81 dans le firewall (si ufw est activé)
sudo ufw allow 81/tcp

echo "Nginx est installé et configuré pour écouter sur le port 81 avec proxy WebSocket pour le domaine $DOMAIN."
echo "Note : Le port 80 est réservé à wstunnel/tunnel SSH WebSocket, donc nginx utilise le port 81."
