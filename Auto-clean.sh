#!/bin/bash

USER_DB="/etc/v2ray/utilisateurs.json"
CONFIG="/etc/v2ray/config.json"

TODAY=$(date +%Y-%m-%d)

if [[ ! -f "$USER_DB" ]]; then
    exit 0
fi

uuids_expire=$(jq -r --arg today "$TODAY" '.[] | select(.expire < $today) | .uuid' "$USER_DB")

if [[ -z "$(echo "$uuids_expire" | tr -d '[:space:]')" ]]; then
    exit 0
fi

tmpfile=$(mktemp)

jq --argjson uuids "$(echo "$uuids_expire" | jq -R -s -c 'split("\n")[:-1]')" '
.inbounds |= map(
    if .protocol=="vless" then
        .settings.clients |= map(select(.id as $id | $uuids | index($id) | not))
    else .
    end
)
' "$CONFIG" > "$tmpfile"

mv "$tmpfile" "$CONFIG"
systemctl restart v2ray

jq --arg today "$TODAY" '[.[] | select(.expire >= $today)]' "$USER_DB" > "$USER_DB"

# ==========================================
# 🔹 Nettoyage automatique des utilisateurs ZIVPN expirés
# ==========================================
clean_zivpn_users() {
    ZIVPN_USER_FILE="/etc/zivpn/users.list"
    ZIVPN_CONFIG="/etc/zivpn/config.json"
    ZIVPN_SERVICE="zivpn.service"

    if [[ ! -f "$ZIVPN_USER_FILE" || ! -f "$ZIVPN_CONFIG" ]]; then
        echo "⚠️  Fichiers ZIVPN introuvables, nettoyage ignoré."
        return
    fi

    echo "🚀 Nettoyage utilisateurs ZIVPN expirés..."

    TODAY=$(date +%Y-%m-%d)

    # Filtrer les utilisateurs encore valides
    TMP_FILE=$(mktemp)
    awk -F'|' -v today="$TODAY" '$3>=today {print $0}' "$ZIVPN_USER_FILE" > "$TMP_FILE" || true
    mv "$TMP_FILE" "$ZIVPN_USER_FILE"
    chmod 600 "$ZIVPN_USER_FILE"

    # Mettre à jour les mots de passe valides dans config.json
    PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" | sort -u | paste -sd, -)
    if jq --arg passwords "$PASSWORDS" '.auth.config = ($passwords | split(","))' "$ZIVPN_CONFIG" > /tmp/config.json 2>/dev/null &&
       jq empty /tmp/config.json >/dev/null 2>&1; then
        mv /tmp/config.json "$ZIVPN_CONFIG"
        systemctl restart "$ZIVPN_SERVICE"
        echo "✅ ZIVPN mis à jour et service redémarré"
    else
        echo "⚠️ Erreur JSON, ZIVPN non mis à jour"
        rm -f /tmp/config.json
    fi
}
