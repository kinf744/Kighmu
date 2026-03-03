#!/bin/bash
# ==========================================
# Auto-clean pour V2Ray, ZIVPN, Xray & Hysteria
# + Gestion de quota de données (via panel KIGHMU)
# Nettoyage automatique des utilisateurs expirés
# ==========================================
set -euo pipefail

LOG_FILE="/var/log/auto-clean.log"
TODAY=$(date +%Y-%m-%d)
TS() { date '+%Y-%m-%d %H:%M:%S'; }

# ==========================================
# ⚙️  CONFIG PANEL (lecture depuis .env)
# ==========================================
PANEL_ENV="/opt/kighmu-panel/.env"
PANEL_URL="http://127.0.0.1:3000"
REPORT_SECRET="kighmu-report-2024"

if [[ -f "$PANEL_ENV" ]]; then
    _port=$(grep '^PORT='            "$PANEL_ENV" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)
    _secret=$(grep '^REPORT_SECRET=' "$PANEL_ENV" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)
    [[ -n "$_port"   ]] && PANEL_URL="http://127.0.0.1:${_port}"
    [[ -n "$_secret" ]] && REPORT_SECRET="$_secret"
fi

XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"
XRAY_API="${XRAY_API:-127.0.0.1:10085}"
V2RAY_BIN="${V2RAY_BIN:-/usr/local/bin/v2ray}"
V2RAY_API="${V2RAY_API:-127.0.0.1:10086}"

echo "[$(TS)] ============================================" >> "$LOG_FILE"
echo "[$(TS)] 🔹 Début du nettoyage automatique + quota"   >> "$LOG_FILE"
echo "[$(TS)] ============================================" >> "$LOG_FILE"

# ==========================================
# 🔧 FONCTION : envoyer stats au panel
# ==========================================
# Usage: send_traffic_stats '{"stats":[{"username":"u1","upload_bytes":100,"download_bytes":200}]}'
send_traffic_stats() {
    local json="$1"
    local resp
    resp=$(curl -s --max-time 10 -X POST "${PANEL_URL}/api/report/traffic" \
        -H "Content-Type: application/json" \
        -H "x-report-secret: ${REPORT_SECRET}" \
        -d "${json}" 2>/dev/null) || true
    echo "[$(TS)] [TRAFFIC] → ${resp:-pas de réponse du panel}" >> "$LOG_FILE"
}

# ==========================================
# 📊 SECTION 0 : Collecte de trafic
# (envoi des stats au panel AVANT le quota check)
# ==========================================

# ── 0a. Xray ────────────────────────────────────────────────
collect_xray_traffic() {
    [[ ! -x "$XRAY_BIN" ]] && return
    local raw
    raw=$("$XRAY_BIN" api statsquery --server="$XRAY_API" 2>/dev/null) || return
    [[ -z "$raw" ]] && return

    local json='{"stats":[' first=1
    declare -A up_map down_map

    while IFS= read -r line; do
        if [[ "$line" =~ name:\"user\>\>\>([^\>]+)\>\>\>traffic\>\>\>(up|down)link\" ]]; then
            local user="${BASH_REMATCH[1]}" dir="${BASH_REMATCH[2]}"
            local val=0
            [[ "$line" =~ value:\"([0-9]+)\" ]] && val="${BASH_REMATCH[1]}"
            [[ "$dir" == "up"   ]] && up_map["$user"]=$(( ${up_map["$user"]:-0}   + val ))
            [[ "$dir" == "down" ]] && down_map["$user"]=$(( ${down_map["$user"]:-0} + val ))
        fi
    done <<< "$raw"

    for user in $(echo "${!up_map[@]} ${!down_map[@]}" | tr ' ' '\n' | sort -u); do
        local up="${up_map[$user]:-0}" dn="${down_map[$user]:-0}"
        (( up + dn == 0 )) && continue
        [[ $first -eq 0 ]] && json+=","
        json+="{\"username\":\"$user\",\"upload_bytes\":$up,\"download_bytes\":$dn}"
        first=0
    done
    json+=']}'

    if [[ $first -eq 0 ]]; then
        echo "[$(TS)] [XRAY] Envoi stats trafic..." >> "$LOG_FILE"
        send_traffic_stats "$json"
    else
        echo "[$(TS)] [XRAY] Aucune stat de trafic" >> "$LOG_FILE"
    fi
}

# ── 0b. V2Ray ───────────────────────────────────────────────
collect_v2ray_traffic() {
    [[ ! -x "$V2RAY_BIN" ]] && return
    local raw
    raw=$("$V2RAY_BIN" api statsquery --server="$V2RAY_API" 2>/dev/null) || return
    [[ -z "$raw" ]] && return

    local json='{"stats":[' first=1
    declare -A up_map down_map

    while IFS= read -r line; do
        if [[ "$line" =~ name:\"user\>\>\>([^\>]+)\>\>\>traffic\>\>\>(up|down)link\" ]]; then
            local user="${BASH_REMATCH[1]}" dir="${BASH_REMATCH[2]}"
            local val=0
            [[ "$line" =~ value:\"([0-9]+)\" ]] && val="${BASH_REMATCH[1]}"
            [[ "$dir" == "up"   ]] && up_map["$user"]=$(( ${up_map["$user"]:-0}   + val ))
            [[ "$dir" == "down" ]] && down_map["$user"]=$(( ${down_map["$user"]:-0} + val ))
        fi
    done <<< "$raw"

    for user in $(echo "${!up_map[@]} ${!down_map[@]}" | tr ' ' '\n' | sort -u); do
        local up="${up_map[$user]:-0}" dn="${down_map[$user]:-0}"
        (( up + dn == 0 )) && continue
        [[ $first -eq 0 ]] && json+=","
        json+="{\"username\":\"$user\",\"upload_bytes\":$up,\"download_bytes\":$dn}"
        first=0
    done
    json+=']}'

    if [[ $first -eq 0 ]]; then
        echo "[$(TS)] [V2RAY] Envoi stats trafic..." >> "$LOG_FILE"
        send_traffic_stats "$json"
    else
        echo "[$(TS)] [V2RAY] Aucune stat de trafic" >> "$LOG_FILE"
    fi
}

# ── 0c. SSH via iptables (par uid système) ──────────────────
collect_ssh_traffic() {
    local USER_FILE="/etc/kighmu/users.list"
    [[ ! -f "$USER_FILE" ]] && return
    command -v iptables &>/dev/null || return

    local json='{"stats":[' first=1

    while IFS='|' read -r username _rest; do
        [[ -z "$username" ]] && continue
        local uid
        uid=$(id -u "$username" 2>/dev/null) || continue
        local up dn
        dn=$(iptables -n -L OUTPUT -v -x 2>/dev/null | awk -v u="$uid" '$0 ~ "uid-owner " u {sum+=$2} END{print sum+0}')
        up=$(iptables -n -L INPUT  -v -x 2>/dev/null | awk -v u="$uid" '$0 ~ "uid-owner " u {sum+=$2} END{print sum+0}')
        (( ${up:-0} + ${dn:-0} == 0 )) && continue
        [[ $first -eq 0 ]] && json+=","
        json+="{\"username\":\"$username\",\"upload_bytes\":${up:-0},\"download_bytes\":${dn:-0}}"
        first=0
    done < "$USER_FILE"
    json+=']}'

    if [[ $first -eq 0 ]]; then
        echo "[$(TS)] [SSH] Envoi stats trafic..." >> "$LOG_FILE"
        send_traffic_stats "$json"
    fi
}

echo "[$(TS)] 📊 Collecte des stats de trafic..." >> "$LOG_FILE"
collect_xray_traffic
collect_v2ray_traffic
collect_ssh_traffic

# ==========================================
# 🔒 SECTION 1 : Vérification quota data
# Lecture depuis MySQL → bloc VPN côté VPS
# ==========================================

# ── Lecture config MySQL depuis .env ────────────────────────
DB_HOST="127.0.0.1"
DB_PORT="3306"
DB_NAME="kighmu_panel"
DB_USER_CONF=""
DB_PASS_CONF=""

if [[ -f "$PANEL_ENV" ]]; then
    DB_HOST=$(grep '^DB_HOST='     "$PANEL_ENV" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "127.0.0.1")
    DB_PORT=$(grep '^DB_PORT='     "$PANEL_ENV" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "3306")
    DB_NAME=$(grep '^DB_NAME='     "$PANEL_ENV" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "kighmu_panel")
    DB_USER_CONF=$(grep '^DB_USER=' "$PANEL_ENV" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)
    DB_PASS_CONF=$(grep '^DB_PASSWORD=' "$PANEL_ENV" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)
fi

# Vérifie que mysql est dispo et que les creds sont présents
MYSQL_OK=0
if command -v mysql &>/dev/null && [[ -n "$DB_USER_CONF" ]]; then
    if mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER_CONF" -p"$DB_PASS_CONF" \
        -e "USE ${DB_NAME};" 2>/dev/null; then
        MYSQL_OK=1
    fi
fi

# Raccourci pour exécuter une requête MySQL
mysql_query() {
    mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER_CONF" -p"$DB_PASS_CONF" \
        -N -s "$DB_NAME" -e "$1" 2>/dev/null
}

# ── Fonctions de blocage/déblocage locales ──────────────────

block_xray_user() {
    local username="$1" uuid="$2" protocol="$3"
    local cfg="/etc/xray/config.json"
    [[ ! -f "$cfg" ]] && return
    # Supprime le client de la config Xray
    local tmp; tmp=$(mktemp)
    if [[ "$protocol" == "trojan" ]]; then
        jq --arg u "$username" '
          .inbounds |= map(
            if .protocol=="trojan" then
              .settings.clients |= map(select(.password != $u and .email != $u))
            else . end)' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
    else
        jq --arg id "$uuid" --arg email "$username" '
          .inbounds |= map(
            if (.protocol=="vmess" or .protocol=="vless") then
              .settings.clients |= map(select(.id != $id and .email != $email))
            else . end)' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
    fi
    systemctl restart xray 2>/dev/null || true
    echo "[$(TS)] [QUOTA] 🔒 Xray bloqué : $username ($protocol)" >> "$LOG_FILE"
}

block_v2ray_user() {
    local username="$1" uuid="$2"
    local cfg="${V2RAY_CONFIG:-/etc/v2ray/config.json}"
    [[ ! -f "$cfg" ]] && return
    local tmp; tmp=$(mktemp)
    jq --arg id "$uuid" --arg email "$username" '
      .inbounds |= map(
        if .settings.clients then
          .settings.clients |= map(select(.id != $id and .email != $email))
        else . end)' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
    systemctl restart v2ray 2>/dev/null || true
    echo "[$(TS)] [QUOTA] 🔒 V2Ray bloqué : $username" >> "$LOG_FILE"
}

block_ssh_user() {
    local username="$1"
    passwd -l "$username" 2>/dev/null || true
    echo "[$(TS)] [QUOTA] 🔒 SSH bloqué : $username" >> "$LOG_FILE"
}

block_zivpn_user() {
    local username="$1"
    local user_file="/etc/zivpn/users.list"
    local cfg="/etc/zivpn/config.json"
    [[ ! -f "$user_file" ]] && return
    sed -i "/^${username}|/d" "$user_file"
    # Resync config.json
    local passwords
    passwords=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$user_file" | sort -u | paste -sd, -)
    if [[ -n "$passwords" ]]; then
        local tmp; tmp=$(mktemp)
        jq --arg p "$passwords" '.auth.config = ($p | split(","))' "$cfg" > "$tmp" \
            && mv "$tmp" "$cfg" || rm -f "$tmp"
    fi
    systemctl restart zivpn 2>/dev/null || true
    echo "[$(TS)] [QUOTA] 🔒 ZIVPN bloqué : $username" >> "$LOG_FILE"
}

block_hysteria_user() {
    local username="$1"
    local user_file="/etc/hysteria/users.txt"
    local cfg="/etc/hysteria/config.json"
    [[ ! -f "$user_file" ]] && return
    sed -i "/^${username}|/d" "$user_file"
    local passwords
    passwords=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$user_file" | sort -u | paste -sd, -)
    if [[ -n "$passwords" ]]; then
        local tmp; tmp=$(mktemp)
        jq --arg p "$passwords" '.auth.config = ($p | split(","))' "$cfg" > "$tmp" \
            && mv "$tmp" "$cfg" || rm -f "$tmp"
    fi
    systemctl restart hysteria 2>/dev/null || true
    echo "[$(TS)] [QUOTA] 🔒 Hysteria bloqué : $username" >> "$LOG_FILE"
}

# ── Vérification quota par client ───────────────────────────
check_quota() {
    if [[ $MYSQL_OK -eq 0 ]]; then
        echo "[$(TS)] [QUOTA] ⚠️  MySQL non accessible — vérification quota ignorée" >> "$LOG_FILE"
        return
    fi

    echo "[$(TS)] 🔒 Vérification des quotas de données..." >> "$LOG_FILE"

    # Clients avec quota dépassé (data_limit_gb > 0, actifs, pas encore bloqués)
    local query="
      SELECT
        c.id,
        c.username,
        c.uuid,
        c.tunnel_type,
        c.data_limit_gb,
        c.password,
        c.expires_at,
        COALESCE(SUM(u.upload_bytes + u.download_bytes), 0) AS total_bytes
      FROM clients c
      LEFT JOIN usage_stats u ON u.client_id = c.id
      WHERE c.data_limit_gb > 0
        AND c.is_active = 1
        AND c.quota_blocked = 0
        AND c.expires_at > NOW()
      GROUP BY c.id
      HAVING total_bytes >= (c.data_limit_gb * 1073741824);"

    local blocked_count=0

    while IFS=$'\t' read -r cid username uuid tunnel_type data_limit_gb password expires_at total_bytes; do
        [[ -z "$username" ]] && continue

        local used_gb
        used_gb=$(awk "BEGIN {printf \"%.2f\", $total_bytes / 1073741824}")
        echo "[$(TS)] [QUOTA] ⚠️  Quota dépassé : $username — ${used_gb}Go / ${data_limit_gb}Go ($tunnel_type)" >> "$LOG_FILE"

        # Bloquer côté VPS selon le type de tunnel
        case "$tunnel_type" in
            vless|vmess)
                block_xray_user "$username" "$uuid" "$tunnel_type" ;;
            trojan)
                block_xray_user "$username" "$username" "trojan" ;;
            v2ray-fastdns)
                block_v2ray_user "$username" "$uuid" ;;
            ssh-multi|ssh-ws|ssh-slowdns|ssh-ssl|ssh-udp)
                block_ssh_user "$username" ;;
            udp-zivpn)
                block_zivpn_user "$username" ;;
            udp-hysteria)
                block_hysteria_user "$username" ;;
            *)
                echo "[$(TS)] [QUOTA] ⚠️  Type tunnel inconnu : $tunnel_type (user=$username)" >> "$LOG_FILE" ;;
        esac

        # Mettre à jour la DB : quota_blocked=1, is_active=0
        mysql_query "UPDATE clients SET quota_blocked=1, is_active=0 WHERE id=${cid};" || true

        (( blocked_count++ ))
    done < <(mysql_query "$query")

    if [[ $blocked_count -gt 0 ]]; then
        echo "[$(TS)] [QUOTA] 🔒 $blocked_count client(s) bloqué(s) pour quota dépassé" >> "$LOG_FILE"
    else
        echo "[$(TS)] [QUOTA] ✅ Aucun quota dépassé" >> "$LOG_FILE"
    fi

    # ── Vérification quota revendeurs ───────────────────────
    local reseller_query="
      SELECT
        r.id,
        r.username,
        r.data_limit_gb,
        COALESCE(SUM(u.upload_bytes + u.download_bytes), 0) AS total_bytes
      FROM resellers r
      LEFT JOIN usage_stats u ON u.reseller_id = r.id
      WHERE r.data_limit_gb > 0
        AND r.is_active = 1
        AND r.expires_at > NOW()
      GROUP BY r.id
      HAVING total_bytes >= (r.data_limit_gb * 1073741824);"

    local reseller_blocked=0

    while IFS=$'\t' read -r rid r_username r_limit_gb r_total_bytes; do
        [[ -z "$r_username" ]] && continue

        local r_used_gb
        r_used_gb=$(awk "BEGIN {printf \"%.2f\", $r_total_bytes / 1073741824}")
        echo "[$(TS)] [QUOTA] ⚠️  Quota revendeur dépassé : $r_username — ${r_used_gb}Go / ${r_limit_gb}Go" >> "$LOG_FILE"

        # Récupérer tous les clients actifs de ce revendeur et les bloquer
        local clients_query="
          SELECT id, username, uuid, tunnel_type, password, expires_at
          FROM clients
          WHERE reseller_id=${rid}
            AND is_active=1
            AND quota_blocked=0;"

        while IFS=$'\t' read -r cid c_username c_uuid c_tunnel c_pass c_exp; do
            [[ -z "$c_username" ]] && continue
            case "$c_tunnel" in
                vless|vmess)
                    block_xray_user "$c_username" "$c_uuid" "$c_tunnel" ;;
                trojan)
                    block_xray_user "$c_username" "$c_username" "trojan" ;;
                v2ray-fastdns)
                    block_v2ray_user "$c_username" "$c_uuid" ;;
                ssh-multi|ssh-ws|ssh-slowdns|ssh-ssl|ssh-udp)
                    block_ssh_user "$c_username" ;;
                udp-zivpn)
                    block_zivpn_user "$c_username" ;;
                udp-hysteria)
                    block_hysteria_user "$c_username" ;;
            esac
            mysql_query "UPDATE clients SET quota_blocked=1, is_active=0 WHERE id=${cid};" || true
        done < <(mysql_query "$clients_query")

        (( reseller_blocked++ ))
    done < <(mysql_query "$reseller_query")

    if [[ $reseller_blocked -gt 0 ]]; then
        echo "[$(TS)] [QUOTA] 🔒 $reseller_blocked revendeur(s) bloqué(s) pour quota dépassé" >> "$LOG_FILE"
    fi
}

check_quota

# ===============================
# 1️⃣ Nettoyage V2Ray
# ===============================
USER_DB="/etc/v2ray/utilisateurs.json"
CONFIG="/etc/v2ray/config.json"

if [[ -f "$USER_DB" && -f "$CONFIG" ]]; then
    echo "[$(TS)] 🔹 Nettoyage utilisateurs V2Ray expirés" >> "$LOG_FILE"

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

        jq --arg today "$TODAY" '[.[] | select(.expire >= $today)]' "$USER_DB" > "$USER_DB.tmp"
        mv "$USER_DB.tmp" "$USER_DB"

        systemctl restart v2ray
        echo "[$(TS)] ✅ V2Ray mis à jour et service redémarré" >> "$LOG_FILE"
    else
        echo "[$(TS)] ℹ️ Aucun utilisateur V2Ray expiré" >> "$LOG_FILE"
    fi
else
    echo "[$(TS)] ⚠️ Fichiers V2Ray introuvables, nettoyage ignoré" >> "$LOG_FILE"
fi

# ===============================
# 2️⃣ Nettoyage ZIVPN
# ===============================
clean_zivpn_users() {
    ZIVPN_USER_FILE="/etc/zivpn/users.list"
    ZIVPN_CONFIG="/etc/zivpn/config.json"
    ZIVPN_SERVICE="zivpn.service"

    [[ ! -f "$ZIVPN_USER_FILE" || ! -f "$ZIVPN_CONFIG" ]] && return

    echo "[$(TS)] 🔹 Nettoyage utilisateurs ZIVPN expirés" >> "$LOG_FILE"

    NUM_BEFORE=$(wc -l < "$ZIVPN_USER_FILE")
    TMP_FILE=$(mktemp)
    awk -F'|' -v today="$TODAY" '$3>=today {print $0}' "$ZIVPN_USER_FILE" > "$TMP_FILE" || true
    mv "$TMP_FILE" "$ZIVPN_USER_FILE"
    chmod 600 "$ZIVPN_USER_FILE"

    PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" | sort -u | paste -sd, -)
    if jq --arg passwords "$PASSWORDS" '.auth.config = ($passwords | split(","))' "$ZIVPN_CONFIG" > /tmp/config.json 2>/dev/null &&
       jq empty /tmp/config.json >/dev/null 2>&1; then
        mv /tmp/config.json "$ZIVPN_CONFIG"

        NUM_AFTER=$(wc -l < "$ZIVPN_USER_FILE")
        [[ "$NUM_AFTER" -lt "$NUM_BEFORE" ]] && systemctl restart "$ZIVPN_SERVICE"

        echo "[$(TS)] ✅ ZIVPN mis à jour et service redémarré" >> "$LOG_FILE"
    else
        echo "[$(TS)] ⚠️ Erreur JSON, ZIVPN non mis à jour" >> "$LOG_FILE"
        rm -f /tmp/config.json
    fi
}

# ===============================
# 3️⃣ Nettoyage Xray (VMess/VLESS/Trojan)
# ===============================
clean_xray_users() {
    XRAY_USERS="/etc/xray/users.json"
    XRAY_CONFIG="/etc/xray/config.json"
    XRAY_EXPIRY="/etc/xray/users_expiry.list"

    [[ ! -f "$XRAY_USERS" || ! -f "$XRAY_CONFIG" ]] && return

    echo "[$(TS)] 🔹 Nettoyage Xray utilisateurs expirés" >> "$LOG_FILE"

    expired_vmess=$(jq -r --arg today "$TODAY" '.vmess[]? | select(.expire < $today) | .uuid' "$XRAY_USERS")
    expired_vless=$(jq -r --arg today "$TODAY" '.vless[]? | select(.expire < $today) | .uuid' "$XRAY_USERS")
    expired_trojan=$(jq -r --arg today "$TODAY" '.trojan[]? | select(.expire < $today) | .password' "$XRAY_USERS")

    if [[ -z "$expired_vmess$expired_vless$expired_trojan" ]]; then
        echo "[$(TS)] ℹ️ Aucun utilisateur Xray expiré" >> "$LOG_FILE"
        return
    fi

    NUM_BEFORE=$(jq '.vmess | length + .vless | length + .trojan | length' "$XRAY_USERS")
    tmp_config=$(mktemp)
    tmp_users=$(mktemp)

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

    jq --arg today "$TODAY" '
    .vmess |= map(select(.expire >= $today)) |
    .vless |= map(select(.expire >= $today)) |
    .trojan |= map(select(.expire >= $today))
    ' "$XRAY_USERS" > "$tmp_users" && mv "$tmp_users" "$XRAY_USERS"

    [[ -f "$XRAY_EXPIRY" ]] && sed -i "/|$TODAY/d" "$XRAY_EXPIRY"

    NUM_AFTER=$(jq '.vmess | length + .vless | length + .trojan | length' "$XRAY_USERS")
    [[ "$NUM_AFTER" -lt "$NUM_BEFORE" ]] && systemctl restart xray

    echo "[$(TS)] ✅ Xray nettoyé et service redémarré" >> "$LOG_FILE"
}

# ===============================
# 4️⃣ Nettoyage Hysteria udp
# ===============================
clean_hysteria_users() {
    HYSTERIA_USER_FILE="/etc/hysteria/users.txt"
    HYSTERIA_CONFIG="/etc/hysteria/config.json"
    HYSTERIA_SERVICE="hysteria.service"

    echo "[$(TS)] 🔹 Début du nettoyage Hysteria" >> "$LOG_FILE"

    [[ ! -f "$HYSTERIA_USER_FILE" ]] && { echo "[$(TS)] ⚠️ users.txt introuvable, nettoyage ignoré" >> "$LOG_FILE"; return; }

    NUM_BEFORE=$(wc -l < "$HYSTERIA_USER_FILE")
    EXPIRED=$(awk -F'|' -v today="$TODAY" '$3<today {print $0}' "$HYSTERIA_USER_FILE")

    if [[ -z "$EXPIRED" ]]; then
        echo "[$(TS)] ℹ️ Aucun utilisateur Hysteria expiré" >> "$LOG_FILE"
        return
    fi

    echo "[$(TS)] 🔹 Utilisateurs expirés détectés" >> "$LOG_FILE"
    while IFS='|' read -r PHONE PASS EXPIRE; do
        echo "[$(TS)] 🗑️ Supprimé: Utilisateur=$PHONE, Expire=$EXPIRE" >> "$LOG_FILE"
    done <<< "$EXPIRED"

    awk -F'|' -v today="$TODAY" '$3>=today {print $0}' "$HYSTERIA_USER_FILE" > "$HYSTERIA_USER_FILE.tmp"
    mv "$HYSTERIA_USER_FILE.tmp" "$HYSTERIA_USER_FILE"
    chmod 600 "$HYSTERIA_USER_FILE"

    PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$HYSTERIA_USER_FILE" | sort -u | paste -sd, -)
    if jq --arg passwords "$PASSWORDS" '.auth.config = ($passwords | split(","))' "$HYSTERIA_CONFIG" > /tmp/config.json &&
       jq empty /tmp/config.json >/dev/null 2>&1; then
        mv /tmp/config.json "$HYSTERIA_CONFIG"

        NUM_AFTER=$(wc -l < "$HYSTERIA_USER_FILE")
        [[ "$NUM_AFTER" -lt "$NUM_BEFORE" ]] && systemctl restart "$HYSTERIA_SERVICE"

        echo "[$(TS)] ✅ Hysteria mis à jour et service redémarré" >> "$LOG_FILE"
    else
        echo "[$(TS)] ⚠️ Erreur JSON, config inchangée" >> "$LOG_FILE"
        rm -f /tmp/config.json
    fi

    echo "[$(TS)] 🔹 Fin du nettoyage Hysteria" >> "$LOG_FILE"
}

# ==========================================
# 🔹 Appel des fonctions de nettoyage expiration
# ==========================================
clean_zivpn_users
clean_xray_users
clean_hysteria_users

echo "[$(TS)] ✅ Nettoyage automatique + quota terminé" >> "$LOG_FILE"
echo "[$(TS)] ============================================" >> "$LOG_FILE"
