#!/bin/bash
# ==============================================
# Kighmu VPS Manager
# Copyright (c) 2025 Kinf744
# Licence MIT (version française)
# ==============================================

echo "=============================================="
echo " 🚀 Installation de Kighmu VPS Manager..."
echo "=============================================="

# Crée le dossier d'installation
INSTALL_DIR="$HOME/Kighmu"
mkdir -p "$INSTALL_DIR"

# Liste des fichiers à télécharger depuis GitHub
FILES=(
    "kighmu-manager.sh"
    "kighmu.sh"
    "menu1.sh"
    "menu2.sh"
    "menu3.sh"
    "menu4.sh"
    "menu5.sh"
    "menu6.sh"
    "menu7.sh"
    "slowdns.sh"
    "socks_python.sh"
    "udp_custom.sh"
)

# Téléchargement de chaque fichier
for file in "${FILES[@]}"; do
    wget -q -O "$INSTALL_DIR/$file" "https://raw.githubusercontent.com/kinf744/Kighmu/main/$file"
    chmod +x "$INSTALL_DIR/$file"
done

# Crée un alias dans ~/.bashrc pour lancer Kighmu facilement
if ! grep -q "alias kighmu=" "$HOME/.bashrc"; then
    echo "alias kighmu='$INSTALL_DIR/kighmu.sh'" >> "$HOME/.bashrc"
fi

# Recharge le bashrc pour prendre l'alias en compte
source "$HOME/.bashrc"

echo "=============================================="
echo " ✅ Installation terminée !"
echo " Pour lancer Kighmu, utilisez la commande : kighmu"
echo "=============================================="
