#!/bin/bash
# ssl.sh
# Script pour installer et configurer SSL avec Certbot et configurer Nginx sur le port 445

set -e

# Remplace cette variable par ton nom de domaine réel
DOMAIN="example.com"
EMAIL="admin@example.com"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

echo "Mise à jour des paquets..."
apt-get update -y

echo "Installation de Certbot et du plugin Nginx..."
apt-get install -y certbot python3-certbot-nginx

echo "Obtention du certificat SSL pour $DOMAIN..."
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL"

echo "Configuration du renouvellement automatique..."
systemctl enable certbot.timer
systemctl start certbot.timer

# Création d'un fichier de configuration Nginx pour le port 445
echo "Création de la configuration Nginx pour le port 445..."

cat > "$NGINX_CONF" <<EOF
server {
    listen 445 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://localhost:22;  # Change si nécessaire vers ton service
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

echo "Test de la configuration Nginx..."
nginx -t

echo "Recharge de Nginx pour appliquer les changements..."
systemctl reload nginx

echo "Configuration SSL terminée et Nginx écoute sur le port 445."

echo "Vérification du statut du certificat..."
certbot certificates | grep "$DOMAIN"
