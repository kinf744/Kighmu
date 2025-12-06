#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=53
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"

CF_API_TOKEN="7mn4LKcZARvdbLlCVFTtaX7LGM2xsnyjHkiTAt37"
CF_ZONE_ID="7debbb8ea4946898a889c4b5745ab7eb"
DOMAIN="kingom.ggff.net"

DEBUG=true

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
log_debug() { if [ "$DEBUG" = true ]; then echo "[DEBUG] $*"; fi; }

if [ "$EUID" -ne 0 ]; then
    echo "❌ Ce script doit être exécuté en root." >&2
    exit 1
fi

verify_cloudflare_token() {
    log "Vérification du token Cloudflare..."
    RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")

    if ! echo "$RESPONSE" | grep -q '"status":"active"'; then
        echo "❌ Token Cloudflare invalide ou permissions insuffisantes."
        echo "$RESPONSE"
        exit 1
    fi
    log_debug "Token vérifié : $RESPONSE"
    log "✔️ Token Cloudflare valide."
}

verify_cloudflare_zone() {
    log "Vérification de la zone Cloudflare..."
    ZONE_INFO=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID" \
        -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")

    if ! echo "$ZONE_INFO" | grep -q '"success":true'; then
        echo "❌ Zone ID Cloudflare invalide : $CF_ZONE_ID"
        exit 1
    fi

    ZONE_NAME=$(echo "$ZONE_INFO" | jq -r .result.name)
    log_debug "Zone trouvée : $ZONE_NAME"

    if [[ "$DOMAIN" != *"$ZONE_NAME" ]]; then
        echo "❌ Domaine '$DOMAIN' n'appartient pas à la zone Cloudflare '$ZONE_NAME'"
        exit 1
    fi

    log "✔️ Zone Cloudflare valide : $ZONE_NAME"
}

log "Installation des dépendances..."
apt update -y
apt install -y iptables iptables-persistent curl jq python3 python3-venv python3-pip

python3 -m venv "$SLOWDNS_DIR/venv"
source "$SLOWDNS_DIR/venv/bin/activate"
pip install --upgrade pip
pip install cloudflare flask

verify_cloudflare_token
verify_cloudflare_zone

if [ ! -x "$SLOWDNS_BIN" ]; then
    log "Téléchargement du binaire DNSTT..."
    curl -L -o "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
    chmod +x "$SLOWDNS_BIN"
fi

mkdir -p "$SLOWDNS_DIR"

read -rp "Choisissez le mode d'installation [auto/man] : " MODE
MODE=${MODE,,}

if [[ "$MODE" == "auto" ]]; then
    log "Mode AUTO sélectionné."

    VPS_IP=$(curl -s ipv4.icanhazip.com)
    SUB_A="vpn-$(date +%s | sha256sum | head -c 6)"
    FQDN_A="$SUB_A.$DOMAIN"

    log "Création de l'enregistrement A : $FQDN_A -> $VPS_IP"
    ADD_A=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$FQDN_A\",\"content\":\"$VPS_IP\",\"ttl\":1,\"proxied\":false}")
    log_debug "Réponse Cloudflare A : $ADD_A"

    SUB_NS="ns-$(date +%s | sha256sum | head -c 6)"
    DOMAIN_NS="$SUB_NS.$DOMAIN"

    log "Création de l'enregistrement NS : $DOMAIN_NS → $FQDN_A"
    ADD_NS=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
        --data "{\"type\":\"NS\",\"name\":\"$DOMAIN_NS\",\"content\":\"$FQDN_A\",\"ttl\":1}")
    log_debug "Réponse Cloudflare NS : $ADD_NS"

elif [[ "$MODE" == "man" ]]; then
    read -rp "Entrez le NS : " DOMAIN_NS
else
    echo "❌ Mode invalide."
    exit 1
fi

echo "$DOMAIN_NS" > "$CONFIG_FILE"
log "NS sélectionné : $DOMAIN_NS"

echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"

chmod 600 "$SERVER_KEY"
chmod 644 "$SERVER_PUB"

cat <<'EOF' > /usr/local/bin/slowdns-start.sh
#!/bin/bash
SLOWDNS_DIR="/etc/slowdns"
PORT=53
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"

NS=$(cat "$CONFIG_FILE")
ssh_port=22

exec "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" "$NS" 0.0.0.0:$ssh_port
EOF
chmod +x /usr/local/bin/slowdns-start.sh

cat <<EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS Tunnel (DNSTT)
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/slowdns-start.sh
Restart=on-failure
RestartSec=3
StandardOutput=append:/var/log/slowdns.log
StandardError=append:/var/log/slowdns.log
SyslogIdentifier=slowdns
LimitNOFILE=1048576
Nice=0
CPUSchedulingPolicy=other
IOSchedulingClass=best-effort
IOSchedulingPriority=4
TimeoutStartSec=20
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable slowdns.service
systemctl restart slowdns.service

log "✔️ SlowDNS installé avec succès !"
log "✔️ NS utilisé : $DOMAIN_NS"
