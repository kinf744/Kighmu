#!/bin/bash
# ==========================================
# QUOTA SSH / WS / TLS / UDP / XRAY (VNSTAT)
# ==========================================

IFACE=$(vnstat --iflist | awk 'NR==1{print $1}')
BASE_DIR="/etc/sshws-quota"
USERS_DB="$BASE_DIR/users.db"
USAGE_DB="$BASE_DIR/usage.db"
LOG="$BASE_DIR/quota.log"

mkdir -p "$BASE_DIR"
touch "$USERS_DB" "$USAGE_DB" "$LOG"

get_total_gb() {
    vnstat -i "$IFACE" --oneline b \
    | awk -F';' '{print int($9/1024/1024)}'
}

TOTAL_USED=$(get_total_gb)

while IFS=: read -r USER QUOTA; do
    id "$USER" &>/dev/null || continue
    [[ -z "$QUOTA" ]] && continue

    PREV=$(grep "^$USER:" "$USAGE_DB" | cut -d: -f2)
    PREV=${PREV:-0}

    DELTA=$(( TOTAL_USED - PREV ))
    [[ $DELTA -lt 0 ]] && DELTA=0

    USED=$(( PREV + DELTA ))

    sed -i "/^$USER:/d" "$USAGE_DB"
    echo "$USER:$USED" >> "$USAGE_DB"

    if (( USED >= QUOTA )); then
        passwd -l "$USER" &>/dev/null
        echo "$(date '+%F %T') | $USER BLOQUÉ ($USED/$QUOTA Go)" >> "$LOG"
    fi

done < "$USERS_DB"
