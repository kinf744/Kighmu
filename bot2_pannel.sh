#!/bin/bash

SCRIPT_DIR="$HOME/Kighmu"
BOT_BIN="$SCRIPT_DIR/bot2"
SERVICE_FILE="/etc/systemd/system/bot2.service"
BOTS_CLIENT="/etc/kighmu/bots.json"

stop_and_uninstall_bot() {
    echo "🛑 Arrêt du bot (si actif)..."
    sudo systemctl stop bot2 2>/dev/null || true
    sudo systemctl disable bot2 2>/dev/null || true
    sudo rm -f "$SERVICE_FILE"

    echo "🗑️ Suppression des fichiers..."
    rm -f "$BOT_BIN" "$SCRIPT_DIR/go.mod" "$SCRIPT_DIR/go.sum"

    echo "✅ Bot arrêté et désinstallé"
}

sudo chmod 600 /etc/kighmu/bots.json
sudo chown root:root /etc/kighmu/bots.json

cat > "$BOTS_CLIENT" << 'EOF'
{
  "bots": [
    {
      "NomBot": "AdminBot",
      "Token": "TOKEN_ADMIN",
      "ID": 123456,
      "Role": "admin",
      "Utilisateurs": []
    },
    {
      "NomBot": "ClientBot1",
      "Token": "TOKEN_CLIENT1",
      "ID": 654321,
      "Role": "client",
      "Utilisateurs": ["user1", "user2"]
    },
    {
      "NomBot": "ClientBot2",
      "Token": "TOKEN_CLIENT2",
      "ID": 987654,
      "Role": "client",
      "Utilisateurs": ["user3"]
    }
  ]
}
EOF

create_systemd_service() {
    read -p "🔑 Entrez votre BOT_TOKEN : " BOT_TOKEN
    read -p "🆔 Entrez votre ADMIN_ID : " ADMIN_ID

    # Le bot sera lancé en root
    sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=Telegram VPS Control Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$SCRIPT_DIR
ExecStart=$BOT_BIN
Restart=always
RestartSec=5
Environment=BOT_TOKEN=$BOT_TOKEN
Environment=ADMIN_ID=$ADMIN_ID

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable bot2
    sudo systemctl start bot2
    echo "✅ Service systemd créé et bot démarré"
}

while true; do
    clear
    echo "======================================"
    echo "      🤖 PANNEAU DE CONTRÔLE BOT"
    echo "======================================"
    echo "1️⃣  Installer / Compiler le bot"
    echo "2️⃣  Lancer le bot (systemd)"
    echo "3️⃣  Quitter"
    echo "4️⃣  Arrêter / Désinstaller le bot"
    echo "======================================"
    read -p "👉 Choisissez une option [1-4] : " option

    case "$option" in

        1)
            echo "⏳ Vérification de Go..."
            if ! command -v go >/dev/null 2>&1; then
                echo "❌ Go n'est pas installé"
                read -p "Entrée pour continuer..."
                continue
            fi

            cd "$SCRIPT_DIR" || continue

            [ ! -f "go.mod" ] && go mod init telegram-bot
            go mod tidy

            if go build -o bot2 bot2.go; then
                echo "✅ Bot compilé avec succès"
            else
                echo "❌ Erreur de compilation"
            fi

            # Permissions pour root
            sudo chown root:root "$BOT_BIN"
            sudo chmod +x "$BOT_BIN"

            read -p "Entrée pour continuer..."
            ;;

        2)
            if [ ! -f "$BOT_BIN" ]; then
                echo "❌ Bot non compilé. Veuillez choisir l'option 1 d'abord."
                read -p "Entrée pour continuer..."
                continue
            fi
            create_systemd_service
            read -p "Entrée pour continuer..."
            ;;

        4)
            stop_and_uninstall_bot
            read -p "Entrée pour continuer..."
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
