#!/bin/bash
# ==========================================
# QUOTA SSH/WS/TLS/UDP/XRAY (VNSTAT + IPTABLES)
# ==========================================

BASE_DIR="/etc/sshws-quota"
USERS_DB="$BASE_DIR/users.db"
USAGE_DB="$BASE_DIR/usage.db"
LOG="$BASE_DIR/quota.log"

mkdir -p "$BASE_DIR"
touch "$USERS_DB" "$USAGE_DB" "$LOG"

CHAIN="SSHWS_QUOTA"

# ================= IPTABLES INIT =================
iptables -N $CHAIN 2>/dev/null || true
iptables -C OUTPUT -j $CHAIN 2>/dev/null || iptables -A OUTPUT -j $CHAIN
iptables -C INPUT  -j $CHAIN 2>/dev/null || iptables -A INPUT  -j $CHAIN

# ================= QUOTA CHECK =================
while IFS=: read -r USER QUOTA; do
    id "$USER" &>/dev/null || continue
    [[ -z "$QUOTA" ]] && continue

    UID=$(id -u "$USER")

    # Création règle de comptage si absente
    iptables -C $CHAIN -m owner --uid-owner "$UID" -j RETURN 2>/dev/null || \
    iptables -A $CHAIN -m owner --uid-owner "$UID" -j RETURN

    # Récupération des bytes envoyés+reçus
    BYTES=$(iptables -L $CHAIN -v -n | awk -v uid="$UID" '$0~uid {sum+=$2} END {print sum}')
    BYTES=${BYTES:-0}

    USED_GB=$(( BYTES / 1024 / 1024 / 1024 ))

    # Sauvegarde dans usage.db
    sed -i "/^$USER:/d" "$USAGE_DB"
    echo "$USER:$USED_GB" >> "$USAGE_DB"

    # Blocage si quota atteint
    if (( USED_GB >= QUOTA )); then
        # Bloque l’utilisateur
        passwd -l "$USER" &>/dev/null

        # Ajout DROP iptables si pas déjà
        iptables -C $CHAIN -m owner --uid-owner "$UID" -j DROP 2>/dev/null || \
        iptables -A $CHAIN -m owner --uid-owner "$UID" -j DROP

        # Log
        echo "$(date '+%F %T') | $USER BLOQUÉ ($USED_GB/$QUOTA Go)" >> "$LOG"
    fi

done < "$USERS_DB"
