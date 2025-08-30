#!/bin/bash
set -e

echo "[*] Mise à jour des paquets..."
sudo apt update -y

echo "[*] Installation de Nginx..."
if ! sudo apt install -y nginx; then
    echo "[Erreur] Échec de l'installation de Nginx. Veuillez vérifier votre connexion réseau et les sources."
    exit 1
fi

echo "[*] Copie de la configuration nginx.conf..."
if ! sudo cp ./nginx.conf /etc/nginx/nginx.conf; then
    echo "[Erreur] Échec de la copie de nginx.conf. Vérifiez les permissions et l'existence du fichier."
    exit 1
fi

echo "[*] Test de la configuration Nginx..."
if ! sudo nginx -t; then
    echo "[Erreur] La configuration Nginx est invalide. Veuillez corriger les erreurs avant de continuer."
    exit 1
fi

echo "[*] Recharge du service Nginx..."
if ! sudo systemctl reload nginx; then
    echo "[Erreur] Impossible de recharger Nginx. Vérifiez les logs pour plus d'informations."
    exit 1
fi

echo "[*] Installation et configuration Nginx terminées avec succès."

