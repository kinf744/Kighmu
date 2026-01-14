#!/bin/bash
# ======================================================
# SSH / WS QUOTA INIT + CHECK
# Auto-initialisation + auto-exécution
# ======================================================

SCRIPT_PATH="/usr/local/bin/quota.sh"

# 🔒 Auto-permission (UNE SEULE FOIS)
if [ ! -x "$SCRIPT_PATH" ]; then
    chmod +x "$SCRIPT_PATH" 2>/dev/null
fi

DB="/etc/sshws-quota/users.db"
CHAIN="SSHWS_QUOTA"
LOG="/etc/sshws-quota/quota.log"

# ================= DOSSIERS =================
mkdir -p /etc/sshws-quota
touch "$DB" "$LOG"

# ================= IPTABLES INIT =================
iptables -N $CHAIN 2>/dev/null

iptables -C OUTPUT -j $CHAIN 2>/dev/null || iptables -A OUTPUT -j $CHAIN
iptables -C INPUT  -j $CHAIN 2>/dev/null || iptables -A INPUT  -j $CHAIN

# ================= QUOTA CHECK =================
while IFS=: read -r USER QUOTA; do
    id "$USER" &>/dev/null || continue
    [[ -z "$QUOTA" ]] && continue

    UID=$(id -u "$USER")

    # Règle de comptage
    iptables -C $CHAIN -m owner --uid-owner "$UID" -j RETURN 2>/dev/null || \
    iptables -A $CHAIN -m owner --uid-owner "$UID" -j RETURN

    # Lecture DATA
    BYTES=$(iptables -L $CHAIN -v -n | awk -v uid="$UID" '$0~uid {sum+=$2} END {print sum}')
    BYTES=${BYTES:-0}

    USED_GB=$(( BYTES / 1024 / 1024 / 1024 ))

    # Blocage si quota atteint
    if (( USED_GB >= QUOTA )); then
        iptables -C $CHAIN -m owner --uid-owner "$UID" -j DROP 2>/dev/null || \
        iptables -A $CHAIN -m owner --uid-owner "$UID" -j DROP

        passwd -l "$USER" &>/dev/null

        echo "$(date '+%F %T') | $USER BLOQUÉ ($USED_GB/$QUOTA Go)" >> "$LOG"
    fi

done < "$DB"

exit 0
