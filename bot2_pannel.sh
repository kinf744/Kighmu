#!/bin/bash
set -e

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
                echo "❌ Go n'est pas installé. Installez Go avant de continuer."
                read -p "Appuyez sur Entrée pour continuer..."
                continue
            fi

            cd "$SCRIPT_DIR" || { echo "❌ Répertoire $SCRIPT_DIR introuvable"; read -p "Appuyez sur Entrée pour continuer..."; continue; }

            if [ ! -f "bot2.go" ]; then
                echo "❌ Fichier bot2.go introuvable dans $SCRIPT_DIR"
                read -p "Appuyez sur Entrée pour continuer..."
                continue
            fi

            if [ ! -f "go.mod" ]; then
                echo "⏳ Initialisation du module Go..."
                go mod init telegram-bot
            fi

            echo "⏳ Installation de la librairie Telegram..."
            go get github.com/go-telegram-bot-api/telegram-bot-api

            echo "⏳ Compilation du bot..."
            go build -o bot2 bot2.go

            echo "✅ Librairie installée et bot compilé avec succès"
            read -p "Appuyez sur Entrée pour continuer..."
            ;;
        2)
            cd "$SCRIPT_DIR" || { echo "❌ Répertoire $SCRIPT_DIR introuvable"; read -p "Appuyez sur Entrée pour continuer..."; continue; }

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
