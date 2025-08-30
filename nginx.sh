#!/bin/bash

# Demander le domaine à configurer
read -p "Merci de saisir le domaine à configurer (exemple: monsite.exemple.com) : " DOMAIN

if [ -z "$DOMAIN" ]; then
  echo "Erreur : le domaine ne peut pas être vide."
  exit 1
fi

echo "Mise à jour du système et installation des prérequis..."
sudo apt update
sudo apt upgrade -y
sudo apt install -y curl nginx ufw

echo "Installation de Node.js version 18 LTS..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

echo "Installation de pm2 globalement..."
sudo npm install -g pm2

# Aller dans le dossier projet (à adapter)
PROJECT_DIR="/home/ubuntu/projet_node"  # Remplacez ce chemin

if [ ! -d "$PROJECT_DIR" ]; then
  echo "Erreur : le dossier projet $PROJECT_DIR n'existe pas."
  exit 1
fi

cd "$PROJECT_DIR"

echo "Installation des dépendances Node.js..."
npm install

echo "Démarrage du serveur Node.js avec pm2..."
pm2 start server.js --name websocket-server --watch
pm2 save
pm2 startup systemd -u $(whoami) --hp $HOME

echo "Configuration de nginx pour proxy WebSocket sur le port 81..."

sudo tee /etc/nginx/sites-available/$DOMAIN > /dev/null <<EOF
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

        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

echo "Test de la configuration nginx..."
sudo nginx -t || exit 1

echo "Rechargement de nginx..."
sudo systemctl reload nginx

echo "Ouverture du port 81 dans le firewall..."
sudo ufw allow 81/tcp

echo "Installation et configuration terminées."
echo "Node.js écoute sur le port 81, nginx fait le proxy. Démarrez ou redémarrez votre VPS pour vérifier le démarrage automatique."
