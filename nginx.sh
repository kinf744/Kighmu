#!/bin/bash
# nginx.sh
# Script d’installation et configuration SSL avancée pour Nginx

set -e

DOMAIN="example.com"          # Remplace par ton domaine réel
EMAIL="admin@example.com"     # Ton email pour Certbot

echo "Mise à jour des paquets et installation de Certbot..."
apt-get update -y
apt-get install -y certbot python3-certbot-nginx

echo "Obtention du certificat SSL pour $DOMAIN ..."
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL"

# Création des snippets pour SSL
echo "Création des snippets de configuration SSL Nginx..."

cat > /etc/nginx/snippets/self-signed.conf <<EOF
ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
EOF

cat > /etc/nginx/snippets/ssl-params.conf <<EOF
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_dhparam /etc/nginx/dhparam.pem;
ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384: ...
';  # Utilise ta liste de ciphers sécurisés ici
ssl_ecdh_curve secp384r1;
ssl_session_timeout 10m;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
add_header X-XSS-Protection "1; mode=block";
EOF

echo "Génération du DH param (peut prendre du temps)..."
if [ ! -f /etc/nginx/dhparam.pem ]; then
    openssl dhparam -out /etc/nginx/dhparam.pem 4096
fi

# Création du fichier de config site Nginx
echo "Création de la configuration Nginx pour $DOMAIN..."

cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    include snippets/self-signed.conf;
    include snippets/ssl-params.conf;

    root /var/www/$DOMAIN/html;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }
}

server {
    listen 445 ssl http2;
    server_name $DOMAIN;

    include snippets/self-signed.conf;
    include snippets/ssl-params.conf;

    location / {
        proxy_pass http://localhost:22;  # Adapter selon service ciblé
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

# Activer le site et tester la config
ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
nginx -t
systemctl reload nginx

echo "Configuration Nginx terminée. SSL actif sur les ports 443 et 445 avec redirection HTTP vers HTTPS."
