#!/bin/bash

# =========================================
# Install Kighmu Manager
# =========================================

# Mettre à jour et upgrader le système
echo "Mise à jour du système en cours..."
apt-get update -y && apt-get upgrade -y

# Créer un dossier pour Kighmu si nécessaire
INSTALL_DIR="/opt/Kighmu"
if [ ! -d "$INSTALL_DIR" ]; then
    mkdir -p "$INSTALL_DIR"
fi

# Télécharger le script principal Kighmu
echo "Téléchargement de Kighmu Manager..."
wget -O "$INSTALL_DIR/Kighmu" https://raw.githubusercontent.com/kinf744/Kighmu/main/Kighmu.sh

# Rendre le script exécutable
chmod 777 "$INSTALL_DIR/Kighmu"

# Lancer Kighmu
echo "Lancement de Kighmu Manager..."
cd "$INSTALL_DIR"
./Kighmu
