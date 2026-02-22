#!/bin/bash
# ==========================================
# Auto-clean pour V2Ray & ZIVPN
# Nettoyage automatique des utilisateurs expirés
# ==========================================
set -euo pipefail

LOG_FILE="/var/log/auto-clean.log"
TODAY=$(date +%Y-%m-%d)

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🔹 Début du nettoyage automatique" >> "$LOG_FILE"

# ===============================
# 1️⃣ Nettoyage V2Ray
# ===============================
USER_DB="/etc/v2ray/utilisateurs.json"
CONFIG="/etc/v2ray/config.json"

if [[ -f "$USER_DB" && -f "$CONFIG" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🔹 Nettoyage utilisateurs V2Ray expirés" >> "$LOG_FILE"

    uuids_expire=$(jq -r --arg today "$TODAY" '.[] | select(.expire < $today) | .uuid' "$USER_DB")

    if [[ -n "$(echo "$uuids_expire" | tr -d '[:space:]')" ]]; then
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

        jq --arg today "$TODAY" '[.[] | select(.expire >= $today)]' "$USER_DB" > "$USER_DB"

        systemctl restart v2ray
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ V2Ray mis à jour et service redémarré" >> "$LOG_FILE"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ℹ️ Aucun utilisateur V2Ray expiré" >> "$LOG_FILE"
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ Fichiers V2Ray introuvables, nettoyage ignoré" >> "$LOG_FILE"
fi

# ===============================
# 2️⃣ Nettoyage ZIVPN
# ===============================
clean_zivpn_users() {
    ZIVPN_USER_FILE="/etc/zivpn/users.list"
    ZIVPN_CONFIG="/etc/zivpn/config.json"
    ZIVPN_SERVICE="zivpn.service"

    if [[ ! -f "$ZIVPN_USER_FILE" || ! -f "$ZIVPN_CONFIG" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ Fichiers ZIVPN introuvables, nettoyage ignoré" >> "$LOG_FILE"
        return
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🔹 Nettoyage utilisateurs ZIVPN expirés" >> "$LOG_FILE"

    TMP_FILE=$(mktemp)
    awk -F'|' -v today="$TODAY" '$3>=today {print $0}' "$ZIVPN_USER_FILE" > "$TMP_FILE" || true
    mv "$TMP_FILE" "$ZIVPN_USER_FILE"
    chmod 600 "$ZIVPN_USER_FILE"

    PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" | sort -u | paste -sd, -)
    if jq --arg passwords "$PASSWORDS" '.auth.config = ($passwords | split(","))' "$ZIVPN_CONFIG" > /tmp/config.json 2>/dev/null &&
       jq empty /tmp/config.json >/dev/null 2>&1; then
        mv /tmp/config.json "$ZIVPN_CONFIG"
        systemctl restart "$ZIVPN_SERVICE"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ ZIVPN mis à jour et service redémarré" >> "$LOG_FILE"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ Erreur JSON, ZIVPN non mis à jour" >> "$LOG_FILE"
        rm -f /tmp/config.json
    fi
}

# Appel de la fonction de nettoyage ZIVPN
clean_zivpn_users

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🔹 Fin du nettoyage automatique" >> "$LOG_FILE"
