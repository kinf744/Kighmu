#!/bin/bash

# Demander le domaine à configurer
read -p "Merci de saisir le domaine à configurer (exemple: monsite.exemple.com) : " DOMAIN

if [ -z "$DOMAIN" ]; then
  echo "Erreur : le domaine ne peut pas être vide."
  exit 1
fi

# Définir le chemin du dossier projet
PROJECT_DIR="/home/$(whoami)/monprojet"

# Créer le dossier projet s'il n'existe pas
if [ ! -d "$PROJECT_DIR" ]; then
  echo "Création du dossier projet $PROJECT_DIR"
  mkdir -p "$PROJECT_DIR"
fi

# Aller dans le dossier projet
cd "$PROJECT_DIR" || exit 1

# Créer un exemple de fichier server.js (adapter selon votre code)
cat > server.js << 'EOF'
const WebSocket = require('ws');

const wss = new WebSocket.Server({ port: 81 });

wss.on('connection', (ws) => {
  console.log('Un client WebSocket est connecté');

  ws.on('message', (message) => {
    console.log('Message reçu: %s', message);
    ws.send(`Echo: ${message}`);
  });

  ws.on('close', () => {
    console.log('Client déconnecté');
  });

  ws.send('Bienvenue sur le serveur WebSocket!');
});

console.log('Serveur WebSocket démarré et écoute sur le port 81');
EOF

# Créer un package.json simple avec dépendance ws
cat > package.json << 'EOF'
{
  "name": "websocket-server",
  "version": "1.0.0",
  "description": "Serveur WebSocket Node.js",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "ws": "^8.12.0"
  }
}
EOF

echo "Installation des dépendances Node.js..."
npm install

echo "Installation de pm2 si nécessaire..."
if ! command -v pm2 &> /dev/null; then
  npm install -g pm2
fi

echo "Démarrage du serveur avec pm2..."
pm2 start server.js --name websocket-server --watch
pm2 save
pm2 startup systemd -u $(whoami) --hp $HOME

echo "Configuration nginx pour le domaine $DOMAIN..."

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

echo "Installation, configuration et démarrage terminés."
echo "Votre serveur WebSocket tourne avec pm2 et nginx fait le proxy au port 81."
