#!/bin/bash
# ==============================================
# Kighmu VPS Manager Installer
# Copyright (c) 2025 Kinf744
# Licence MIT (version française)
# Voir le fichier LICENSE pour plus de détails
# ==============================================

echo "Mise à jour du serveur..."
apt-get update -y && apt-get upgrade -y

echo "Installation des dépendances nécessaires..."
apt-get install -y wget curl net-tools

echo "Téléchargement et configuration du script Kighmu..."
wget -O /opt/Kighmu.sh https://raw.githubusercontent.com/kinf744/Kighmu/main/Kighmu.sh
chmod +x /opt/Kighmu.sh

echo "Installation terminée !"
echo "Vous pouvez lancer le panneau de contrôle avec la commande : /opt/Kighmu.sh"
