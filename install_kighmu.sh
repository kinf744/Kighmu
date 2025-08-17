#!/bin/bash
# install_kighmu.sh
# Installation automatique de Kighmu Manager - style DarkSSH

clear
echo "+--------------------------------------------+"
echo "|                                            |"
echo "|         K I G H M U   M A N A G E R        |"
echo "|                                            |"
echo "+--------------------------------------------+"
echo ""
echo "🛠  Mise à jour du système..."
apt-get update -y && apt-get upgrade -y

echo "📦 Installation des dépendances nécessaires..."
apt-get install -y wget curl git python3 sudo

echo "⬇️  Téléchargement du panneau Kighmu Manager..."
cd /opt
if [ -d "/opt/Kighmu" ]; then
    echo "⚠️  Le dossier /opt/Kighmu existe déjà. Suppression..."
    rm -rf /opt/Kighmu
fi
git clone https://github.com/kinf744/Kighmu.git
cd Kighmu

echo "⚙️  Rendre tous les scripts exécutables..."
chmod +x *.sh

echo "🔗 Création du raccourci global 'kighmu'..."
ln -sf /opt/Kighmu/kighmu.sh /usr/local/bin/kighmu

echo ""
echo "+--------------------------------------------+"
echo "|       Installation terminée avec succès !   |"
echo "|                                            |"
echo "|  Lancer Kighmu Manager avec la commande :  |"
echo "|               kighmu                        |"
echo "+--------------------------------------------+"
