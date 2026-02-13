#!/bin/bash

SCRIPT_DIR="$HOME/Kighmu"
BOT_BIN="$SCRIPT_DIR/bot2"
SERVICE_FILE="/etc/systemd/system/bot2.service"
BOTS_CLIENT="/etc/kighmu/bots.json"

mkdir -p /etc/kighmu
[ ! -f "$BOTS_CLIENT" ] && cat > "$BOTS_CLIENT" << 'EOF'
{
  "bots": [
    {
      "NomBot": "AdminBot",
      "Token": "TOKEN_ADMIN",
      "ID": 123456,
      "Role": "admin",
      "Utilisateurs": []
    }
  ]
}
EOF

sudo chmod 600 "$BOTS_CLIENT"
sudo chown root:root "$BOTS_CLIENT"

stop_and_uninstall_bot() {
    echo "🛑 Arrêt du bot (si actif)..."
    sudo systemctl stop bot2 2>/dev/null || true
    sudo systemctl disable bot2 2>/dev/null || true
    sudo rm -f "$SERVICE_FILE"

    echo "🗑️ Suppression des fichiers..."
    rm -f "$BOT_BIN" "$SCRIPT_DIR/go.mod" "$SCRIPT_DIR/go.sum"

    echo "✅ Bot arrêté et désinstallé"
}

# Ajouter un client bot
ajouter_client_bot() {
    echo "➤ Ajouter un client bot"
    read -p "Nom du bot : " NOM_BOT
    read -p "Token du bot : " TOKEN_BOT
    read -p "ID du bot : " ID_BOT

    while true; do
        read -p "Rôle (client/admin) : " ROLE_BOT
        [[ "$ROLE_BOT" == "admin" || "$ROLE_BOT" == "client" ]] && break
        echo "❌ Rôle invalide, choisissez 'admin' ou 'client'"
    done

    read -p "Utilisateurs initiaux (séparés par des virgules, vide si aucun) : " USERS_INPUT
    read -p "Durée d'expiration par défaut en jours pour chaque utilisateur : " DAYS

    IFS=',' read -ra USERS <<< "$USERS_INPUT"

    # Création de tableau d'utilisateurs avec expiration
    USERS_JSON="[]"
    for u in "${USERS[@]}"; do
        EXP_DATE=$(date -d "+$DAYS days" +%Y-%m-%d)
        USERS_JSON=$(echo "$USERS_JSON" | jq --arg name "$u" --arg expire "$EXP_DATE" '. += [{"nom": $name, "expire": $expire}]')
    done

    TMP_JSON=$(mktemp)
    jq --arg nom "$NOM_BOT" \
       --arg token "$TOKEN_BOT" \
       --argjson id "$ID_BOT" \
       --arg role "$ROLE_BOT" \
       --argjson users "$USERS_JSON" \
       '.bots += [{"NomBot": $nom, "Token": $token, "ID": $id, "Role": $role, "Utilisateurs": $users}]' \
       "$BOTS_CLIENT" > "$TMP_JSON" && mv "$TMP_JSON" "$BOTS_CLIENT"

    sudo chmod 600 "$BOTS_CLIENT"
    sudo chown root:root "$BOTS_CLIENT"
    echo "✅ Client bot $NOM_BOT ajouté"
}

# Gérer utilisateurs avec expiration
gerer_utilisateurs_client() {
    echo "➤ Gestion des utilisateurs client bot"
    jq -r '.bots[] | "\(.NomBot) (ID: \(.ID))"' "$BOTS_CLIENT"
    read -p "Nom du client bot à gérer : " NOM_CLIENT

    USERS=$(jq -r --arg nom "$NOM_CLIENT" '.bots[] | select(.NomBot == $nom) | .Utilisateurs[] | "\(.nom) | expire: \(.expire)"' "$BOTS_CLIENT")
    if [ -z "$USERS" ]; then echo "Aucun utilisateur pour ce client bot"; return; fi

    echo "Utilisateurs :"
    i=1
    declare -a USER_ARR
    declare -a EXPIRE_ARR
    while IFS='|' read -r NAME EXPIRE; do
        NAME=$(echo "$NAME" | xargs)
        EXPIRE=$(echo "$EXPIRE" | xargs | cut -d' ' -f2)
        echo "$i) $NAME (Expire: $EXPIRE)"
        USER_ARR+=("$NAME")
        EXPIRE_ARR+=("$EXPIRE")
        ((i++))
    done <<< "$USERS"

    echo "Options :"
    echo "1) Supprimer un utilisateur"
    echo "2) Ajouter un utilisateur"
    read -p "Choisissez une option : " CHOICE

    case "$CHOICE" in
        1)
            read -p "Numéro de l'utilisateur à supprimer : " NUM
            [[ ! "$NUM" =~ ^[0-9]+$ ]] || [ "$NUM" -lt 1 ] || [ "$NUM" -gt "${#USER_ARR[@]}" ] && echo "❌ Numéro invalide" && return
            USER_DELETE="${USER_ARR[$((NUM-1))]}"
            TMP_JSON=$(mktemp)
            jq --arg nom "$NOM_CLIENT" --arg userdel "$USER_DELETE" \
               '(.bots[] | select(.NomBot == $nom) | .Utilisateurs) |= map(select(.nom != $userdel))' \
               "$BOTS_CLIENT" > "$TMP_JSON" && mv "$TMP_JSON" "$BOTS_CLIENT"
            echo "✅ Utilisateur $USER_DELETE supprimé du client bot $NOM_CLIENT"
            ;;
        2)
            read -p "Nom du nouvel utilisateur : " NEW_USER
            read -p "Durée d'expiration en jours : " DAYS
            EXP_DATE=$(date -d "+$DAYS days" +%Y-%m-%d)
            TMP_JSON=$(mktemp)
            jq --arg nom "$NOM_CLIENT" --arg name "$NEW_USER" --arg expire "$EXP_DATE" \
               '(.bots[] | select(.NomBot == $nom) | .Utilisateurs) += [{"nom": $name, "expire": $expire}]' \
               "$BOTS_CLIENT" > "$TMP_JSON" && mv "$TMP_JSON" "$BOTS_CLIENT"
            echo "✅ Utilisateur $NEW_USER ajouté avec expiration $EXP_DATE"
            ;;
        *)
            echo "❌ Option invalide"
            ;;
    esac

    sudo chmod 600 "$BOTS_CLIENT"
    sudo chown root:root "$BOTS_CLIENT"
}

create_systemd_service() {
    read -p "🔑 Entrez votre BOT_TOKEN : " BOT_TOKEN
    read -p "🆔 Entrez votre ADMIN_ID : " ADMIN_ID

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
    echo "3️⃣  Ajouter un client bot"
    echo "4️⃣  Gérer les utilisateurs d'un client bot"
    echo "5️⃣  Arrêter / Désinstaller le bot"
    echo "6️⃣  Quitter"
    echo "======================================"
    read -p "👉 Choisissez une option [1-6] : " option

    case "$option" in
        1) 
            echo "⏳ Vérification de Go..."
            command -v go >/dev/null 2>&1 || { echo "❌ Go n'est pas installé"; read -p "Entrée pour continuer..."; continue; }
            cd "$SCRIPT_DIR" || continue
            [ ! -f "go.mod" ] && go mod init telegram-bot
            go mod tidy
            if go build -o bot2 bot2.go; then echo "✅ Bot compilé"; else echo "❌ Erreur de compilation"; fi
            sudo chown root:root "$BOT_BIN"
            sudo chmod +x "$BOT_BIN"
            read -p "Entrée pour continuer..."
            ;;
        2)
            [ ! -f "$BOT_BIN" ] && { echo "❌ Bot non compilé"; read -p "Entrée pour continuer..."; continue; }
            create_systemd_service
            read -p "Entrée pour continuer..."
            ;;
        3)
            ajouter_client_bot
            read -p "Entrée pour continuer..."
            ;;
        4)
            gerer_utilisateurs_client
            read -p "Entrée pour continuer..."
            ;;
        5)
            stop_and_uninstall_bot
            read -p "Entrée pour continuer..."
            ;;
        6)
            echo "👋 Au revoir"
            exit 0
            ;;
        *)
            echo "❌ Option invalide"
            read -p "Entrée pour continuer..."
            ;;
    esac
done
