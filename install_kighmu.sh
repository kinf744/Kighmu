#!/bin/bash
# ==============================================
# Kighmu VPS Manager
# Copyright (c) 2025 Kinf744
# Licensed under the MIT License
# See LICENSE file for details
# ==============================================

set -e

echo "=============================================="
echo " 🚀 Installation de Kighmu VPS Manager..."
echo "=============================================="

# Mettre à jour le serveur
apt-get update -y && apt-get upgrade -y

# Créer le dossier d'installation
INSTALL_DIR="/opt"
mkdir -p $INSTALL_DIR

# Télécharger le script principal et menus depuis GitHub
echo "➡ Téléchargement des fichiers..."
wget -q -O $INSTALL_DIR/Kighmu.sh https://raw.githubusercontent.com/kinf744/Kighmu/main/Kighmu.sh
wget -q -O $INSTALL_DIR/menu1.sh https://raw.githubusercontent.com/kinf744/Kighmu/main/menu1.sh
wget -q -O $INSTALL_DIR/menu2.sh https://raw.githubusercontent.com/kinf744/Kighmu/main/menu2.sh
wget -q -O $INSTALL_DIR/menu3.sh https://raw.githubusercontent.com/kinf744/Kighmu/main/menu3.sh
wget -q -O $INSTALL_DIR/menu4.sh https://raw.githubusercontent.com/kinf744/Kighmu/main/menu4.sh
wget -q -O $INSTALL_DIR/menu5.sh https://raw.githubusercontent.com/kinf744/Kighmu/main/menu5.sh
wget -q -O $INSTALL_DIR/menu6.sh https://raw.githubusercontent.com/kinf744/Kighmu/main/menu6.sh
wget -q -O $INSTALL_DIR/menu7.sh https://raw.githubusercontent.com/kinf744/Kighmu/main/menu7.sh

# Donner les permissions d'exécution
chmod +x $INSTALL_DIR/Kighmu.sh
chmod +x $INSTALL_DIR/menu*.sh

# Ajouter un alias pour exécuter plus facilement
if ! grep -q "alias kighmu=" ~/.bashrc; then
    echo "alias kighmu='/opt/Kighmu.sh'" >> ~/.bashrc
    source ~/.bashrc
fi

echo "=============================================="
echo " ✅ Installation terminée !"
echo " Lancez le panneau de contrôle avec :"
echo "   /opt/Kighmu.sh"
echo " ou simplement :"
echo "   kighmu"
echo "=============================================="
