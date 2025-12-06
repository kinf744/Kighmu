#!/bin/bash
set -euo pipefail

# --- Configuration principale ---
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=53
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"

# Cloudflare API
CF_API_TOKEN="t4RmpfDtvrrb9FvMzXTxZnJ3ZnP3KdlqWSlCsFMI"
CF_ZONE_ID="45827ec075b0d9b60039d406765abead"
DOMAIN="kingdom.qzz.io"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# --- Vérification root ---
if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en root." >&2
    exit 1
fi

# --- Dépendances ---
log "Installation des dépendances..."
apt update -y
apt install -y curl jq iptables iptables-persistent

# --- DNSTT ---
if [ ! -x "$SLOWDNS_BIN" ]; then
    log "Téléchargement du binaire DNSTT..."
    curl -L -o "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
    chmod +x "$SLOWDNS_BIN"
fi

mkdir -p "$SLOWDNS_DIR"

# --- Choix du mode auto/man ---
read -rp "Choisissez le mode d'installation [auto/man] : " MODE
MODE=${MODE,,}  # minuscule

if [[ "$MODE" == "auto" ]]; then
    log "Mode AUTO sélectionné : génération automatique du NS"

    # Générer un sous-domaine aléatoire
    SUBDOMAIN="tun-$(tr -dc a-z0-9 </dev/urandom | head -c6)"
    DOMAIN_NS="${SUBDOMAIN}.${DOMAIN}"
    VPS_IP=$(curl -s ipv4.icanhazip.com)

    log "Création de l'enregistrement A sur Cloudflare : $DOMAIN_NS -> $VPS_IP"

    # Créer l'enregistrement A via l'API Cloudflare
    RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$DOMAIN_NS\",\"content\":\"$VPS_IP\",\"ttl\":120,\"proxied\":false}")

    SUCCESS=$(echo "$RESPONSE" | jq -r .success)
    if [[ "$SUCCESS" != "true" ]]; then
        echo "Erreur Cloudflare : $(echo "$RESPONSE" | jq -r .errors[].message)"
        exit 1
    fi

elif [[ "$MODE" == "man" ]]; then
    read -rp "Entrez le NameServer (NS) à utiliser : " DOMAIN_NS
else
    echo "Mode invalide, utilisez 'auto' ou 'man'" >&2
    exit 1
fi

# --- Écriture NS ---
echo "$DOMAIN_NS" > "$CONFIG_FILE"
log "NS sélectionné : $DOMAIN_NS"

# --- Clés fixes ---
echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
chmod 600 "$SERVER_KEY"
chmod 644 "$SERVER_PUB"

# --- Wrapper SlowDNS ---
cat <<'EOF' > /usr/local/bin/slowdns-start.sh
#!/bin/bash
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
NS=$(cat "$CONFIG_FILE")
ssh_port=22
exec "$SLOWDNS_BIN" -udp :53 -privkey-file "$SERVER_KEY" "$NS" 0.0.0.0:$ssh_port
EOF
chmod +x /usr/local/bin/slowdns-start.sh

# --- Service systemd ---
cat <<EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS Server Tunnel (DNSTT)
After=network-online.target
Wants=network-online.target

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

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable slowdns.service
systemctl restart slowdns.service

log "SlowDNS installé et démarré avec NS : $DOMAIN_NS"
