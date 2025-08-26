#!/bin/bash

# Ce script menu2.sh sert uniquement à lancer menu2_et_expire.sh avec les bons paramètres
# Usage dans un menu principal : option 2 de menu lance "Créer test utilisateur"

# Vérifie que le script principal est présent
SCRIPT_PATH="/root/Kighmu/menu2_et_expire.sh"

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Erreur : script $SCRIPT_PATH introuvable."
    exit 1
fi

# Lance la création utilisateur test
$SCRIPT_PATH create
