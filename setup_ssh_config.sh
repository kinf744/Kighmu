#!/bin/bash

CONFIG_FILE="./config/sshd_config"  # Chemin vers ta config SSH dans le dépôt
TARGET_FILE="/etc/ssh/sshd_config"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Erreur : fichier $CONFIG_FILE introuvable."
    exit 1
fi

echo "Sauvegarde de l'ancien fichier sshd_config..."
sudo cp "$TARGET_FILE" "${TARGET_FILE}.backup.$(date +%F_%T)"

echo "Déploiement de la nouvelle configuration SSH..."
sudo cp "$CONFIG_FILE" "$TARGET_FILE"

echo "Réglage des permissions..."
sudo chown root:root "$TARGET_FILE"
sudo chmod 644 "$TARGET_FILE"

echo "Redémarrage du service SSH pour appliquer la nouvelle configuration..."
sudo systemctl restart ssh

echo "Configuration SSH appliquée avec succès."
