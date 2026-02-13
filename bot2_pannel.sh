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

# Fonction pour ajouter un nouveau client bot
ajouter_client_bot() {
    echo "➤ Ajouter un client bot"
    read -p "Nom du bot : " NOM_BOT
    read -p "Token du bot : " TOKEN_BOT
    read -p "ID du bot : " ID_BOT
    read -p "Rôle (client/admin) : " ROLE_BOT
    read -p "Utilisateurs initiaux (séparés par des virgules, vide si aucun) : " USERS_INPUT
    IFS=',' read -ra USERS <<< "$USERS_INPUT"

    # Lire le JSON actuel
    TMP_JSON=$(mktemp)
    jq --arg nom "$NOM_BOT" \
       --arg token "$TOKEN_BOT" \
       --argjson id "$ID_BOT" \
       --arg role "$ROLE_BOT" \
       --argjson users "$(printf '%s\n' "${USERS[@]}" | jq -R . | jq -s .)" \
       '.bots += [{"NomBot": $nom, "Token": $token, "ID": $id, "Role": $role, "Utilisateurs": $users}]' \
       "$BOTS_CLIENT" > "$TMP_JSON" && mv "$TMP_JSON" "$BOTS_CLIENT"

    sudo chmod 600 "$BOTS_CLIENT"
    sudo chown root:root "$BOTS_CLIENT"
    echo "✅ Client bot $NOM_BOT ajouté"
}

# Fonction pour lister les utilisateurs et supprimer un utilisateur d'un client bot
gerer_utilisateurs_client() {
    echo "➤ Gestion des utilisateurs client bot"
    # Afficher tous les clients
    jq -r '.bots[] | "\(.NomBot) (ID: \(.ID))"' "$BOTS_CLIENT"
    read -p "Nom du client bot à gérer : " NOM_CLIENT

    # Vérifier si le client existe
    EXISTS=$(jq --arg nom "$NOM_CLIENT" '.bots[] | select(.NomBot == $nom)' "$BOTS_CLIENT")
    if [ -z "$EXISTS" ]; then
        echo "❌ Client bot non trouvé"
        return
    fi

    # Lister les utilisateurs du client
    USERS=$(jq -r --arg nom "$NOM_CLIENT" '.bots[] | select(.NomBot == $nom) | .Utilisateurs[]' "$BOTS_CLIENT")
    if [ -z "$USERS" ]; then
        echo "Aucun utilisateur pour ce client bot"
        return
    fi

    echo "Utilisateurs :"
    i=1
    declare -a USER_ARR
    for u in $USERS; do
        echo "$i) $u"
        USER_ARR+=("$u")
        ((i++))
    done

    read -p "Numéro de l'utilisateur à supprimer (ou vide pour annuler) : " NUM
    if [ -z "$NUM" ]; then
        echo "❌ Annulé"
        return
    fi

    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || [ "$NUM" -lt 1 ] || [ "$NUM" -gt "${#USER_ARR[@]}" ]; then
        echo "❌ Numéro invalide"
        return
    fi

    USER_DELETE="${USER_ARR[$((NUM-1))]}"

    # Supprimer l'utilisateur du JSON
    TMP_JSON=$(mktemp)
    jq --arg nom "$NOM_CLIENT" --arg userdel "$USER_DELETE" \
       '(.bots[] | select(.NomBot == $nom) | .Utilisateurs) |= map(select(. != $userdel))' \
       "$BOTS_CLIENT" > "$TMP_JSON" && mv "$TMP_JSON" "$BOTS_CLIENT"

    sudo chmod 600 "$BOTS_CLIENT"
    sudo chown root:root "$BOTS_CLIENT"
    echo "✅ Utilisateur $USER_DELETE supprimé du client bot $NOM_CLIENT"
}

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
    echo "2️⃣  Lancer le bot admin(systemd)"
    echo "3️⃣  Quitter"
    echo "4️⃣  Arrêter / Désinstaller le bot"
    echo "5️⃣  Ajouter un client bot"
    echo "6️⃣  Gérer les utilisateurs d'un client bot"
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

        5)
          ajouter_client_bot
          read -p "Entrée pour continuer..."
            ;;

        6)
          gerer_utilisateurs_client
          read -p "Entrée pour continuer..."
            ;;

        *)
            echo "❌ Option invalide"
            read -p "Entrée pour continuer..."
            ;;
    esac
done
