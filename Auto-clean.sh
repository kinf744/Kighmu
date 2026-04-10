#!/bin/bash
# ==========================================
# Auto-clean + collecte trafic + quota data
# V2Ray, ZIVPN, Xray, Hysteria & SSH
# ==========================================
set -euo pipefail

LOG_FILE="/var/log/auto-clean.log"
TODAY=$(date +%Y-%m-%d)
TS() { date '+%Y-%m-%d %H:%M:%S'; }

# ── Config panel (lu depuis .env) ────────────────────────────
PANEL_ENV="/opt/kighmu-panel/.env"
PANEL_URL="http://127.0.0.1:3000"
REPORT_SECRET="kighmu-report-2024"
if [[ -f "$PANEL_ENV" ]]; then
    _p=$(grep '^PORT='           "$PANEL_ENV" 2>/dev/null | cut -d= -f2 | tr -d '"' || true)
    _s=$(grep '^REPORT_SECRET=' "$PANEL_ENV" 2>/dev/null | cut -d= -f2 | tr -d '"' || true)
    [[ -n "$_p" ]] && PANEL_URL="http://127.0.0.1:${_p}"
    [[ -n "$_s" ]] && REPORT_SECRET="$_s"
fi

# Si REPORT_SECRET toujours vide, lire depuis traffic-collect.sh
if [[ "$REPORT_SECRET" == "kighmu-report-2024" ]]; then
    _tc="/etc/kighmu/traffic-collect.sh"
    if [[ -f "$_tc" ]]; then
        _s2=$(grep '^SECRET=' "$_tc" 2>/dev/null | cut -d'"' -f2 || true)
        [[ -n "$_s2" ]] && REPORT_SECRET="$_s2"
    fi
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

# ============================================================
# VARIABLES GLOBALES SSH
# ============================================================
BW_DIR="/var/lib/kighmu/bandwidth"
USER_FILE="/etc/kighmu/users.list"
mkdir -p "$BW_DIR"

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

# ── 0a. Xray — commande : xray api statsquery ────────────────
# Format de sortie Xray 26.x : JSON
# {
#   "stat": [
#     { "name": "user>>>kighmu49>>>traffic>>>uplink", "value": "12345" },
#     { "name": "user>>>kighmu49>>>traffic>>>downlink", "value": "67890" }
#   ]
# }
# NOTE : les clients sans email ou avec email "default" ne génèrent
# pas de stats par user — il faut que chaque client ait un email = username.
collect_xray_traffic() {
    local bin="${XRAY_BIN:-/usr/local/bin/xray}"
    local api="${XRAY_API:-127.0.0.1:10085}"
    [[ ! -x "$bin" ]] && return
    command -v jq &>/dev/null || {
        echo "[$(TS)] [XRAY] jq absent — impossible de parser les stats" >> "$LOG_FILE"
        return
    }

    local raw
    # --reset : remet les compteurs à 0 après lecture (évite le double-comptage)
    raw=$("$bin" api statsquery --server="$api" --reset 2>/dev/null) || return
    [[ -z "$raw" ]] && { echo "[$(TS)] [XRAY] Aucune stat" >> "$LOG_FILE"; return; }

    # Parser le JSON avec jq : extraire uniquement les stats "user>>>"
    # Ignorer "default" (client pré-installé sans username réel)
    declare -A up_map=()
    declare -A down_map=()

    while IFS='|' read -r name value; do
        [[ -z "$name" ]] && continue  # ne pas skipper value=0
        # Format name: "user>>>TAG>>>traffic>>>uplink"
        if [[ "$name" =~ ^user\>\>\>([^\>]+)\>\>\>traffic\>\>\>(up|down)link$ ]]; then
            local tag="${BASH_REMATCH[1]}" dir="${BASH_REMATCH[2]}"
            [[ "$tag" == "default" ]] && continue
            # Extraire le username depuis le tag (format: proto_username_uuid8)
            # ex: vless_89uuo_da5bae66 → 89uuo
            local user
            if [[ "$tag" =~ ^[a-z]+_(.+)_[0-9a-f]{8}$ ]]; then
                user="${BASH_REMATCH[1]}"
            else
                user="$tag"  # fallback: utiliser le tag complet
            fi
            local val="${value:-0}"
            [[ "$dir" == "up"   ]] && up_map["$user"]=$(( ${up_map["$user"]:-0}   + val ))
            [[ "$dir" == "down" ]] && down_map["$user"]=$(( ${down_map["$user"]:-0} + val ))
        fi
    done < <(echo "$raw" | jq -r '.stat[]? | select(.name != null) | "\(.name)|\(.value // "0")"' 2>/dev/null)

    local json='{"stats":[' first=1
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
        echo "[$(TS)] [XRAY] Aucun trafic user (vérifiez que les clients ont un email=username)" >> "$LOG_FILE"
    fi
}

# ── 0b. V2Ray — commande : v2ray api stats ───────────────────
# Format de sortie V2Ray 5.x (tableau texte) :
#   IDX   SIZE    NAME
#   3   262.93KB  inbound>>>ssh>>>traffic>>>downlink
#   4   108.65KB  inbound>>>ssh>>>traffic>>>uplink
#
# Le trafic SSH passe entièrement par V2Ray (dokodemo-door port 5401→22).
# Comme V2Ray ne connaît pas les usernames SSH individuels (dokodemo-door
# ne fait pas d'authentification), on répartit le trafic de l'inbound "ssh"
# équitablement entre tous les users SSH actifs connectés via ce tunnel.
# Pour vless-fastdns, les stats sont par user (email dans les clients).
collect_v2ray_traffic() {
    local bin="${V2RAY_BIN:-/usr/local/bin/v2ray}"
    local api="${V2RAY_API:-127.0.0.1:10086}"
    [[ ! -x "$bin" ]] && return
    # Vérifier que l'API répond
    ss -tnlp 2>/dev/null | grep -q "${api##*:}" || {
        echo "[$(TS)] [V2RAY] API non disponible sur $api" >> "$LOG_FILE"
        return
    }

    local raw
    # -reset : remet les compteurs à 0 après lecture
    raw=$("$bin" api stats --server="$api" -reset 2>/dev/null) || return
    [[ -z "$raw" ]] && { echo "[$(TS)] [V2RAY] Aucune stat" >> "$LOG_FILE"; return; }

    # Parser le format texte : "IDX  SIZE  NAME"
    # Convertir les tailles en bytes (B, KB, MB, GB)
    to_bytes() {
        local val="$1"
        # Format: "262.93KB" ou "108.65KB" ou "54.00B" ou "1.23MB"
        if [[ "$val" =~ ^([0-9]+\.?[0-9]*)([KMGT]?B)$ ]]; then
            local num="${BASH_REMATCH[1]}" unit="${BASH_REMATCH[2]}"
            case "$unit" in
                B)  awk "BEGIN {printf \"%d\", $num}" ;;
                KB) awk "BEGIN {printf \"%d\", $num * 1024}" ;;
                MB) awk "BEGIN {printf \"%d\", $num * 1048576}" ;;
                GB) awk "BEGIN {printf \"%d\", $num * 1073741824}" ;;
                *)  echo "0" ;;
            esac
        else
            echo "0"
        fi
    }

    # Accumuler trafic SSH inbound (tous users confondus)
    local ssh_down=0 ssh_up=0
    # Accumuler trafic vless par user (email)
    declare -A up_map=()
    declare -A down_map=()

    while IFS= read -r line; do
        # Format: "  3   262.93KB    inbound>>>ssh>>>traffic>>>downlink"
        if [[ "$line" =~ ^[[:space:]]*[0-9]+[[:space:]]+([0-9]+\.?[0-9]*[KMGT]?B)[[:space:]]+(.*) ]]; then
            local size_str="${BASH_REMATCH[1]}" name="${BASH_REMATCH[2]}"
            local bytes; bytes=$(to_bytes "$size_str")

            # SSH inbound (dokodemo-door)
            if [[ "$name" == "inbound>>>ssh>>>traffic>>>downlink" ]]; then
                ssh_down=$bytes
            elif [[ "$name" == "inbound>>>ssh>>>traffic>>>uplink" ]]; then
                ssh_up=$bytes
            # Vless par user : "user>>>USERNAME>>>traffic>>>uplink"
            elif [[ "$name" =~ user\>\>\>([^\>]+)\>\>\>traffic\>\>\>(up|down)link ]]; then
                local user="${BASH_REMATCH[1]}" dir="${BASH_REMATCH[2]}"
                [[ "$dir" == "up"   ]] && up_map["$user"]=$(( ${up_map["$user"]:-0}   + bytes ))
                [[ "$dir" == "down" ]] && down_map["$user"]=$(( ${down_map["$user"]:-0} + bytes ))
            fi
        fi
    done <<< "$raw"

    local json='{"stats":[' first=1

    # Trafic SSH inbound (dokodemo-door 127.0.0.1→port 22)
    # Méthode : auth.log donne PID→username pour chaque "Accepted password from 127.0.0.1"
    # Les PIDs actifs dans ss sont les enfants (PPid) des PIDs auth.log
    if (( ssh_up + ssh_down > 0 )); then
        declare -A sess_count=()

        # Construire map pid_parent→username depuis auth.log (dernières 24h)
        declare -A pid_user_map=()
        while IFS= read -r line; do
            # Format: "... sshd[PID]: Accepted password for USERNAME from 127.0.0.1 ..."
            if [[ "$line" =~ sshd\[([0-9]+)\]:.*Accepted\ password\ for\ ([^[:space:]]+)\ from\ 127\.0\.0\.1 ]]; then
                local apid="${BASH_REMATCH[1]}" auser="${BASH_REMATCH[2]}"
                [[ "$auser" == "root" ]] && continue
                # Vérifier que c'est un user VPN connu
                [[ -f "$USER_FILE" ]] && \
                    grep -q "^${auser}|" "$USER_FILE" 2>/dev/null || continue
                pid_user_map["$apid"]="$auser"
            fi
        done < <(grep "Accepted password" /var/log/auth.log 2>/dev/null | grep "127.0.0.1" | tail -500)

        # Pour chaque connexion SSH active, remonter au PID auth.log via PPid
        while IFS= read -r line; do
            # ss output: "... users:(("sshd",pid=XXXX,fd=Y),("sshd",pid=YYYY,fd=Z))"
            while [[ "$line" =~ pid=([0-9]+) ]]; do
                local cpid="${BASH_REMATCH[1]}"
                line="${line#*pid=${cpid}}"
                # Lire le PPid de ce processus
                local ppid
                ppid=$(awk '/^PPid:/{print $2}' "/proc/$cpid/status" 2>/dev/null)
                [[ -z "$ppid" ]] && continue
                # Chercher le username dans la map (pid direct ou parent)
                local found_user=""
                [[ -n "${pid_user_map[$cpid]:-}" ]] && found_user="${pid_user_map[$cpid]}"
                [[ -z "$found_user" && -n "${pid_user_map[$ppid]:-}" ]] && found_user="${pid_user_map[$ppid]}"
                [[ -z "$found_user" ]] && continue
                sess_count["$found_user"]=$(( ${sess_count["$found_user"]:-0} + 1 ))
            done
        done < <(ss -tnp state established 2>/dev/null | grep ":22 ")

        # Dédupliquer : compter 1 session par PID parent unique par user
        # (ss liste 2 PIDs par connexion : parent+enfant)
        declare -A seen_pairs=()
        declare -A sess_dedup=()
        while IFS= read -r line; do
            local pids=()
            local tmp="$line"
            while [[ "$tmp" =~ pid=([0-9]+) ]]; do
                pids+=("${BASH_REMATCH[1]}")
                tmp="${tmp#*pid=${BASH_REMATCH[1]}}"
            done
            # Trouver le user associé à cette connexion
            local conn_user=""
            for p in "${pids[@]}"; do
                local pp; pp=$(awk '/^PPid:/{print $2}' "/proc/$p/status" 2>/dev/null)
                [[ -n "${pid_user_map[$p]:-}" ]]  && { conn_user="${pid_user_map[$p]}";  break; }
                [[ -n "${pid_user_map[$pp]:-}" ]] && { conn_user="${pid_user_map[$pp]}"; break; }
            done
            [[ -z "$conn_user" ]] && continue
            # Clé unique = PIDs triés pour éviter le double comptage
            local key; key=$(printf '%s\n' "${pids[@]}" | sort | tr '\n' '_')
            [[ -n "${seen_pairs[$key]:-}" ]] && continue
            seen_pairs["$key"]=1
            sess_dedup["$conn_user"]=$(( ${sess_dedup["$conn_user"]:-0} + 1 ))
        done < <(ss -tnp state established 2>/dev/null | grep ":22 ")

        local total_sess=0
        for u in "${!sess_dedup[@]}"; do
            total_sess=$(( total_sess + sess_dedup[$u] ))
        done

        if (( total_sess > 0 )); then
            echo "[$(TS)] [V2RAY] SSH inbound ↑${ssh_up}B ↓${ssh_down}B → réparti par sessions (total=${total_sess})" >> "$LOG_FILE"
            for uname in "${!sess_dedup[@]}"; do
                local weight="${sess_dedup[$uname]}"
                local u_up=$(( ssh_up   * weight / total_sess ))
                local u_dn=$(( ssh_down * weight / total_sess ))
                (( u_up + u_dn == 0 )) && continue
                [[ $first -eq 0 ]] && json+=","
                json+="{\"username\":\"${uname}\",\"upload_bytes\":${u_up},\"download_bytes\":${u_dn}}"
                echo "[$(TS)] [V2RAY]   $uname : ${weight} session(s) → ↑${u_up}B ↓${u_dn}B" >> "$LOG_FILE"
                first=0
            done
        else
            # Fallback : répartition égale sur tous les users connus
            local ssh_users=()
            while IFS='|' read -r username _rest; do
                [[ -z "$username" ]] && continue
                id "$username" &>/dev/null && ssh_users+=("$username")
            done < "$USER_FILE"
            local nb_users=${#ssh_users[@]}
            if (( nb_users > 0 )); then
                local share_up=$(( ssh_up   / nb_users ))
                local share_dn=$(( ssh_down / nb_users ))
                echo "[$(TS)] [V2RAY] SSH inbound — aucune session identifiée, répartition égale sur $nb_users user(s)" >> "$LOG_FILE"
                for uname in "${ssh_users[@]}"; do
                    [[ $first -eq 0 ]] && json+=","
                    json+="{\"username\":\"${uname}\",\"upload_bytes\":${share_up},\"download_bytes\":${share_dn}}"
                    first=0
                done
            fi
        fi
    fi

    # Trafic vless par user
    for user in $(echo "${!up_map[@]} ${!down_map[@]}" | tr ' ' '\n' | sort -u); do
        local up="${up_map[$user]:-0}" dn="${down_map[$user]:-0}"
        (( up + dn == 0 )) && continue
        [[ $first -eq 0 ]] && json+=","
        json+="{\"username\":\"$user\",\"upload_bytes\":$up,\"download_bytes\":$dn}"
        first=0
    done
    json+="]}"

    if [[ $first -eq 0 ]]; then
        echo "[$(TS)] [V2RAY] Envoi stats..." >> "$LOG_FILE"
        send_stats "$json"
    else
        echo "[$(TS)] [V2RAY] Aucun trafic" >> "$LOG_FILE"
    fi
}

# ── 0c. SSH : lecture des cumuls depuis le service kighmu-bandwidth ─────────
# Le service kighmu-bandwidth.sh accumule en temps réel dans BW_DIR/username.usage
# auto-clean.sh lit uniquement le delta depuis le dernier envoi et l'envoie au panel
collect_ssh_traffic() {
    local USER_FILE="/etc/kighmu/users.list"
    local BW_DIR="/var/lib/kighmu/bandwidth"
    local SENT_DIR="$BW_DIR/sent"
    [[ ! -f "$USER_FILE" ]] && return
    mkdir -p "$SENT_DIR"

    local json='{"stats":[' first=1 has_data=0

    while IFS='|' read -r username _rest; do
        [[ -z "$username" ]] && continue

        local usagefile="$BW_DIR/${username}.usage"
        [[ ! -f "$usagefile" ]] && continue

        local accumulated
        accumulated=$(cat "$usagefile" 2>/dev/null)
        [[ ! "$accumulated" =~ ^[0-9]+$ ]] && continue
        (( accumulated == 0 )) && continue

        # Lire la dernière valeur envoyée au panel
        local sentfile="$SENT_DIR/${username}.sent"
        local last_sent=0
        [[ -f "$sentfile" ]] && last_sent=$(cat "$sentfile" 2>/dev/null)
        [[ ! "$last_sent" =~ ^[0-9]+$ ]] && last_sent=0

        # Delta depuis le dernier envoi
        local delta=$(( accumulated - last_sent ))
        (( delta <= 0 )) && continue

        # Sauvegarder la valeur envoyée
        echo "$accumulated" > "$sentfile"

        local half=$(( delta / 2 ))
        local other=$(( delta - half ))

        [[ $first -eq 0 ]] && json+=","
        json+="{\"username\":\"${username}\",\"upload_bytes\":${half},\"download_bytes\":${other}}"
        first=0
        has_data=1
        echo "[$(TS)] [SSH] $username +$(( delta / 1048576 ))MB (cumul: $(( accumulated / 1048576 ))MB)" >> "$LOG_FILE"
    done < "$USER_FILE"

    json+="]}"
    if [[ $has_data -eq 1 ]]; then
        echo "[$(TS)] [SSH] Envoi stats..." >> "$LOG_FILE"
        send_stats "$json"
    else
        echo "[$(TS)] [SSH] Aucun nouveau trafic SSH" >> "$LOG_FILE"
    fi
}

# ── 0d. UDP Zivpn + Hysteria : comptage INDIVIDUEL par user ──────────────────
# PROBLÈMES CORRIGÉS vs ancienne version :
#   1. SUPPRESSION du comptage global par port (--dport 20000:50000) qui captait
#      TOUT le trafic UDP du serveur et le répartissait sur tous les users.
#   2. SUPPRESSION du "rattrapage automatique" (recovery/gap) qui injectait des
#      dizaines de Go fictifs dès qu'un fichier .sent était absent ou décalé.
#   3. SUPPRESSION de la distribution équitable sur tous les users non-expirés :
#      un user qui consomme ne doit JAMAIS faire gonfler les autres.
#
# NOUVELLE LOGIQUE :
#   Priorité 1 : logs NATIFS du service (bytes réels par user à la déconnexion)
#   Priorité 2 : iptables par IP SOURCE individuelle (uniquement sessions actives)
#   Dans tous les cas : si le user ne peut pas être identifié → trafic ignoré.
# ─────────────────────────────────────────────────────────────────────────────

init_udp_per_ip_chain() {
    iptables -N KIGHMU_UDP_PER_IP 2>/dev/null || true
    iptables -C INPUT  -j KIGHMU_UDP_PER_IP 2>/dev/null || iptables -I INPUT  1 -j KIGHMU_UDP_PER_IP 2>/dev/null || true
    iptables -C OUTPUT -j KIGHMU_UDP_PER_IP 2>/dev/null || iptables -I OUTPUT 1 -j KIGHMU_UDP_PER_IP 2>/dev/null || true
}

_ensure_iptables_rule_for_ip() {
    local ip="$1" port="$2" chain="$3"
    iptables -C "$chain" -p udp -s "$ip" --dport "$port" 2>/dev/null || \
        iptables -A "$chain" -p udp -s "$ip" --dport "$port" 2>/dev/null || true
    iptables -C "$chain" -p udp -d "$ip" --sport "$port" 2>/dev/null || \
        iptables -A "$chain" -p udp -d "$ip" --sport "$port" 2>/dev/null || true
}

# ─── Collecte trafic Hysteria ────────────────────────────────────────────────
collect_hysteria_traffic() {
    local BW_DIR="/var/lib/kighmu/bandwidth"
    local SNAP_NATIVE="$BW_DIR/hy_native"
    local SNAP_IPTA="$BW_DIR/hy_ipta"
    local hy_uf="/etc/hysteria/users.txt"
    mkdir -p "$SNAP_NATIVE" "$SNAP_IPTA"
    [[ ! -f "$hy_uf" ]] && return

    local json='{"stats":[' first=1 has_data=0

    # Lire port hysteria
    local hy_port="20000"
    if [[ -f /etc/hysteria/config.json ]]; then
        local _hp; _hp=$(python3 -c "
import json,sys
try:
    d=json.load(open('/etc/hysteria/config.json'))
    p=d.get('listen',':20000').lstrip(':')
    print(p if p.isdigit() else '20000')
except: print('20000')
" 2>/dev/null)
        [[ "$_hp" =~ ^[0-9]+$ ]] && hy_port="$_hp"
    fi

    # ── Méthode 1 : logs natifs Hysteria2 (bytes réels par user) ─────────────
    # Hysteria2 log format JSON: {"msg":"client disconnected","auth":"USER","tx":N,"rx":N}
    # tx = serveur→client (download), rx = client→serveur (upload)
    declare -A hy_native_up=() hy_native_dn=()
    local hy_log=""
    for lpath in /var/log/hysteria.log /var/log/hysteria2.log; do
        [[ -f "$lpath" ]] && { hy_log="$lpath"; break; }
    done

    _parse_hy_disconnects() {
        local src="$1"
        while IFS= read -r line; do
            local user tx rx
            user=$(echo "$line" | grep -oP '(?<="auth":")[^"]+' 2>/dev/null || true)
            tx=$(echo   "$line" | grep -oP '(?<="tx":)[0-9]+'   2>/dev/null || true)
            rx=$(echo   "$line" | grep -oP '(?<="rx":)[0-9]+'   2>/dev/null || true)
            [[ -z "$user" ]] && continue
            hy_native_up["$user"]=$(( ${hy_native_up["$user"]:-0} + ${rx:-0} ))
            hy_native_dn["$user"]=$(( ${hy_native_dn["$user"]:-0} + ${tx:-0} ))
        done < <(grep -a '"disconnected"' "$src" 2>/dev/null | tail -20000)
    }

    if [[ -n "$hy_log" ]]; then
        _parse_hy_disconnects "$hy_log"
        echo "[$(TS)] [UDP-hysteria] Log natif : $hy_log" >> "$LOG_FILE"
    else
        # Fallback journalctl
        local tmp_jlog; tmp_jlog=$(mktemp)
        journalctl -u hysteria -u hysteria2 --no-pager -n 20000 2>/dev/null \
            | grep 'disconnected' > "$tmp_jlog" || true
        [[ -s "$tmp_jlog" ]] && _parse_hy_disconnects "$tmp_jlog"
        rm -f "$tmp_jlog"
        echo "[$(TS)] [UDP-hysteria] Log natif via journalctl" >> "$LOG_FILE"
    fi

    if [[ ${#hy_native_up[@]} -gt 0 ]]; then
        # Calculer delta (cumul log - dernier snapshot) pour chaque user
        for user in "${!hy_native_up[@]}"; do
            local snap_up="$SNAP_NATIVE/${user}.up" snap_dn="$SNAP_NATIVE/${user}.dn"
            local prev_up=0 prev_dn=0
            [[ -f "$snap_up" ]] && prev_up=$(cat "$snap_up" 2>/dev/null)
            [[ -f "$snap_dn" ]] && prev_dn=$(cat "$snap_dn" 2>/dev/null)
            [[ ! "$prev_up" =~ ^[0-9]+$ ]] && prev_up=0
            [[ ! "$prev_dn" =~ ^[0-9]+$ ]] && prev_dn=0
            local cur_up="${hy_native_up[$user]}" cur_dn="${hy_native_dn[$user]}"
            local dlt_up=$(( cur_up > prev_up ? cur_up - prev_up : 0 ))
            local dlt_dn=$(( cur_dn > prev_dn ? cur_dn - prev_dn : 0 ))
            (( dlt_up + dlt_dn == 0 )) && continue
            # Ignorer les users qui ne sont plus dans users.txt (supprimés)
            grep -q "^${user}|" "$hy_uf" 2>/dev/null || continue
            echo "$cur_up" > "$snap_up"
            echo "$cur_dn" > "$snap_dn"
            [[ $first -eq 0 ]] && json+=","
            json+="{\"username\":\"${user}\",\"upload_bytes\":${dlt_up},\"download_bytes\":${dlt_dn}}"
            first=0; has_data=1
            echo "[$(TS)] [UDP-hysteria] [NATIF] $user ↑$(( dlt_up/1048576 ))MB ↓$(( dlt_dn/1048576 ))MB" >> "$LOG_FILE"
        done
    else
        # ── Méthode 2 : iptables par IP — uniquement sessions UDP ACTIVES ────
        echo "[$(TS)] [UDP-hysteria] Aucun log natif — fallback iptables/IP active" >> "$LOG_FILE"
        init_udp_per_ip_chain

        # Détecter les IPs sources ayant des sockets UDP établies sur le port hysteria
        local active_ips=()
        while IFS= read -r ip; do
            [[ -z "$ip" || "$ip" == "127.0.0.1" || "$ip" == "::1" ]] && continue
            active_ips+=("$ip")
        done < <(ss -u -a -n 2>/dev/null | awk -v p=":${hy_port}" '
            $1=="ESTAB" && ($5 ~ p || $4 ~ p) {
                split($4=="*" ? $5 : $4, a, ":")
                if (a[1]!="" && a[1]!="*") print a[1]
            }' | sort -u)

        if [[ ${#active_ips[@]} -eq 0 ]]; then
            echo "[$(TS)] [UDP-hysteria] Aucune session active — trafic non comptabilisé" >> "$LOG_FILE"
        else
            echo "[$(TS)] [UDP-hysteria] ${#active_ips[@]} IP(s) active(s) sur port ${hy_port}" >> "$LOG_FILE"

            # Construire map IP→user depuis les logs de connexion (pas déconnexion)
            declare -A hy_ip_user=()
            local log_src="${hy_log}"
            if [[ -z "$log_src" ]]; then
                log_src=$(mktemp)
                journalctl -u hysteria -u hysteria2 --no-pager -n 5000 2>/dev/null \
                    | grep 'connected' > "$log_src" || true
            fi
            if [[ -f "$log_src" && -s "$log_src" ]]; then
                while IFS= read -r line; do
                    local user ip_raw
                    user=$(echo   "$line" | grep -oP '(?<="auth":")[^"]+' 2>/dev/null || true)
                    ip_raw=$(echo "$line" | grep -oP '(?<="addr":")[^"]+' 2>/dev/null || true)
                    [[ -z "$user" || -z "$ip_raw" ]] && continue
                    hy_ip_user["${ip_raw%:*}"]="$user"
                done < <(grep -a '"connected"' "$log_src" 2>/dev/null | tail -5000)
            fi

            declare -A hy_user_up=() hy_user_dn=()
            for ip in "${active_ips[@]}"; do
                _ensure_iptables_rule_for_ip "$ip" "$hy_port" "KIGHMU_UDP_PER_IP"
                local snap_up_f="$SNAP_IPTA/${ip//./_}.up"
                local snap_dn_f="$SNAP_IPTA/${ip//./_}.dn"
                local raw_up raw_dn
                raw_up=$(iptables -nvx -L KIGHMU_UDP_PER_IP 2>/dev/null | \
                    awk -v ip="$ip" -v p="$hy_port" '$8==ip && $10~"dpt:"p {sum+=$2} END{print sum+0}')
                raw_dn=$(iptables -nvx -L KIGHMU_UDP_PER_IP 2>/dev/null | \
                    awk -v ip="$ip" -v p="$hy_port" '$9==ip && $10~"spt:"p {sum+=$2} END{print sum+0}')
                local prev_up=0 prev_dn=0
                [[ -f "$snap_up_f" ]] && prev_up=$(cat "$snap_up_f" 2>/dev/null)
                [[ -f "$snap_dn_f" ]] && prev_dn=$(cat "$snap_dn_f" 2>/dev/null)
                [[ ! "$prev_up" =~ ^[0-9]+$ ]] && prev_up=0
                [[ ! "$prev_dn" =~ ^[0-9]+$ ]] && prev_dn=0
                local dlt_up=$(( raw_up > prev_up ? raw_up - prev_up : 0 ))
                local dlt_dn=$(( raw_dn > prev_dn ? raw_dn - prev_dn : 0 ))
                (( dlt_up + dlt_dn == 0 )) && continue
                echo "$raw_up" > "$snap_up_f"
                echo "$raw_dn" > "$snap_dn_f"
                local uname="${hy_ip_user[$ip]:-}"
                if [[ -z "$uname" ]]; then
                    echo "[$(TS)] [UDP-hysteria] IP $ip non identifiée — $(( (dlt_up+dlt_dn)/1048576 ))MB ignorés" >> "$LOG_FILE"
                    continue
                fi
                hy_user_up["$uname"]=$(( ${hy_user_up["$uname"]:-0} + dlt_up ))
                hy_user_dn["$uname"]=$(( ${hy_user_dn["$uname"]:-0} + dlt_dn ))
            done

            for uname in "${!hy_user_up[@]}"; do
                local du="${hy_user_up[$uname]}" dd="${hy_user_dn[$uname]}"
                (( du + dd == 0 )) && continue
                [[ $first -eq 0 ]] && json+=","
                json+="{\"username\":\"${uname}\",\"upload_bytes\":${du},\"download_bytes\":${dd}}"
                first=0; has_data=1
                echo "[$(TS)] [UDP-hysteria] [IPTA] $uname ↑$(( du/1048576 ))MB ↓$(( dd/1048576 ))MB" >> "$LOG_FILE"
            done
        fi
    fi

    json+="]}"
    if [[ $has_data -eq 1 ]]; then
        echo "[$(TS)] [UDP-hysteria] Envoi stats panel..." >> "$LOG_FILE"
        send_stats "$json"
    else
        echo "[$(TS)] [UDP-hysteria] Aucun nouveau trafic" >> "$LOG_FILE"
    fi
}

# ─── Collecte trafic Zivpn ───────────────────────────────────────────────────
collect_zivpn_traffic() {
    local BW_DIR="/var/lib/kighmu/bandwidth"
    local SNAP_NATIVE="$BW_DIR/zi_native"
    local SNAP_IPTA="$BW_DIR/zi_ipta"
    local zi_uf="/etc/zivpn/users.list"
    mkdir -p "$SNAP_NATIVE" "$SNAP_IPTA"
    [[ ! -f "$zi_uf" ]] && return

    local json='{"stats":[' first=1 has_data=0

    # Lire le port ZIVPN
    local zi_port="5667"
    if [[ -f /etc/zivpn/config.json ]]; then
        local _zp; _zp=$(python3 -c "
import json,sys
try:
    d=json.load(open('/etc/zivpn/config.json'))
    p=d.get('listen',':5667').lstrip(':')
    print(p if p.isdigit() else '5667')
except: print('5667')
" 2>/dev/null)
        [[ "$_zp" =~ ^[0-9]+$ ]] && zi_port="$_zp"
    fi

    # ── Méthode 1 : logs natifs Zivpn ────────────────────────────────────────
    declare -A zi_native_up=() zi_native_dn=()
    local zi_log=""
    for lpath in /var/log/zivpn.log /var/log/zivpn/access.log; do
        [[ -f "$lpath" ]] && { zi_log="$lpath"; break; }
    done

    if [[ -n "$zi_log" ]]; then
        echo "[$(TS)] [UDP-zivpn] Log natif : $zi_log" >> "$LOG_FILE"
        while IFS= read -r line; do
            local user tx rx
            # Format JSON
            user=$(echo "$line" | grep -oP '(?<="auth":")[^"]+' 2>/dev/null || true)
            tx=$(echo   "$line" | grep -oP '(?<="tx":)[0-9]+'   2>/dev/null || true)
            rx=$(echo   "$line" | grep -oP '(?<="rx":)[0-9]+'   2>/dev/null || true)
            # Format texte clé=valeur
            if [[ -z "$user" ]]; then
                user=$(echo "$line" | grep -oP '(?<=user=)\S+' 2>/dev/null || true)
                tx=$(echo   "$line" | grep -oP '(?<=tx=)[0-9]+'  2>/dev/null || true)
                rx=$(echo   "$line" | grep -oP '(?<=rx=)[0-9]+'  2>/dev/null || true)
            fi
            [[ -z "$user" ]] && continue
            zi_native_up["$user"]=$(( ${zi_native_up["$user"]:-0} + ${rx:-0} ))
            zi_native_dn["$user"]=$(( ${zi_native_dn["$user"]:-0} + ${tx:-0} ))
        done < <(grep -a 'disconnect\|closed\|tx=' "$zi_log" 2>/dev/null | tail -10000)
    else
        local tmp_zjlog; tmp_zjlog=$(mktemp)
        journalctl -u zivpn --no-pager -n 10000 2>/dev/null \
            | grep -a 'disconnect\|closed\|tx=' > "$tmp_zjlog" || true
        if [[ -s "$tmp_zjlog" ]]; then
            echo "[$(TS)] [UDP-zivpn] Log natif via journalctl" >> "$LOG_FILE"
            while IFS= read -r line; do
                local user tx rx
                user=$(echo "$line" | grep -oP '(?<="auth":")[^"]+' 2>/dev/null || true)
                tx=$(echo   "$line" | grep -oP '(?<="tx":)[0-9]+'   2>/dev/null || true)
                rx=$(echo   "$line" | grep -oP '(?<="rx":)[0-9]+'   2>/dev/null || true)
                [[ -z "$user" ]] && {
                    user=$(echo "$line" | grep -oP '(?<=user=)\S+' || true)
                    tx=$(echo "$line" | grep -oP '(?<=tx=)[0-9]+' || true)
                    rx=$(echo "$line" | grep -oP '(?<=rx=)[0-9]+' || true)
                }
                [[ -z "$user" ]] && continue
                zi_native_up["$user"]=$(( ${zi_native_up["$user"]:-0} + ${rx:-0} ))
                zi_native_dn["$user"]=$(( ${zi_native_dn["$user"]:-0} + ${tx:-0} ))
            done < "$tmp_zjlog"
        fi
        rm -f "$tmp_zjlog"
    fi

    if [[ ${#zi_native_up[@]} -gt 0 ]]; then
        for user in "${!zi_native_up[@]}"; do
            local snap_up="$SNAP_NATIVE/${user}.up" snap_dn="$SNAP_NATIVE/${user}.dn"
            local prev_up=0 prev_dn=0
            [[ -f "$snap_up" ]] && prev_up=$(cat "$snap_up" 2>/dev/null)
            [[ -f "$snap_dn" ]] && prev_dn=$(cat "$snap_dn" 2>/dev/null)
            [[ ! "$prev_up" =~ ^[0-9]+$ ]] && prev_up=0
            [[ ! "$prev_dn" =~ ^[0-9]+$ ]] && prev_dn=0
            local cur_up="${zi_native_up[$user]}" cur_dn="${zi_native_dn[$user]}"
            local dlt_up=$(( cur_up > prev_up ? cur_up - prev_up : 0 ))
            local dlt_dn=$(( cur_dn > prev_dn ? cur_dn - prev_dn : 0 ))
            (( dlt_up + dlt_dn == 0 )) && continue
            grep -q "^${user}|" "$zi_uf" 2>/dev/null || continue
            echo "$cur_up" > "$snap_up"
            echo "$cur_dn" > "$snap_dn"
            [[ $first -eq 0 ]] && json+=","
            json+="{\"username\":\"${user}\",\"upload_bytes\":${dlt_up},\"download_bytes\":${dlt_dn}}"
            first=0; has_data=1
            echo "[$(TS)] [UDP-zivpn] [NATIF] $user ↑$(( dlt_up/1048576 ))MB ↓$(( dlt_dn/1048576 ))MB" >> "$LOG_FILE"
        done
    else
        # ── Méthode 2 : iptables par IP active ───────────────────────────────
        echo "[$(TS)] [UDP-zivpn] Aucun log natif — fallback iptables/IP active" >> "$LOG_FILE"
        init_udp_per_ip_chain

        local active_ips=()
        while IFS= read -r ip; do
            [[ -z "$ip" || "$ip" == "127.0.0.1" ]] && continue
            active_ips+=("$ip")
        done < <(ss -u -a -n 2>/dev/null | awk -v p=":${zi_port}" '
            $1=="ESTAB" && ($5 ~ p || $4 ~ p) {
                split($4=="*" ? $5 : $4, a, ":")
                if (a[1]!="" && a[1]!="*") print a[1]
            }' | sort -u)

        if [[ ${#active_ips[@]} -eq 0 ]]; then
            echo "[$(TS)] [UDP-zivpn] Aucune session active — trafic non comptabilisé" >> "$LOG_FILE"
        else
            echo "[$(TS)] [UDP-zivpn] ${#active_ips[@]} IP(s) active(s) sur port ${zi_port}" >> "$LOG_FILE"

            # Map IP→user depuis les logs de connexion Zivpn
            declare -A zi_ip_user=()
            local zi_conn_src="${zi_log}"
            if [[ -z "$zi_conn_src" ]]; then
                zi_conn_src=$(mktemp)
                journalctl -u zivpn --no-pager -n 2000 2>/dev/null \
                    | grep 'connect' > "$zi_conn_src" || true
            fi
            if [[ -f "$zi_conn_src" && -s "$zi_conn_src" ]]; then
                while IFS= read -r line; do
                    local user ip_raw
                    user=$(echo   "$line" | grep -oP '(?<="auth":")[^"]+' 2>/dev/null || true)
                    ip_raw=$(echo "$line" | grep -oP '(?<="addr":")[^"]+' 2>/dev/null || true)
                    [[ -z "$user" && -z "$ip_raw" ]] && {
                        user=$(echo "$line" | grep -oP '(?<=user=)\S+' || true)
                        ip_raw=$(echo "$line" | grep -oP '(?<=addr=)\S+' || true)
                    }
                    [[ -z "$user" || -z "$ip_raw" ]] && continue
                    zi_ip_user["${ip_raw%:*}"]="$user"
                done < <(grep -a 'connect' "$zi_conn_src" 2>/dev/null | tail -2000)
            fi

            declare -A zi_user_up=() zi_user_dn=()
            for ip in "${active_ips[@]}"; do
                _ensure_iptables_rule_for_ip "$ip" "$zi_port" "KIGHMU_UDP_PER_IP"
                local snap_up_f="$SNAP_IPTA/${ip//./_}.up"
                local snap_dn_f="$SNAP_IPTA/${ip//./_}.dn"
                local raw_up raw_dn
                raw_up=$(iptables -nvx -L KIGHMU_UDP_PER_IP 2>/dev/null | \
                    awk -v ip="$ip" -v p="$zi_port" '$8==ip && $10~"dpt:"p {sum+=$2} END{print sum+0}')
                raw_dn=$(iptables -nvx -L KIGHMU_UDP_PER_IP 2>/dev/null | \
                    awk -v ip="$ip" -v p="$zi_port" '$9==ip && $10~"spt:"p {sum+=$2} END{print sum+0}')
                local prev_up=0 prev_dn=0
                [[ -f "$snap_up_f" ]] && prev_up=$(cat "$snap_up_f" 2>/dev/null)
                [[ -f "$snap_dn_f" ]] && prev_dn=$(cat "$snap_dn_f" 2>/dev/null)
                [[ ! "$prev_up" =~ ^[0-9]+$ ]] && prev_up=0
                [[ ! "$prev_dn" =~ ^[0-9]+$ ]] && prev_dn=0
                local dlt_up=$(( raw_up > prev_up ? raw_up - prev_up : 0 ))
                local dlt_dn=$(( raw_dn > prev_dn ? raw_dn - prev_dn : 0 ))
                (( dlt_up + dlt_dn == 0 )) && continue
                echo "$raw_up" > "$snap_up_f"
                echo "$raw_dn" > "$snap_dn_f"
                local uname="${zi_ip_user[$ip]:-}"
                if [[ -z "$uname" ]]; then
                    echo "[$(TS)] [UDP-zivpn] IP $ip non identifiée — $(( (dlt_up+dlt_dn)/1048576 ))MB ignorés" >> "$LOG_FILE"
                    continue
                fi
                zi_user_up["$uname"]=$(( ${zi_user_up["$uname"]:-0} + dlt_up ))
                zi_user_dn["$uname"]=$(( ${zi_user_dn["$uname"]:-0} + dlt_dn ))
            done

            for uname in "${!zi_user_up[@]}"; do
                local du="${zi_user_up[$uname]}" dd="${zi_user_dn[$uname]}"
                (( du + dd == 0 )) && continue
                [[ $first -eq 0 ]] && json+=","
                json+="{\"username\":\"${uname}\",\"upload_bytes\":${du},\"download_bytes\":${dd}}"
                first=0; has_data=1
                echo "[$(TS)] [UDP-zivpn] [IPTA] $uname ↑$(( du/1048576 ))MB ↓$(( dd/1048576 ))MB" >> "$LOG_FILE"
            done
        fi
    fi

    json+="]}"
    if [[ $has_data -eq 1 ]]; then
        echo "[$(TS)] [UDP-zivpn] Envoi stats panel..." >> "$LOG_FILE"
        send_stats "$json"
    else
        echo "[$(TS)] [UDP-zivpn] Aucun nouveau trafic" >> "$LOG_FILE"
    fi
}

collect_udp_traffic() {
    collect_hysteria_traffic
    collect_zivpn_traffic
}

echo "[$(TS)] Collecte des stats de trafic..." >> "$LOG_FILE"
collect_xray_traffic
collect_v2ray_traffic
collect_ssh_traffic
collect_udp_traffic

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
        local blocked_dir="/etc/zivpn/blocked"
        [[ ! -f "$f" ]] && return
        mkdir -p "$blocked_dir"
        # Sauvegarder la ligne de l'utilisateur avant de la retirer
        local user_line
        user_line=$(grep "^${u}|" "$f" 2>/dev/null || true)
        if [[ -n "$user_line" ]]; then
            echo "$user_line" > "${blocked_dir}/${u}.blocked"
            chmod 600 "${blocked_dir}/${u}.blocked"
        fi
        # Retirer de users.list
        sed -i "/^${u}|/d" "$f"
        # Resynchroniser config.json
        local pw; pw=$(awk -F'|' -v t="$TODAY" '$3>=t {print $2}' "$f" | sort -u | paste -sd, -)
        [[ -n "$pw" ]] && { local tmp; tmp=$(mktemp)
            jq --arg p "$pw" '.auth.config=($p|split(","))' "$c" > "$tmp" && mv "$tmp" "$c" || rm -f "$tmp"; }
        systemctl restart zivpn 2>/dev/null || true
        echo "[$(TS)] [BLOCK-ZIVPN] $u bloqué — password sauvegardé dans ${blocked_dir}/${u}.blocked" >> "$LOG_FILE"
    }
    _block_hysteria() {
        local u="$1" f="/etc/hysteria/users.txt" c="/etc/hysteria/config.json"
        local blocked_dir="/etc/hysteria/blocked"
        [[ ! -f "$f" ]] && return
        mkdir -p "$blocked_dir"
        # Sauvegarder la ligne de l'utilisateur avant de la retirer
        local user_line
        user_line=$(grep "^${u}|" "$f" 2>/dev/null || true)
        if [[ -n "$user_line" ]]; then
            echo "$user_line" > "${blocked_dir}/${u}.blocked"
            chmod 600 "${blocked_dir}/${u}.blocked"
        fi
        # Retirer de users.txt
        sed -i "/^${u}|/d" "$f"
        # Resynchroniser config.json
        local pw; pw=$(awk -F'|' -v t="$TODAY" '$3>=t {print $2}' "$f" | sort -u | paste -sd, -)
        [[ -n "$pw" ]] && { local tmp; tmp=$(mktemp)
            jq --arg p "$pw" '.auth.config=($p|split(","))' "$c" > "$tmp" && mv "$tmp" "$c" || rm -f "$tmp"; }
        systemctl restart hysteria 2>/dev/null || true
        echo "[$(TS)] [BLOCK-HYSTERIA] $u bloqué — password sauvegardé dans ${blocked_dir}/${u}.blocked" >> "$LOG_FILE"
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

    # Clients dépassant leur quota
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

    # Revendeurs dépassant leur quota
    local r_blocked=0
    while IFS=$'\t' read -r rid r_user r_limit r_total; do
        [[ -z "$r_user" ]] && continue
        local r_used; r_used=$(awk "BEGIN {printf \"%.2f\", $r_total/1073741824}")
        echo "[$(TS)] [QUOTA] Revendeur $r_user — ${r_used}Go / ${r_limit}Go" >> "$LOG_FILE"
        while IFS=$'\t' read -r cid c_user c_uuid c_tunnel; do
            [[ -z "$c_user" ]] && continue
            _do_block "$cid" "$c_user" "$c_uuid" "$c_tunnel"
        done < <(mysql_query "
            SELECT id,username,uuid,tunnel_type
            FROM clients
            WHERE reseller_id=${rid} AND is_active=1 AND quota_blocked=0;")
        (( r_blocked++ ))
    done < <(mysql_query "
        SELECT r.id, r.username, r.data_limit_gb,
               COALESCE(SUM(u.upload_bytes+u.download_bytes),0) AS total_bytes
        FROM resellers r
        LEFT JOIN usage_stats u ON u.reseller_id=r.id
        WHERE r.data_limit_gb>0 AND r.is_active=1 AND r.expires_at > NOW()
        GROUP BY r.id
        HAVING total_bytes >= (r.data_limit_gb * 1073741824);")

    [[ $r_blocked -gt 0 ]] \
        && echo "[$(TS)] [QUOTA] $r_blocked revendeur(s) bloque(s)" >> "$LOG_FILE"
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
        jq --arg today "$TODAY" '[.[] | select(.expire >= $today)]' "$USER_DB" \
            > "$USER_DB.tmp" && mv "$USER_DB.tmp" "$USER_DB"
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
    local PASSWORDS; PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' \
        "$ZIVPN_USER_FILE" | sort -u | paste -sd, -)
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
    jq --argjson ids "$(printf '%s\n%s\n' "$expired_vmess" "$expired_vless" \
            | jq -R -s -c 'split("\n")[:-1]')" \
       --argjson pw "$(printf '%s\n' "$expired_trojan" | jq -R -s -c 'split("\n")[:-1]')" '
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
    [[ ! -f "$HYSTERIA_USER_FILE" ]] && {
        echo "[$(TS)] users.txt Hysteria introuvable" >> "$LOG_FILE"; return; }
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
    local PASSWORDS; PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' \
        "$HYSTERIA_USER_FILE" | sort -u | paste -sd, -)
    local tmp; tmp=$(mktemp)
    if jq --arg p "$PASSWORDS" '.auth.config=($p|split(","))' "$HYSTERIA_CONFIG" > "$tmp" \
        && jq empty "$tmp" >/dev/null 2>&1; then
        mv "$tmp" "$HYSTERIA_CONFIG"
        local NUM_AFTER; NUM_AFTER=$(wc -l < "$HYSTERIA_USER_FILE")
        [[ "$NUM_AFTER" -lt "$NUM_BEFORE" ]] && systemctl restart hysteria
        echo "[$(TS)] Hysteria nettoye et redemarre" >> "$LOG_FILE"
    else
        echo "[$(TS)] Erreur JSON Hysteria" >> "$LOG_FILE"; rm -f "$tmp"
    fi
}

clean_zivpn_users
clean_xray_users
clean_hysteria_users

echo "[$(TS)] Termine" >> "$LOG_FILE"
echo "[$(TS)] ============================================" >> "$LOG_FILE"
