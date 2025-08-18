#!/bin/bash
# ssl.sh
# Script pour installer et configurer SSL avec Certbot sur un VPS

set -e

# Remplace cette variable par ton nom de domaine réel
DOMAIN="example.com"
EMAIL="admin@example.com"

echo "Mise à jour des paquets..."
apt-get update -y

echo "Installation de Certbot et du plugin Nginx..."
apt-get install -y certbot python3-certbot-nginx

echo "Obtention du certificat SSL pour $DOMAIN..."
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL"

echo "Configuration du renouvellement automatique..."
systemctl enable certbot.timer
systemctl start certbot.timer

echo "Vérification du statut du certificat..."
certbot certificates | grep "$DOMAIN"

echo "SSL installé et configuré pour la gestion automatique."
