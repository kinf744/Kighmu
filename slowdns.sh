#!/bin/bash
set -euo pipefail

# --- Configuration principale ---
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=53
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
API_PORT=9999

# --- Cloudflare API ---
CF_API_TOKEN="t4RmpfDtvrrb9FvMzXTxZnJ3ZnP3KdlqWSlCsFMI"
CF_ZONE_ID="45827ec075b0d9b60039d406765abead"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# --- Vérification root ---
if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en root." >&2
    exit 1
fi

# --- Dépendances ---
log "Installation des dépendances..."
apt update -y
apt install -y iptables iptables-persistent curl tcpdump jq python3 python3-venv python3-pip

# --- Création venv ---
python3 -m venv "$SLOWDNS_DIR/venv"
source "$SLOWDNS_DIR/venv/bin/activate"
pip install --upgrade pip
pip install flask cloudflare

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

    DOMAIN="kingom.ggff.net"  # ton domaine principal
    VPS_IP=$(curl -s ipv4.icanhazip.com)

    # Création enregistrement A
    SUB_A="vpn-$(date +%s | sha256sum | head -c 6)"
    FQDN_A="$SUB_A.$DOMAIN"
    log "Création de l'enregistrement A $FQDN_A -> $VPS_IP"
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$FQDN_A\",\"content\":\"$VPS_IP\",\"ttl\":120,\"proxied\":false}" \
        | jq .

    # Création enregistrement NS
    SUB_NS="ns-$(date +%s | sha256sum | head -c 6)"
    DOMAIN_NS="$SUB_NS.$DOMAIN"
    log "Création de l'enregistrement NS $DOMAIN_NS -> $FQDN_A"
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"NS\",\"name\":\"$DOMAIN_NS\",\"content\":\"$FQDN_A\",\"ttl\":120}" \
        | jq .

elif [[ "$MODE" == "man" ]]; then
    read -rp "Entrez le NameServer (NS) à utiliser : " DOMAIN_NS
else
    echo "Mode invalide, utilisez 'auto' ou 'man'" >&2
    exit 1
fi

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
PORT=53
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
NS=$(cat "$CONFIG_FILE")
ssh_port=22
exec "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" "$NS" 0.0.0.0:$ssh_port
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
