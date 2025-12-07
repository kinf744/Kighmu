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

# --- Cloudflare API (à mettre en variable d'environnement pour prod) ---
CF_API_TOKEN="${CF_API_TOKEN:-7mn4LKcZARvdbLlCVFTtaX7LGM2xsnyjHkiTAt37}"
CF_ZONE_ID="7debbb8ea4946898a889c4b5745ab7eb"

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

# --- Optimisations SSH ---
log "Optimisation SSH pour tunnel rapide..."
SSHD_CONFIG="/etc/ssh/sshd_config"
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%s)"
sed -i 's/^#?Ciphers .*/Ciphers aes128-ctr,aes192-ctr,aes256-ctr/' "$SSHD_CONFIG" || echo "Ciphers aes128-ctr,aes192-ctr,aes256-ctr" >> "$SSHD_CONFIG"
sed -i 's/^#?Compression .*/Compression yes/' "$SSHD_CONFIG" || echo "Compression yes" >> "$SSHD_CONFIG"
sed -i 's/^#?UseDNS .*/UseDNS no/' "$SSHD_CONFIG" || echo "UseDNS no" >> "$SSHD_CONFIG"
systemctl restart ssh

# --- Optimisations kernel UDP ---
log "Tuning kernel UDP pour stabilité..."
cat <<'SYSCTL' > /etc/sysctl.d/99-slowdns.conf
# Buffers UDP optimisés pour DNSTT
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400
net.core.rmem_default = 2621440
net.core.wmem_default = 2621440
SYSCTL
sysctl --system

# --- Création venv ---
mkdir -p "$SLOWDNS_DIR"
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

# --- Choix du mode auto/man ---
read -rp "Choisissez le mode d'installation [auto/man] : " MODE
MODE=${MODE,,}

if [[ "$MODE" == "auto" ]]; then
    log "Mode AUTO : génération NS/A records"
    DOMAIN="kingom.ggff.net"
    VPS_IP=$(curl -s ipv4.icanhazip.com)

    # Enregistrement A avec vérification
    SUB_A="vpn-$(date +%s | sha256sum | head -c 6)"
    FQDN_A="$SUB_A.$DOMAIN"
    log "Création A record $FQDN_A -> $VPS_IP"
    respA=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{"type":"A","name":"$FQDN_A","content":"$VPS_IP","ttl":120,"proxied":false}")
    
    if [ "$(echo "$respA" | jq -r '.success')" != "true" ]; then
        log "ERREUR A record: $(echo "$respA" | jq -r '.errors[0].message')"
        exit 1
    fi
    log "A record OK: $FQDN_A"

    # Enregistrement NS avec vérification
    SUB_NS="ns-$(date +%s | sha256sum | head -c 6)"
    DOMAIN_NS="$SUB_NS.$DOMAIN"
    log "Création NS record $DOMAIN_NS -> $FQDN_A"
    respNS=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{"type":"NS","name":"$DOMAIN_NS","content":"$FQDN_A","ttl":120}")
    
    if [ "$(echo "$respNS" | jq -r '.success')" != "true" ]; then
        log "ERREUR NS record: $(echo "$respNS" | jq -r '.errors[0].message')"
        exit 1
    fi
    log "NS record OK: $DOMAIN_NS"

elif [[ "$MODE" == "man" ]]; then
    read -rp "Entrez le NameServer (NS) à utiliser : " DOMAIN_NS
else
    echo "Mode invalide, utilisez 'auto' ou 'man'" >&2
    exit 1
fi

echo "$DOMAIN_NS" > "$CONFIG_FILE"
log "NS final: $DOMAIN_NS"

# --- Clés fixes ---
echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
chmod 600 "$SERVER_KEY"
chmod 644 "$SERVER_PUB"

# --- Wrapper SlowDNS (syntaxe OFFICIELLE dnstt.network) ---
cat <<'EOF' > /usr/local/bin/slowdns-start.sh
#!/bin/bash
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=53
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
NS=$(cat "$CONFIG_FILE")
ssh_port=22

# Syntaxe 100% officielle DNSTT - AUCUNE option supplémentaire
exec "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" "$NS" 0.0.0.0:$ssh_port
EOF
chmod +x /usr/local/bin/slowdns-start.sh

# --- Service systemd ---
cat <<EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS Server Tunnel (DNSTT) - Optimisé
After=network-online.target ssh.service
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
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable slowdns.service
systemctl restart slowdns.service

# --- Status final ---
log "✅ SlowDNS installé avec optimisations:"
log "   → SSH: aes128-ctr + compression + UseDNS=no"
log "   → Kernel: UDP buffers 26M"
log "   → NS: $DOMAIN_NS"
log "   → Logs: /var/log/slowdns.log"
log "   → Test: systemctl status slowdns.service"
