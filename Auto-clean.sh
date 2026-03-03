#!/bin/bash
# ==========================================
# Auto-clean + collecte trafic + quota data
# V2Ray, ZIVPN, Xray, Hysteria & SSH
# ==========================================
set -euo pipefail

LOG_FILE="/var/log/auto-clean.log"
TODAY=$(date +%Y-%m-%d)
TS() { date '+%Y-%m-%d %H:%M:%S'; }

# ── Config panel (lu depuis .env) ───────────────────────────
PANEL_ENV="/opt/kighmu-panel/.env"
PANEL_URL="http://127.0.0.1:3000"
REPORT_SECRET="kighmu-report-2024"
if [[ -f "$PANEL_ENV" ]]; then
    _p=$(grep '^PORT='           "$PANEL_ENV" 2>/dev/null | cut -d= -f2 | tr -d '"' || true)
    _s=$(grep '^REPORT_SECRET=' "$PANEL_ENV" 2>/dev/null | cut -d= -f2 | tr -d '"' || true)
    [[ -n "$_p" ]] && PANEL_URL="http://127.0.0.1:${_p}"
    [[ -n "$_s" ]] && REPORT_SECRET="$_s"
fi

# ── Config MySQL (lu depuis .env) ────────────────────────────
DB_HOST="127.0.0.1"; DB_PORT="3306"; DB_NAME="kighmu_panel"
DB_USER_CONF=""; DB_PASS_CONF=""
if [[ -f "$PANEL_ENV" ]]; then
    DB_HOST=$(grep '^DB_HOST='     "$PANEL_ENV" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "127.0.0.1")
    DB_PORT=$(grep '^DB_PORT='     "$PANEL_ENV" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "3306")
    DB_NAME=$(grep '^DB_NAME='     "$PANEL_ENV" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "kighmu_panel")
    DB_USER_CONF=$(grep '^DB_USER='     "$PANEL_ENV" 2>/dev/null | cut -d= -f2 | tr -d '"' || true)
    DB_PASS_CONF=$(grep '^DB_PASSWORD=' "$PANEL_ENV" 2>/dev/null | cut -d= -f2 | tr -d '"' || true)
fi

MYSQL_OK=0
if command -v mysql &>/dev/null && [[ -n "$DB_USER_CONF" ]]; then
    if mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER_CONF" -p"$DB_PASS_CONF" \
        -e "USE ${DB_NAME};" 2>/dev/null; then
        MYSQL_OK=1
    fi
fi
mysql_query() {
    mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER_CONF" -p"$DB_PASS_CONF" \
        -N -s "$DB_NAME" -e "$1" 2>/dev/null
}

echo "[$(TS)] ============================================" >> "$LOG_FILE"
echo "[$(TS)] Debut nettoyage + collecte trafic + quota"   >> "$LOG_FILE"

# ==========================================
# SECTION 0 : Collecte trafic -> panel
# ==========================================

send_stats() {
    local json="$1"
    local resp
    resp=$(curl -s --max-time 10 -X POST "${PANEL_URL}/api/report/traffic" \
        -H "Content-Type: application/json" \
        -H "x-report-secret: ${REPORT_SECRET}" \
        -d "${json}" 2>/dev/null) || true
    echo "[$(TS)] [TRAFFIC] -> ${resp:-pas de reponse}" >> "$LOG_FILE"
}

# -- 0a. Xray --
collect_xray_traffic() {
    local XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"
    local XRAY_API="${XRAY_API:-127.0.0.1:10085}"
    [[ ! -x "$XRAY_BIN" ]] && return
    local raw
    raw=$("$XRAY_BIN" api statsquery --server="$XRAY_API" 2>/dev/null) || return
    [[ -z "$raw" ]] && { echo "[$(TS)] [XRAY] Aucune stat" >> "$LOG_FILE"; return; }

    local json='{"stats":[' first=1
    declare -A up_map down_map

    while IFS= read -r line; do
        if [[ "$line" =~ name:\"user\>\>\>([^\>]+)\>\>\>traffic\>\>\>(up|down)link\" ]]; then
            local user="${BASH_REMATCH[1]}" dir="${BASH_REMATCH[2]}" val=0
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
    json+="]}"
    if [[ $first -eq 0 ]]; then
        echo "[$(TS)] [XRAY] Envoi stats..." >> "$LOG_FILE"
        send_stats "$json"
    else
        echo "[$(TS)] [XRAY] Aucun trafic a reporter" >> "$LOG_FILE"
    fi
}

# -- 0b. V2Ray --
collect_v2ray_traffic() {
    local V2RAY_BIN="${V2RAY_BIN:-/usr/local/bin/v2ray}"
    local V2RAY_API="${V2RAY_API:-127.0.0.1:10086}"
    [[ ! -x "$V2RAY_BIN" ]] && return
    local raw
    raw=$("$V2RAY_BIN" api statsquery --server="$V2RAY_API" 2>/dev/null) || return
    [[ -z "$raw" ]] && return

    local json='{"stats":[' first=1
    declare -A up_map down_map

    while IFS= read -r line; do
        if [[ "$line" =~ name:\"user\>\>\>([^\>]+)\>\>\>traffic\>\>\>(up|down)link\" ]]; then
            local user="${BASH_REMATCH[1]}" dir="${BASH_REMATCH[2]}" val=0
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
    json+="]}"
    [[ $first -eq 0 ]] && send_stats "$json"
}

# -- 0c. SSH delta via iptables KIGHMU_SSH + CONNMARK --
collect_ssh_traffic() {
    local USER_FILE="/etc/kighmu/users.list"
    local DELTA_DIR="/var/lib/kighmu/ssh-counters"
    [[ ! -f "$USER_FILE" ]] && return
    command -v iptables &>/dev/null || return
    mkdir -p "$DELTA_DIR"

    if ! iptables -L KIGHMU_SSH 2>/dev/null | grep -q "Chain KIGHMU_SSH"; then
        echo "[$(TS)] [SSH] Chaine KIGHMU_SSH absente — en attente creation par server.js" >> "$LOG_FILE"
        return
    fi

    local json='{"stats":[' first=1 has_data=0

    while IFS='|' read -r username _rest; do
        [[ -z "$username" ]] && continue
        local uid
        uid=$(id -u "$username" 2>/dev/null) || continue

        local cur_out=0
        cur_out=$(iptables -nvx -L KIGHMU_SSH 2>/dev/null \
            | awk -v uid="$uid" '
                /uid-owner/ && ($0 ~ "uid-owner " uid " " || $0 ~ "uid-owner " uid "$") {
                    sum += $2
                }
                END { print sum + 0 }')

        local hex_mark
        hex_mark=$(printf '0x%x' "$uid")
        local cur_in=0
        cur_in=$(iptables -nvx -L INPUT 2>/dev/null \
            | awk -v mark="$hex_mark" '
                /connmark/ && $0 ~ "mark match " mark { sum += $2 }
                END { print sum + 0 }')

        local prev_out=0 prev_in=0
        [[ -f "${DELTA_DIR}/${username}.out" ]] && prev_out=$(< "${DELTA_DIR}/${username}.out")
        [[ -f "${DELTA_DIR}/${username}.in"  ]] && prev_in=$(<  "${DELTA_DIR}/${username}.in")

        local delta_out delta_in
        (( cur_out >= prev_out )) && delta_out=$(( cur_out - prev_out )) || delta_out=$cur_out
        (( cur_in  >= prev_in  )) && delta_in=$(( cur_in  - prev_in  )) || delta_in=$cur_in

        echo "$cur_out" > "${DELTA_DIR}/${username}.out"
        echo "$cur_in"  > "${DELTA_DIR}/${username}.in"

        (( delta_out + delta_in == 0 )) && continue

        [[ $first -eq 0 ]] && json+=","
        json+="{\"username\":\"${username}\",\"upload_bytes\":${delta_in},\"download_bytes\":${delta_out}}"
        first=0
        has_data=1

        echo "[$(TS)] [SSH-DELTA] $username up:${delta_in}B down:${delta_out}B" >> "$LOG_FILE"
    done < "$USER_FILE"

    json+="]}"
    if [[ $has_data -eq 1 ]]; then
        echo "[$(TS)] [SSH] Envoi stats delta..." >> "$LOG_FILE"
        send_stats "$json"
    else
        echo "[$(TS)] [SSH] Aucun trafic SSH a reporter" >> "$LOG_FILE"
    fi
}

echo "[$(TS)] Collecte des stats de trafic..." >> "$LOG_FILE"
collect_xray_traffic
collect_v2ray_traffic
collect_ssh_traffic

# ==========================================
# SECTION 1 : Verification quota data
# ==========================================
check_quota() {
    if [[ $MYSQL_OK -eq 0 ]]; then
        echo "[$(TS)] [QUOTA] MySQL non accessible — quota ignore" >> "$LOG_FILE"
        return
    fi
    echo "[$(TS)] Verification des quotas..." >> "$LOG_FILE"

    _block_xray() {
        local username="$1" uuid="$2" proto="$3"
        local cfg="/etc/xray/config.json"; [[ ! -f "$cfg" ]] && return
        local tmp; tmp=$(mktemp)
        if [[ "$proto" == "trojan" ]]; then
            jq --arg u "$username" '
              .inbounds |= map(if .protocol=="trojan" then
                .settings.clients |= map(select(.password != $u and .email != $u))
              else . end)' "$cfg" > "$tmp" && mv "$tmp" "$cfg" || rm -f "$tmp"
        else
            jq --arg id "$uuid" --arg em "$username" '
              .inbounds |= map(if (.protocol=="vmess" or .protocol=="vless") then
                .settings.clients |= map(select(.id != $id and .email != $em))
              else . end)' "$cfg" > "$tmp" && mv "$tmp" "$cfg" || rm -f "$tmp"
        fi
        systemctl restart xray 2>/dev/null || true
    }
    _block_v2ray() {
        local username="$1" uuid="$2"
        local cfg="${V2RAY_CONFIG:-/etc/v2ray/config.json}"; [[ ! -f "$cfg" ]] && return
        local tmp; tmp=$(mktemp)
        jq --arg id "$uuid" --arg em "$username" '
          .inbounds |= map(if .settings.clients then
            .settings.clients |= map(select(.id != $id and .email != $em))
          else . end)' "$cfg" > "$tmp" && mv "$tmp" "$cfg" || rm -f "$tmp"
        systemctl restart v2ray 2>/dev/null || true
    }
    _block_ssh()      { passwd -l "$1" 2>/dev/null || true; }
    _block_zivpn() {
        local u="$1" f="/etc/zivpn/users.list" c="/etc/zivpn/config.json"
        [[ ! -f "$f" ]] && return
        sed -i "/^${u}|/d" "$f"
        local pw; pw=$(awk -F'|' -v t="$TODAY" '$3>=t {print $2}' "$f" | sort -u | paste -sd, -)
        [[ -n "$pw" ]] && { local tmp; tmp=$(mktemp); jq --arg p "$pw" '.auth.config=($p|split(","))' "$c" > "$tmp" && mv "$tmp" "$c" || rm -f "$tmp"; }
        systemctl restart zivpn 2>/dev/null || true
    }
    _block_hysteria() {
        local u="$1" f="/etc/hysteria/users.txt" c="/etc/hysteria/config.json"
        [[ ! -f "$f" ]] && return
        sed -i "/^${u}|/d" "$f"
        local pw; pw=$(awk -F'|' -v t="$TODAY" '$3>=t {print $2}' "$f" | sort -u | paste -sd, -)
        [[ -n "$pw" ]] && { local tmp; tmp=$(mktemp); jq --arg p "$pw" '.auth.config=($p|split(","))' "$c" > "$tmp" && mv "$tmp" "$c" || rm -f "$tmp"; }
        systemctl restart hysteria 2>/dev/null || true
    }

    _do_block() {
        local cid="$1" username="$2" uuid="$3" tunnel="$4"
        case "$tunnel" in
            vless|vmess)                                   _block_xray "$username" "$uuid" "$tunnel" ;;
            trojan)                                        _block_xray "$username" "$username" "trojan" ;;
            v2ray-fastdns)                                 _block_v2ray "$username" "$uuid" ;;
            ssh-multi|ssh-ws|ssh-slowdns|ssh-ssl|ssh-udp) _block_ssh "$username" ;;
            udp-zivpn)                                     _block_zivpn "$username" ;;
            udp-hysteria)                                  _block_hysteria "$username" ;;
            *) echo "[$(TS)] [QUOTA] tunnel inconnu: $tunnel ($username)" >> "$LOG_FILE" ;;
        esac
        mysql_query "UPDATE clients SET quota_blocked=1, is_active=0 WHERE id=${cid};" || true
        echo "[$(TS)] [QUOTA] BLOQUE $username ($tunnel) — quota depasse" >> "$LOG_FILE"
    }

    local blocked=0
    while IFS=$'\t' read -r cid username uuid tunnel data_limit total_bytes; do
        [[ -z "$username" ]] && continue
        local used_gb; used_gb=$(awk "BEGIN {printf \"%.2f\", $total_bytes/1073741824}")
        echo "[$(TS)] [QUOTA] $username — ${used_gb}Go / ${data_limit}Go" >> "$LOG_FILE"
        _do_block "$cid" "$username" "$uuid" "$tunnel"
        (( blocked++ ))
    done < <(mysql_query "
        SELECT c.id, c.username, c.uuid, c.tunnel_type, c.data_limit_gb,
               COALESCE(SUM(u.upload_bytes+u.download_bytes),0) AS total_bytes
        FROM clients c
        LEFT JOIN usage_stats u ON u.client_id=c.id
        WHERE c.data_limit_gb > 0 AND c.is_active=1 AND c.quota_blocked=0 AND c.expires_at > NOW()
        GROUP BY c.id
        HAVING total_bytes >= (c.data_limit_gb * 1073741824);")

    [[ $blocked -gt 0 ]] \
        && echo "[$(TS)] [QUOTA] $blocked client(s) bloque(s)" >> "$LOG_FILE" \
        || echo "[$(TS)] [QUOTA] Aucun quota client depasse"   >> "$LOG_FILE"

    local r_blocked=0
    while IFS=$'\t' read -r rid r_user r_limit r_total; do
        [[ -z "$r_user" ]] && continue
        local r_used; r_used=$(awk "BEGIN {printf \"%.2f\", $r_total/1073741824}")
        echo "[$(TS)] [QUOTA] Revendeur $r_user — ${r_used}Go / ${r_limit}Go" >> "$LOG_FILE"
        while IFS=$'\t' read -r cid c_user c_uuid c_tunnel; do
            [[ -z "$c_user" ]] && continue
            _do_block "$cid" "$c_user" "$c_uuid" "$c_tunnel"
        done < <(mysql_query "SELECT id,username,uuid,tunnel_type FROM clients WHERE reseller_id=${rid} AND is_active=1 AND quota_blocked=0;")
        (( r_blocked++ ))
    done < <(mysql_query "
        SELECT r.id, r.username, r.data_limit_gb,
               COALESCE(SUM(u.upload_bytes+u.download_bytes),0) AS total_bytes
        FROM resellers r
        LEFT JOIN usage_stats u ON u.reseller_id=r.id
        WHERE r.data_limit_gb>0 AND r.is_active=1 AND r.expires_at > NOW()
        GROUP BY r.id
        HAVING total_bytes >= (r.data_limit_gb * 1073741824);")

    [[ $r_blocked -gt 0 ]] && echo "[$(TS)] [QUOTA] $r_blocked revendeur(s) bloque(s)" >> "$LOG_FILE"
}

check_quota

# ==========================================
# 1. Nettoyage V2Ray
# ==========================================
USER_DB="/etc/v2ray/utilisateurs.json"
CONFIG="/etc/v2ray/config.json"

if [[ -f "$USER_DB" && -f "$CONFIG" ]]; then
    echo "[$(TS)] Nettoyage V2Ray expires" >> "$LOG_FILE"
    uuids_expire=$(jq -r --arg today "$TODAY" '.[] | select(.expire < $today) | .uuid' "$USER_DB")
    if [[ -n "$(echo "$uuids_expire" | tr -d '[:space:]')" ]]; then
        tmpfile=$(mktemp)
        jq --argjson uuids "$(echo "$uuids_expire" | jq -R -s -c 'split("\n")[:-1]')" '
        .inbounds |= map(if .protocol=="vless" then
            .settings.clients |= map(select(.id as $id | $uuids | index($id) | not))
        else . end)' "$CONFIG" > "$tmpfile" && mv "$tmpfile" "$CONFIG"
        jq --arg today "$TODAY" '[.[] | select(.expire >= $today)]' "$USER_DB" > "$USER_DB.tmp" \
            && mv "$USER_DB.tmp" "$USER_DB"
        systemctl restart v2ray
        echo "[$(TS)] V2Ray nettoye et redemarre" >> "$LOG_FILE"
    else
        echo "[$(TS)] Aucun V2Ray expire" >> "$LOG_FILE"
    fi
else
    echo "[$(TS)] Fichiers V2Ray introuvables, ignore" >> "$LOG_FILE"
fi

# ==========================================
# 2. Nettoyage ZIVPN
# ==========================================
clean_zivpn_users() {
    local ZIVPN_USER_FILE="/etc/zivpn/users.list"
    local ZIVPN_CONFIG="/etc/zivpn/config.json"
    [[ ! -f "$ZIVPN_USER_FILE" || ! -f "$ZIVPN_CONFIG" ]] && return
    echo "[$(TS)] Nettoyage ZIVPN expires" >> "$LOG_FILE"
    local NUM_BEFORE; NUM_BEFORE=$(wc -l < "$ZIVPN_USER_FILE")
    local TMP_FILE; TMP_FILE=$(mktemp)
    awk -F'|' -v today="$TODAY" '$3>=today {print $0}' "$ZIVPN_USER_FILE" > "$TMP_FILE" || true
    mv "$TMP_FILE" "$ZIVPN_USER_FILE"
    chmod 600 "$ZIVPN_USER_FILE"
    local PASSWORDS; PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" | sort -u | paste -sd, -)
    local tmp; tmp=$(mktemp)
    if jq --arg p "$PASSWORDS" '.auth.config=($p|split(","))' "$ZIVPN_CONFIG" > "$tmp" 2>/dev/null \
        && jq empty "$tmp" >/dev/null 2>&1; then
        mv "$tmp" "$ZIVPN_CONFIG"
        local NUM_AFTER; NUM_AFTER=$(wc -l < "$ZIVPN_USER_FILE")
        [[ "$NUM_AFTER" -lt "$NUM_BEFORE" ]] && systemctl restart zivpn
        echo "[$(TS)] ZIVPN nettoye" >> "$LOG_FILE"
    else
        echo "[$(TS)] Erreur JSON ZIVPN" >> "$LOG_FILE"; rm -f "$tmp"
    fi
}

# ==========================================
# 3. Nettoyage Xray
# ==========================================
clean_xray_users() {
    local XRAY_USERS="/etc/xray/users.json"
    local XRAY_CONFIG="/etc/xray/config.json"
    local XRAY_EXPIRY="/etc/xray/users_expiry.list"
    [[ ! -f "$XRAY_USERS" || ! -f "$XRAY_CONFIG" ]] && return
    echo "[$(TS)] Nettoyage Xray expires" >> "$LOG_FILE"
    local expired_vmess expired_vless expired_trojan
    expired_vmess=$(jq  -r --arg t "$TODAY" '.vmess[]?  | select(.expire < $t) | .uuid'     "$XRAY_USERS")
    expired_vless=$(jq  -r --arg t "$TODAY" '.vless[]?  | select(.expire < $t) | .uuid'     "$XRAY_USERS")
    expired_trojan=$(jq -r --arg t "$TODAY" '.trojan[]? | select(.expire < $t) | .password' "$XRAY_USERS")
    if [[ -z "$expired_vmess$expired_vless$expired_trojan" ]]; then
        echo "[$(TS)] Aucun Xray expire" >> "$LOG_FILE"; return
    fi
    local tmp_c; tmp_c=$(mktemp)
    local tmp_u; tmp_u=$(mktemp)
    jq --argjson ids "$(printf '%s\n%s\n' "$expired_vmess" "$expired_vless" | jq -R -s -c 'split("\n")[:-1]')" \
       --argjson pw  "$(printf '%s\n' "$expired_trojan" | jq -R -s -c 'split("\n")[:-1]')" '
    .inbounds |= map(
        if .protocol=="vmess" or .protocol=="vless" then
            .settings.clients |= map(select(.id as $id | $ids | index($id) | not))
        elif .protocol=="trojan" then
            .settings.clients |= map(select(.password as $p | $pw | index($p) | not))
        else . end)' "$XRAY_CONFIG" > "$tmp_c" && mv "$tmp_c" "$XRAY_CONFIG"
    jq --arg t "$TODAY" '
        .vmess  |= map(select(.expire >= $t)) |
        .vless  |= map(select(.expire >= $t)) |
        .trojan |= map(select(.expire >= $t))' "$XRAY_USERS" > "$tmp_u" && mv "$tmp_u" "$XRAY_USERS"
    [[ -f "$XRAY_EXPIRY" ]] && sed -i "/|$TODAY/d" "$XRAY_EXPIRY"
    systemctl restart xray
    echo "[$(TS)] Xray nettoye et redemarre" >> "$LOG_FILE"
}

# ==========================================
# 4. Nettoyage Hysteria
# ==========================================
clean_hysteria_users() {
    local HYSTERIA_USER_FILE="/etc/hysteria/users.txt"
    local HYSTERIA_CONFIG="/etc/hysteria/config.json"
    echo "[$(TS)] Nettoyage Hysteria" >> "$LOG_FILE"
    [[ ! -f "$HYSTERIA_USER_FILE" ]] && { echo "[$(TS)] users.txt Hysteria introuvable" >> "$LOG_FILE"; return; }
    local NUM_BEFORE; NUM_BEFORE=$(wc -l < "$HYSTERIA_USER_FILE")
    local EXPIRED; EXPIRED=$(awk -F'|' -v today="$TODAY" '$3<today {print $0}' "$HYSTERIA_USER_FILE")
    if [[ -z "$EXPIRED" ]]; then
        echo "[$(TS)] Aucun Hysteria expire" >> "$LOG_FILE"; return
    fi
    while IFS='|' read -r user _pass expire; do
        echo "[$(TS)] Supprime Hysteria: $user (expire=$expire)" >> "$LOG_FILE"
    done <<< "$EXPIRED"
    awk -F'|' -v today="$TODAY" '$3>=today' "$HYSTERIA_USER_FILE" > "$HYSTERIA_USER_FILE.tmp"
    mv "$HYSTERIA_USER_FILE.tmp" "$HYSTERIA_USER_FILE"
    chmod 600 "$HYSTERIA_USER_FILE"
    local PASSWORDS; PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$HYSTERIA_USER_FILE" | sort -u | paste -sd, -)
    local tmp; tmp=$(mktemp)
    if jq --arg p "$PASSWORDS" '.auth.config=($p|split(","))' "$HYSTERIA_CONFIG" > "$tmp" \
        && jq empty "$tmp" >/dev/null 2>&1; then
        mv "$tmp" "$HYSTERIA_CONFIG"
        local NUM_AFTER; NUM_AFTER=$(wc -l < "$HYSTERIA_USER_FILE")
        [[ "$NUM_AFTER" -lt "$NUM_BEFORE" ]] && systemctl restart hysteria
        echo "[$(TS)] Hysteria nettoye et redemarre" >> "$LOG_FILE"
    else
        echo "[$(TS)] Erreur JSON Hysteria, config inchangee" >> "$LOG_FILE"; rm -f "$tmp"
    fi
}

# ==========================================
# Appel des nettoyages expiration
# ==========================================
clean_zivpn_users
clean_xray_users
clean_hysteria_users

echo "[$(TS)] Termine" >> "$LOG_FILE"
echo "[$(TS)] ============================================" >> "$LOG_FILE"
