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

# ==========================================
# 🔹 Nettoyage automatique Xray (VMess/VLESS/Trojan)
# ==========================================
clean_xray_users() {

    XRAY_USERS="/etc/xray/users.json"
    XRAY_CONFIG="/etc/xray/config.json"
    XRAY_EXPIRY="/etc/xray/users_expiry.list"

    [[ ! -f "$XRAY_USERS" || ! -f "$XRAY_CONFIG" ]] && return

    echo "🚀 Nettoyage Xray en cours..."

    TODAY=$(date +%Y-%m-%d)

    # UUID VMESS expirés
    expired_vmess=$(jq -r --arg today "$TODAY" '.vmess[]? | select(.expire < $today) | .uuid' "$XRAY_USERS")

    # UUID VLESS expirés
    expired_vless=$(jq -r --arg today "$TODAY" '.vless[]? | select(.expire < $today) | .uuid' "$XRAY_USERS")

    # Password TROJAN expirés
    expired_trojan=$(jq -r --arg today "$TODAY" '.trojan[]? | select(.expire < $today) | .password' "$XRAY_USERS")

    if [[ -z "$expired_vmess$expired_vless$expired_trojan" ]]; then
        echo "✔ Aucun utilisateur Xray expiré"
        return
    fi

    tmp_config=$(mktemp)
    tmp_users=$(mktemp)

    # Supprimer VMESS & VLESS dans config.json
    jq --argjson ids "$(printf '%s\n%s\n' "$expired_vmess" "$expired_vless" | jq -R -s -c 'split("\n")[:-1]')" \
       --argjson pw "$(printf '%s\n' "$expired_trojan" | jq -R -s -c 'split("\n")[:-1]')" '
    .inbounds |= map(
        if .protocol=="vmess" or .protocol=="vless" then
            .settings.clients |= map(select(.id as $id | $ids | index($id) | not))
        elif .protocol=="trojan" then
            .settings.clients |= map(select(.password as $p | $pw | index($p) | not))
        else .
        end
    )
    ' "$XRAY_CONFIG" > "$tmp_config" && mv "$tmp_config" "$XRAY_CONFIG"

    # Nettoyer users.json
    jq --arg today "$TODAY" '
    .vmess |= map(select(.expire >= $today)) |
    .vless |= map(select(.expire >= $today)) |
    .trojan |= map(select(.expire >= $today))
    ' "$XRAY_USERS" > "$tmp_users" && mv "$tmp_users" "$XRAY_USERS"

    # Nettoyer users_expiry.list si existe
    [[ -f "$XRAY_EXPIRY" ]] && sed -i "/|$TODAY/d" "$XRAY_EXPIRY"

    systemctl restart xray
    echo "✅ Xray nettoyé et redémarré"
}

# ===============================
# 1️⃣ Nettoyage Hysteria udp
# ===============================
clean_hysteria_users() {
    HYSTERIA_USER_FILE="/etc/hysteria/users.txt"
    HYSTERIA_CONFIG="/etc/hysteria/config.json"
    HYSTERIA_SERVICE="hysteria.service"
    LOG_FILE="/var/log/hysteria-auto-clean.log"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🔹 Début du nettoyage Hysteria" >> "$LOG_FILE"

    # Vérifier que le fichier users existe
    if [[ ! -f "$HYSTERIA_USER_FILE" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ users.txt introuvable, nettoyage ignoré" >> "$LOG_FILE"
        return
    fi

    # Extraire les utilisateurs expirés
    EXPIRED=$(awk -F'|' -v today="$TODAY" '$3<today {print $0}' "$HYSTERIA_USER_FILE")
    if [[ -z "$EXPIRED" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ℹ️ Aucun utilisateur Hysteria expiré" >> "$LOG_FILE"
        return
    fi

    # Logger les utilisateurs supprimés
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🔹 Utilisateurs expirés détectés" >> "$LOG_FILE"
    while IFS='|' read -r PHONE PASS EXPIRE; do
        echo "🗑️ Supprimé: Téléphone=$PHONE, Password=$PASS, Expire=$EXPIRE" >> "$LOG_FILE"
    done <<< "$EXPIRED"

    # Supprimer les utilisateurs expirés
    awk -F'|' -v today="$TODAY" '$3>=today {print $0}' "$HYSTERIA_USER_FILE" > "$HYSTERIA_USER_FILE.tmp"
    mv "$HYSTERIA_USER_FILE.tmp" "$HYSTERIA_USER_FILE"
    chmod 600 "$HYSTERIA_USER_FILE"

    # Mettre à jour config.json
    PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$HYSTERIA_USER_FILE" | sort -u | paste -sd, -)
    if jq --arg passwords "$PASSWORDS" '.auth.config = ($passwords | split(","))' "$HYSTERIA_CONFIG" > /tmp/config.json &&
       jq empty /tmp/config.json >/dev/null 2>&1; then
        mv /tmp/config.json "$HYSTERIA_CONFIG"
        systemctl restart "$HYSTERIA_SERVICE"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Hysteria mis à jour et service redémarré" >> "$LOG_FILE"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ Erreur JSON, config inchangée" >> "$LOG_FILE"
        rm -f /tmp/config.json
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🔹 Fin du nettoyage Hysteria" >> "$LOG_FILE"
}

# Appel de la fonction de nettoyage ZIVPN
clean_zivpn_users
clean_xray_users
clean_hysteria_users

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🔹 Fin du nettoyage automatique" >> "$LOG_FILE"
