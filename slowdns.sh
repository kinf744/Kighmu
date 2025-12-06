#!/bin/bash
# install-slowdns-optimized.sh
# Version: 2025-12-06 - Optimized DNSTT (SlowDNS) + Systemd service + network tuning
# Usage:
#   MODE=auto CF_API_TOKEN="..." CF_ZONE_ID="..." DOMAIN="example.com" ./install-slowdns-optimized.sh
#   or interactively: ./install-slowdns-optimized.sh (defaults to MODE=auto)
set -euo pipefail

########################
# CONFIGURATION (edit or export env vars before running)
########################
: "${CF_API_TOKEN:=""}"   # Cloudflare API Token (scoped to DNS edit)
: "${CF_ZONE_ID:=""}"     # Cloudflare Zone ID
: "${DOMAIN:="kingom.ggff.net"}"  # Your base domain managed in Cloudflare
: "${MODE:=auto}"         # auto or man
: "${SLOWDNS_DIR:=/etc/slowdns}"
: "${SLOWDNS_BIN:=/usr/local/bin/dnstt-server}"
: "${PORT:=53}"
: "${SSH_PORT:=22}"
: "${DEBUG:=true}"

# Tunables
TASKSET_CPU="0"           # CPU core to pin DNSTT to
DNSTT_MTU="1024"
DNSTT_MAX_IDLE="30"
DNSTT_NICE="-15"

# Internal files
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
VENV_DIR="$SLOWDNS_DIR/venv"
SLOWDNS_START="/usr/local/bin/slowdns-start.sh"
SYSTEMD_UNIT="/etc/systemd/system/slowdns.service"
LOG_FILE="/var/log/slowdns.log"

########################
# Helpers
########################
log() { echo "[$(date '+%F %T')] $*"; }
log_debug() { if [ "$DEBUG" = true ]; then echo "[DEBUG] $*"; fi; }
err() { echo "[$(date '+%F %T')] ERROR: $*" >&2; }

require_root() {
    if [ "$EUID" -ne 0 ]; then
        err "Ce script doit être exécuté en root."
        exit 1
    fi
}

safe_curl() {
    # wrapper to avoid printing token
    curl -s -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" "$@"
}

########################
# Pre-flight
########################
require_root
log "Démarrage de l'installation SlowDNS optimisée..."

# Basic packages
log "Installation des dépendances apt (non interactif)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends iptables iptables-persistent curl jq python3 python3-venv python3-pip ca-certificates

# Create dirs
mkdir -p "$SLOWDNS_DIR"
chown root:root "$SLOWDNS_DIR"
chmod 700 "$SLOWDNS_DIR"

########################
# Virtualenv & python deps (for optional Cloudflare helper)
########################
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi
# activate and install minimal libs
# use --no-warn-script-location to reduce noise
source "$VENV_DIR/bin/activate"
pip install --upgrade pip >/dev/null
pip install --upgrade cloudflare flask >/dev/null || true
deactivate

########################
# Verify Cloudflare token & zone (only if token/zone provided)
########################
if [ -n "$CF_API_TOKEN" ] && [ -n "$CF_ZONE_ID" ]; then
    log "Vérification du token Cloudflare (masqué)..."
    RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")
    if ! echo "$RESPONSE" | jq -e '.result | .status=="active"' >/dev/null 2>&1; then
        err "Token Cloudflare invalide ou permissions insuffisantes."
        log_debug "Cloudflare verify response: $(echo "$RESPONSE" | jq -c '.')"
        # continue but warn
        err "Abandon: vérifier CF_API_TOKEN et permissions (DNS edit)."
        exit 1
    fi
    log "✔️ Token Cloudflare actif."

    log "Vérification de la zone Cloudflare..."
    ZONE_INFO=$(safe_curl -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID")
    if ! echo "$ZONE_INFO" | jq -e '.success' >/dev/null 2>&1; then
        err "Zone Cloudflare invalide (CF_ZONE_ID=$CF_ZONE_ID)."
        log_debug "Zone response: $(echo "$ZONE_INFO" | jq -c '.')"
        exit 1
    fi
    ZONE_NAME=$(echo "$ZONE_INFO" | jq -r '.result.name')
    log "✔️ Zone Cloudflare trouvée: $ZONE_NAME"
    if [[ "$DOMAIN" != *"$ZONE_NAME" && "$ZONE_NAME" != "$DOMAIN" ]]; then
        err "Le domaine '$DOMAIN' ne semble pas appartenir à la zone Cloudflare '$ZONE_NAME'."
        exit 1
    fi
else
    err "CF_API_TOKEN ou CF_ZONE_ID manquant. Le mode Cloudflare AUTO ne sera pas utilisé."
fi

########################
# Download DNSTT binary if missing
########################
if [ ! -x "$SLOWDNS_BIN" ]; then
    log "Téléchargement du binaire DNSTT..."
    curl -L -o "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
    chmod +x "$SLOWDNS_BIN"
fi
log_debug "DNSTT binaire: $SLOWDNS_BIN"

########################
# Manage keys (do NOT expose private key in logs)
########################
if [ ! -f "$SERVER_KEY" ] || [ ! -f "$SERVER_PUB" ]; then
    log "Installation des clés DNSTT (clés embarquées ou génération)..."
    # If you have custom keys, replace the following strings or put files into SLOWDNS_DIR before running.
    cat > "$SERVER_KEY" <<'EOF'
4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa
EOF
    cat > "$SERVER_PUB" <<'EOF'
2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c
EOF
    chmod 600 "$SERVER_KEY"
    chmod 644 "$SERVER_PUB"
else
    log_debug "Clés DNSTT déjà présentes."
fi

########################
# Generate NS records via Cloudflare (AUTO mode)
########################
DOMAIN_NS=""
if [ "$MODE" = "auto" ] && [ -n "$CF_API_TOKEN" ] && [ -n "$CF_ZONE_ID" ]; then
    log "Mode AUTO: création A + NS via Cloudflare..."
    VPS_IP=$(curl -s ipv4.icanhazip.com)
    if [ -z "$VPS_IP" ]; then
        err "Impossible de récupérer l'IP publique (icanhazip)."
        exit 1
    fi
    # generate short random subdomain
    SUB_A="vpn-$(date +%s | sha256sum | head -c 6)"
    FQDN_A="$SUB_A.$DOMAIN"

    log "Création de l'enregistrement A: $FQDN_A -> $VPS_IP"
    ADD_A=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$FQDN_A\",\"content\":\"$VPS_IP\",\"ttl\":1,\"proxied\":false}")
    if ! echo "$ADD_A" | jq -e '.success' >/dev/null 2>&1; then
        err "Échec création A record. Réponse CF: $(echo "$ADD_A" | jq -c '.')"
        exit 1
    fi

    SUB_NS="ns-$(date +%s | sha256sum | head -c 6)"
    DOMAIN_NS="$SUB_NS.$DOMAIN"
    log "Création de l'enregistrement NS: $DOMAIN_NS -> $FQDN_A"
    ADD_NS=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
        --data "{\"type\":\"NS\",\"name\":\"$DOMAIN_NS\",\"content\":\"$FQDN_A\",\"ttl\":1}")
    if ! echo "$ADD_NS" | jq -e '.success' >/dev/null 2>&1; then
        err "Échec création NS record. Réponse CF: $(echo "$ADD_NS" | jq -c '.')"
        exit 1
    fi
    log "✔️ Enregistrements A/NS créés: $FQDN_A , $DOMAIN_NS"
elif [ "$MODE" = "man" ]; then
    read -rp "Entrez le NS (ex: ns1.example.com): " DOMAIN_NS
else
    # if not auto and not man, try to read existing config
    if [ -f "$CONFIG_FILE" ]; then
        DOMAIN_NS=$(cat "$CONFIG_FILE")
        log_debug "NS lu depuis $CONFIG_FILE: $DOMAIN_NS"
    else
        err "Aucun NS fourni et aucun mode auto possible. Passez MODE=man pour entrer manuellement."
        exit 1
    fi
fi

# Persist selected NS
echo "$DOMAIN_NS" > "$CONFIG_FILE"
chmod 644 "$CONFIG_FILE"
log "NS utilisé: $DOMAIN_NS"

########################
# Network Tunables (applied immediately and persisted to sysctl.d)
########################
log "Application des optimisations réseau (sysctl)..."
SYSCTL_CONF="/etc/sysctl.d/99-slowdns-optim.conf"
cat > "$SYSCTL_CONF" <<EOF
# SlowDNS optimizations
net.core.rmem_max=26214400
net.core.wmem_max=26214400
net.ipv4.udp_mem=262144 327680 393216
net.core.netdev_max_backlog=250000
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384
net.core.somaxconn=65535
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.ip_forward=1
EOF
sysctl --system >/dev/null

########################
# iptables rules (accept DNS UDP 53 and ssh)
########################
log "Configuration iptables pour autoriser UDP/53 et TCP/$SSH_PORT..."
iptables -C INPUT -p udp --dport 53 -j ACCEPT >/dev/null 2>&1 || iptables -I INPUT -p udp --dport 53 -j ACCEPT
iptables -C INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT >/dev/null 2>&1 || iptables -I INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT

# Save persistent rules (works for iptables-persistent)
iptables-save > /etc/iptables/rules.v4

########################
# Create start script (with taskset + nice + options)
########################
log "Création du script de démarrage $SLOWDNS_START..."
cat > "$SLOWDNS_START" <<EOF
#!/bin/bash
set -euo pipefail
SLOWDNS_DIR="$SLOWDNS_DIR"
SLOWDNS_BIN="$SLOWDNS_BIN"
PORT="$PORT"
SSH_PORT="$SSH_PORT"
CONFIG_FILE="$CONFIG_FILE"
SERVER_KEY="$SERVER_KEY"

NS=\$(cat "\$CONFIG_FILE")
# Pin to CPU and raise priority to reduce jitter
exec taskset -c ${TASKSET_CPU} nice -n ${DNSTT_NICE} "\$SLOWDNS_BIN" \\
    -udp :\${PORT} \\
    -privkey-file "\$SERVER_KEY" \\
    -mtu ${DNSTT_MTU} \\
    -max-idle ${DNSTT_MAX_IDLE} \\
    "\$NS" 0.0.0.0:\${SSH_PORT}
EOF
chmod +x "$SLOWDNS_START"

########################
# Create robust systemd unit
########################
log "Création de l'unité systemd ($SYSTEMD_UNIT)..."
cat > "$SYSTEMD_UNIT" <<EOF
[Unit]
Description=DNSTT SlowDNS Server (optimized)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$SLOWDNS_START
Restart=always
RestartSec=2
# allow unlimited restarts in pathological situations
StartLimitIntervalSec=0
StartLimitBurst=0

# Give higher priority and resource limits
Nice=${DNSTT_NICE}
LimitNOFILE=200000
LimitNPROC=65536
TimeoutStopSec=5
KillSignal=SIGKILL

# Log to file (append)
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
log "Reload systemd, enable & restart service..."
systemctl daemon-reload
systemctl enable --now slowdns.service
systemctl restart slowdns.service || {
    err "Échec du démarrage du service slowdns. Voir $LOG_FILE pour détails."
    journalctl -u slowdns.service --no-pager -n 200 || true
    exit 1
}

########################
# Healthcheck: verify DNSTT listening on UDP/53
########################
sleep 1
if ss -lun | grep -q ":53"; then
    log "✔️ DNSTT écoute sur UDP/53"
else
    err "DNSTT ne semble pas écouter sur UDP/53. Voir journal systemd."
    journalctl -u slowdns.service --no-pager -n 200 || true
    exit 1
fi

log "Installation terminée avec succès !"
log "NS configuré : $(cat "$CONFIG_FILE")"
log "Journal : sudo journalctl -u slowdns.service -f"
log "Fichier de configuration : $CONFIG_FILE"
log "Clés privées protégées : $SERVER_KEY (chmod 600)"
