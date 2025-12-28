#!/bin/bash

SCRIPT_DIR="$HOME/Kighmu"
BOT_BIN="$SCRIPT_DIR/bot2"

while true; do
    clear
    echo "======================================"
    echo "      🤖 PANNEAU DE CONTRÔLE BOT"
    echo "======================================"
    echo "1️⃣  Installer la librairie Telegram Go et compiler le bot"
    echo "2️⃣  Lancer le bot Telegram"
    echo "3️⃣  Quitter"
    echo "======================================"
    read -p "👉 Choisissez une option [1-3] : " option

    case "$option" in

        1)
            echo "⏳ Vérification de Go..."
            if ! command -v go >/dev/null 2>&1; then
                echo "❌ Go n'est pas installé"
                read -p "Entrée pour continuer..."
                continue
            fi

            if [ ! -d "$SCRIPT_DIR" ]; then
                echo "❌ Répertoire $SCRIPT_DIR introuvable"
                read -p "Entrée pour continuer..."
                continue
            fi

            cd "$SCRIPT_DIR" || continue

            if [ ! -f "bot2.go" ]; then
                echo "❌ bot2.go introuvable dans $SCRIPT_DIR"
                read -p "Entrée pour continuer..."
                continue
            fi

            if [ ! -f "go.mod" ]; then
                echo "⏳ Initialisation du module Go..."
                go mod init telegram-bot || true
            fi

            echo "⏳ Téléchargement des dépendances..."
            go mod tidy

            echo "⏳ Compilation du bot..."
            if go build -o bot2 bot2.go; then
                echo "✅ Bot compilé avec succès"
            else
                echo "❌ Erreur lors de la compilation"
            fi

            read -p "Entrée pour continuer..."
            ;;

        2)
            cd "$SCRIPT_DIR" || continue

            if [ ! -f "$BOT_BIN" ]; then
                echo "❌ Bot non compilé"
                echo "➡ Utilise l’option 1 d’abord"
                read -p "Entrée pour continuer..."
                continue
            fi

            if [ -z "$BOT_TOKEN" ] || [ -z "$ADMIN_ID" ]; then
                echo "❌ Variables manquantes"
                echo "➡ BOT_TOKEN ou ADMIN_ID non définis"
                read -p "Entrée pour continuer..."
                continue
            fi

            echo "🚀 Lancement du bot Telegram..."
            exec "$BOT_BIN"
            ;;

        3)
            echo "👋 Au revoir"
            exit 0
            ;;

        *)
            echo "❌ Option invalide"
            read -p "Entrée pour continuer..."
            ;;
    esac
done
