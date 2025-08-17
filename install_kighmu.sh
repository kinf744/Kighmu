#!/bin/bash
# ==============================================
# Kighmu VPS Manager
# Copyright (c) 2025 Kinf744
# Licensed under the MIT License
# See LICENSE file for details
# ==============================================

echo "=============================================="
echo " 🚀 Installation de Kighmu VPS Manager..."
echo "=============================================="

# Mise à jour du système
apt-get update -y && apt-get upgrade -y

# Création du dossier d’installation
mkdir -p /opt

# Téléchargement du script principal Kighmu.sh
echo "➡ Téléchargement des fichiers depuis GitHub..."
wget -q -O /opt/Kighmu.sh https://raw.githubusercontent.com/kinf744/Kighmu/main/Kighmu.sh

# Vérifier si le fichier a bien été téléchargé
if [ ! -s /opt/Kighmu.sh ]; then
    echo "❌ Erreur : Impossible de télécharger Kighmu.sh"
    exit 1
fi

chmod +x /opt/Kighmu.sh

# Création du lanceur global
echo "➡ Création du lanceur global..."
cat > /usr/local/bin/kighmu <<EOL
#!/bin/bash
/opt/Kighmu.sh
EOL

chmod +x /usr/local/bin/kighmu

echo "=============================================="
echo " ✅ Installation terminée !"
echo " Lancez le panneau de contrôle avec : kighmu"
echo "=============================================="
