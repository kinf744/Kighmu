#!/bin/bash
# system_dns.sh
# Script d'installation et configuration d'un serveur DNS (bind9) sur VPS

set -e

echo "Mise à jour des paquets..."
apt-get update -y

echo "Installation de bind9..."
apt-get install -y bind9 bind9utils bind9-doc dnsutils

echo "Activation du service bind9 au démarrage..."
systemctl enable bind9

echo "Démarrage du service bind9..."
systemctl restart bind9

echo "Vérification du statut du service bind9..."
if systemctl is-active --quiet bind9; then
    echo "Serveur DNS bind9 est installé et en cours d'exécution sur le port 53."
else
    echo "Échec du démarrage de bind9."
    exit 1
fi

echo "Configuration par défaut : bind9 écoute normalement sur le port 53 UDP/TCP."
echo "Pour des configurations avancées, modifiez les fichiers dans /etc/bind/"
