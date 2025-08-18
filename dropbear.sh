#!/bin/bash
# dropbear.sh
# Script pour installer et configurer Dropbear SSH sur VPS

set -e

echo "Mise à jour des paquets..."
apt-get update -y

echo "Installation de Dropbear..."
apt-get install -y dropbear

echo "Activation du service Dropbear au démarrage..."
systemctl enable dropbear

echo "Démarrage du service Dropbear..."
systemctl restart dropbear

echo "Vérification du statut du service Dropbear..."
if systemctl is-active --quiet dropbear; then
    echo "Dropbear est installé et en cours d'exécution."
else
    echo "Échec du démarrage de Dropbear."
    exit 1
fi
