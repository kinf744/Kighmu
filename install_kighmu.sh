#!/bin/bash
# ==============================================
# Kighmu VPS Manager
# Copyright (c) 2025 Kinf744
# Licensed under the MIT License
# See LICENSE file for details
# ==============================================

clear
echo "=============================================="
echo "      Bienvenue dans Kighmu VPS Manager"
echo "=============================================="

# Appeler le menu principal depuis le même dossier que Kighmu.sh
SCRIPT_DIR=$(dirname "$0")

if [ -f "$SCRIPT_DIR/menu_principal.sh" ]; then
    bash "$SCRIPT_DIR/menu_principal.sh"
else
    echo "❌ Erreur : fichier menu_principal.sh introuvable"
    exit 1
fi
