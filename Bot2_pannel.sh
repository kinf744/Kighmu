#!/bin/bash

SCRIPT_DIR="$HOME/Kighmu"

while true; do
    clear
    echo "======================================"
    echo "      🤖 Panneau de contrôle Bot"
    echo "======================================"
    echo "1️⃣  Installer la librairie Telegram Go et compiler le bot"
    echo "2️⃣  Lancer le bot Telegram"
    echo "3️⃣  Quitter"
    echo "======================================"
    read -p "👉 Choisissez une option [1-3] : " option

    case "$option" in
        1)
            echo "⏳ Installation de la librairie et compilation..."
            if ! command -v go &> /dev/null; then
                echo "❌ Go n'est pas installé"
                read -p "Appuyez sur Entrée pour continuer..."
                continue
            fi
            cd "$SCRIPT_DIR"
            if [ ! -f "go.mod" ]; then
                go mod init telegram-bot
            fi
            go get github.com/go-telegram-bot-api/telegram-bot-api
            go build -o bot2 bot2.go
            echo "✅ Librairie installée et bot compilé"
            read -p "Appuyez sur Entrée pour continuer..."
            ;;
        2)
            cd "$SCRIPT_DIR"
            if [ ! -f "bot2" ]; then
                echo "❌ Bot non compilé. Choisissez d'abord l'option 1."
                read -p "Appuyez sur Entrée pour continuer..."
                continue
            fi
            echo "🚀 Lancement du bot..."
            ./bot2
            ;;
        3)
            echo "👋 Au revoir"
            exit 0
            ;;
        *)
            echo "❌ Option invalide"
            read -p "Appuyez sur Entrée pour continuer..."
            ;;
    esac
done
