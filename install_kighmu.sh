#!/bin/bash
# ==============================================
# Kighmu VPS Manager
# Copyright (c) 2025 Kinf744
# Licensed under the MIT License
# ==============================================

clear
echo "=============================================="
echo " 🚀 Installation de Kighmu VPS Manager..."
echo "=============================================="

# Mettre à jour et upgrader le système
apt-get update -y && apt-get upgrade -y

# Installer wget et bash si nécessaire
apt-get install -y wget bash

# Répertoire d'installation
INSTALL_DIR="$HOME/Kighmu"
mkdir -p "$INSTALL_DIR"

# Télécharger tous les scripts depuis GitHub
echo "➡ Téléchargement des fichiers depuis GitHub..."
wget -q -P "$INSTALL_DIR" https://raw.githubusercontent.com/kinf744/Kighmu/main/Kighmu.sh
wget -q -P "$INSTALL_DIR" https://raw.githubusercontent.com/kinf744/Kighmu/main/menu_principal.sh
wget -q -P "$INSTALL_DIR" https://raw.githubusercontent.com/kinf744/Kighmu/main/menu1.sh
wget -q -P "$INSTALL_DIR" https://raw.githubusercontent.com/kinf744/Kighmu/main/menu2.sh
wget -q -P "$INSTALL_DIR" https://raw.githubusercontent.com/kinf744/Kighmu/main/menu3.sh
wget -q -P "$INSTALL_DIR" https://raw.githubusercontent.com/kinf744/Kighmu/main/menu4.sh
wget -q -P "$INSTALL_DIR" https://raw.githubusercontent.com/kinf744/Kighmu/main/menu5.sh
wget -q -P "$INSTALL_DIR" https://raw.githubusercontent.com/kinf744/Kighmu/main/menu6.sh
wget -q -P "$INSTALL_DIR" https://raw.githubusercontent.com/kinf744/Kighmu/main/menu7.sh

# Donner les droits d'exécution
chmod +x "$INSTALL_DIR"/*.sh

# Créer un alias pour lancer Kighmu facilement
echo "alias kighmu='bash $INSTALL_DIR/Kighmu.sh'" >> ~/.bashrc
source ~/.bashrc

clear
echo "=============================================="
echo " ✅ Installation terminée !"
echo " Pour lancer Kighmu, utilisez la commande : kighmu"
echo "=============================================="
