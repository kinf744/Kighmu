#!/bin/bash

# Vérifie si pm2 est installé, sinon l'installe
if ! command -v pm2 &> /dev/null
then
    echo "Installation de pm2 ..."
    npm install -g pm2
fi

# Remplacez ce chemin par celui de votre projet qui contient server.js
PROJECT_DIR="/chemin/vers/votre/projet"

cd "$PROJECT_DIR"

# Installer les dépendances Node.js depuis package.json
npm install

# Démarrer le serveur avec pm2 ou le redémarrer s'il est déjà lancé
pm2 start server.js --name websocket-server --watch

# Sauvegarder la configuration pm2 pour la restauration au démarrage
pm2 save

# Configurer pm2 pour démarrer automatiquement au boot système
pm2 startup systemd -u $(whoami) --hp $HOME

echo "Serveur Node.js démarré avec pm2 et configuré pour démarrage automatique."
  
