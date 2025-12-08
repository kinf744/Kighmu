#!/bin/bash
set -euo pipefail

# --- Configuration principale ---
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
ENV_FILE="$SLOWDNS_DIR/slowdns.env"

# --- Cloudflare API ---
CF_API_TOKEN="7mn4LKcZARvdbLlCVFTtaX7LGM2xsnyjHkiTAt37"
CF_ZONE_ID="7debbb8ea4946898a889c4b5745ab7eb"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en root." >&2
    exit 1
fi

mkdir -p "$SLOWDNS_DIR"

# --- Dépendances ---
log "Installation des dépendances..."
apt update -y
apt install -y iptables iptables-persistent curl jq

# --- DNSTT ---
if [ ! -x "$SLOWDNS_BIN" ]; then
    log "Téléchargement du binaire DNSTT..."
    curl -L -o "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
    chmod +x "$SLOWDNS_BIN"
fi

# -------------------------------
# GÉNÉRATION DU NS AUTO
# -------------------------------
generate_ns_auto() {
    DOMAIN="kingom.ggff.net"
    VPS_IP=$(curl -s ipv4.icanhazip.com)

    SUB_A="vpn-$(date +%s | sha256sum | head -c 6)"
    FQDN_A="$SUB_A.$DOMAIN"
    log "→ Création du A : $FQDN_A -> $VPS_IP"

    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$FQDN_A\",\"content\":\"$VPS_IP\",\"ttl\":1,\"proxied\":false}" > /dev/null

    SUB_NS="ns-$(date +%s | sha256sum | head -c 6)"
    NS="$SUB_NS.$DOMAIN"

    log "→ Création du NS : $NS -> $FQDN_A"

    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"NS\",\"name\":\"$NS\",\"content\":\"$FQDN_A\",\"ttl\":1}" > /dev/null

    echo -e "NS=$NS\nENV_MODE=auto" > "$ENV_FILE"
}

# -------------------------------
# CHOIX MODE
# -------------------------------
read -rp "Choisissez le mode d'installation [auto/man] : " MODE
MODE=${MODE,,}

if [[ "$MODE" == "auto" ]]; then
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
        if [[ "${ENV_MODE:-}" == "auto" ]]; then
            log "NS auto existant détecté : $NS"
        else
            log "NS manuel existant → génération d'un nouveau NS auto..."
            generate_ns_auto
        fi
    else
        log "Aucun NS auto → génération..."
        generate_ns_auto
    fi

elif [[ "$MODE" == "man" ]]; then
    read -rp "Entrez le NameServer (NS) : " NS
    echo -e "NS=$NS\nENV_MODE=man" > "$ENV_FILE"
else
    echo "Mode invalide."
    exit 1
fi

echo "$NS" > "$CONFIG_FILE"

# -------------------------------
# CLÉS FIXES (DEMANDÉ PAR TOI)
# -------------------------------
echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
chmod 600 "$SERVER_KEY"
chmod 644 "$SERVER_PUB"

# -------------------------------
# SYSCTL OPTIMISÉ (HAUTE PERFORMANCE UDP)
# -------------------------------
log "Optimisation réseau UDP..."
cat <<EOF > /etc/sysctl.d/slowdns.conf
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=8388608
net.core.wmem_default=8388608
net.ipv4.udp_mem=2097152 4194304 8388608
net.ipv4.tcp_fin_timeout=10
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_mtu_probing=1
net.ipv4.ip_forward=1
EOF

sysctl --system

# -------------------------------
# DNS
# -------------------------------
log "Désactivation systemd-resolved..."
systemctl stop systemd-resolved
systemctl disable systemd-resolved

rm -f /etc/resolv.conf
echo "nameserver 1.1.1.1" > /etc/resolv.conf
chattr +i /etc/resolv.conf

# -------------------------------
# WRAPPER STARTUP
# -------------------------------
cat <<'EOF' > /usr/local/bin/slowdns-start.sh
#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

iface=$(ip route show default | awk '/default/ {print $5}' | head -n1)
log "Interface détectée : $iface"

log "Réglage MTU à 1400..."
ip link set dev "$iface" mtu 1400 || true

NS=$(cat "$CONFIG_FILE")
ssh_port=$(ss -tlnp | awk '/sshd/ {print $4}' | head -1 | cut -d: -f2)
[ -z "$ssh_port" ] && ssh_port=22

log "Démarrage DNSTT..."
exec "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" "$NS" 0.0.0.0:$ssh_port
EOF

chmod +x /usr/local/bin/slowdns-start.sh

# -------------------------------
# SYSTEMD SERVICE
# -------------------------------
cat <<EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS Server Tunnel (DNSTT)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/slowdns-start.sh
Restart=always
RestartSec=2
LimitNOFILE=1048576
StandardOutput=append:/var/log/slowdns.log
StandardError=append:/var/log/slowdns.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable slowdns.service
systemctl restart slowdns.service

log "✅ SlowDNS installé et optimisé. NS : $NS"
