#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
ENV_FILE="$SLOWDNS_DIR/slowdns.env"
BACKEND_CONF="$SLOWDNS_DIR/backend.conf"

CF_API_TOKEN="7mn4LKcZARvdbLlCVFTtaX7LGM2xsnyjHkiTAt37"
CF_ZONE_ID="7debbb8ea4946898a889c4b5745ab7eb"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Vérification root
[[ "$EUID" -ne 0 ]] && echo "Ce script doit être exécuté en root." >&2 && exit 1

mkdir -p "$SLOWDNS_DIR"

# Désactivation systemd-resolved et config resolv.conf
log "Désactivation systemd-resolved et configuration DNS..."
systemctl disable --now systemd-resolved.service || true
chattr -i /etc/resolv.conf 2>/dev/null || true
cat <<EOF > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
options timeout:1
options attempts:1
EOF
chmod 644 /etc/resolv.conf

# Dépendances
log "Installation des dépendances..."
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y nftables curl tcpdump jq python3 python3-venv python3-pip iproute2

# Activer nftables
systemctl enable nftables
systemctl start nftables

# venv et cloudflare python
if [[ ! -d "$SLOWDNS_DIR/venv" ]]; then
    python3 -m venv "$SLOWDNS_DIR/venv"
fi
source "$SLOWDNS_DIR/venv/bin/activate"
pip install --upgrade pip >/dev/null
pip install cloudflare >/dev/null || log "pip install cloudflare failed (non fatal)"

# DNSTT binaire
if [[ ! -x "$SLOWDNS_BIN" ]]; then
    log "Téléchargement DNSTT..."
    curl -fsSL -o "$SLOWDNS_BIN" https://www.bamsoftware.com/software/dnstt/dnstt-server-linux-amd64
    chmod +x "$SLOWDNS_BIN"
fi

# Backend
choose_backend() {
    echo -e "\nChoix du backend SlowDNS :"
    echo "1) SSH direct"
    echo "2) V2Ray direct"
    echo "3) MIX"
    read -rp "Sélectionnez [1-3] : " mode
    case "$mode" in
        1) BACKEND_MODE="ssh" ;;
        2) BACKEND_MODE="v2ray" ;;
        3) BACKEND_MODE="mix" ;;
        *) echo "Mode invalide"; exit 1 ;;
    esac
    echo "BACKEND_MODE=$BACKEND_MODE" > "$BACKEND_CONF"
    log "Backend : $BACKEND_MODE"
}

# NS
read -rp "Mode d'installation NS [auto/man] : " MODE
MODE=${MODE,,}

generate_ns_auto() {
    DOMAIN="kingom.ggff.net"
    VPS_IP=$(curl -s ipv4.icanhazip.com || echo "127.0.0.1")
    SUB_A="vpn-$(date +%s | sha256sum | head -c 6)"
    FQDN_A="$SUB_A.$DOMAIN"
    log "Création A : $FQDN_A -> $VPS_IP"

    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
         -H "Authorization: Bearer $CF_API_TOKEN" \
         -H "Content-Type: application/json" \
         --data "{\"type\":\"A\",\"name\":\"$FQDN_A\",\"content\":\"$VPS_IP\",\"ttl\":120,\"proxied\":false}" \
         | jq . || log "Erreur Cloudflare A record"

    SUB_NS="ns-$(date +%s | sha256sum | head -c 6)"
    NS="$SUB_NS.$DOMAIN"
    log "Création NS : $NS -> $FQDN_A"

    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
         -H "Authorization: Bearer $CF_API_TOKEN" \
         -H "Content-Type: application/json" \
         --data "{\"type\":\"NS\",\"name\":\"$NS\",\"content\":\"$FQDN_A\",\"ttl\":120}" \
         | jq . || log "Erreur Cloudflare NS record"

    echo -e "NS=$NS\nENV_MODE=auto" > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    log "NS auto sauvegardé : $NS"
    echo "$NS"
}

# Gestion NS persistant
if [[ "$MODE" == "auto" ]]; then
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
        [[ "${ENV_MODE:-}" == "auto" && -n "${NS:-}" ]] && log "NS auto existant : $NS" || NS=$(generate_ns_auto)
    else
        NS=$(generate_ns_auto)
    fi
elif [[ "$MODE" == "man" ]]; then
    read -rp "Entrez NS : " NS
    echo -e "NS=$NS\nENV_MODE=man" > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    log "NS manuel sauvegardé : $NS"
else
    echo "Mode invalide" >&2
    exit 1
fi

choose_backend

echo "$NS" > "$CONFIG_FILE"
chmod 644 "$CONFIG_FILE"
log "NS utilisé : $NS"

# Clés fixes
cat > "$SERVER_KEY" <<'KEY'
4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa
KEY
cat > "$SERVER_PUB" <<'PUB'
2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c
PUB
chmod 600 "$SERVER_KEY"
chmod 644 "$SERVER_PUB"

# Kernel tuning
log "Optimisations réseau..."
cat > /etc/sysctl.d/99-slowdns.conf <<'EOF'
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.core.rmem_default=8192000
net.core.wmem_default=8192000
net.core.netdev_max_backlog=60000
net.core.somaxconn=4096
net.ipv4.udp_rmem_min=32768
net.ipv4.udp_wmem_min=32768
net.ipv4.udp_mem=4096 87380 268435456
net.core.optmem_max=65536
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.neigh.default.gc_thresh1=4096
net.ipv4.neigh.default.gc_thresh2=8192
net.ipv4.neigh.default.gc_thresh3=16384
EOF
sysctl --system >/dev/null || log "sysctl apply returned non-zero"

# Wrapper startup
cat > /usr/local/bin/slowdns-start.sh << 'EOF'
#!/bin/bash
set -euo pipefail
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
BACKEND_CONF="$SLOWDNS_DIR/backend.conf"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

wait_for_iface() {
  local iface=""
  while [ -z "$iface" ]; do
    iface=$(ip -o link show up | awk -F': ' '{print $2}' | grep -v '^lo$' | grep -vE '^(docker|veth|br|virbr|tun|tap|wl|vmnet|vboxnet)' | head -n1)
    [ -z "$iface" ] && sleep 1
  done
  echo "$iface"
}

select_backend_target() {
    local mode target ssh_port
    mode="ssh"
    [ -f "$BACKEND_CONF" ] && source "$BACKEND_CONF" && mode="${BACKEND_MODE:-ssh}"

    case "$mode" in
        ssh)
            ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2 || echo 22)
            [ -z "$ssh_port" ] && ssh_port=22
            target="127.0.0.1:$ssh_port"
            ;;
        v2ray) target="127.0.0.1:5401" ;;
        mix) target="127.0.0.1:8443" ;;
        *) target="127.0.0.1:22" ;;
    esac
    echo "$target"
}

iface=$(wait_for_iface)
backend_target=$(select_backend_target)

exec "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" "$(cat "$CONFIG_FILE")" "$backend_target"
EOF
chmod +x /usr/local/bin/slowdns-start.sh

# Service systemd SlowDNS
cat > /etc/systemd/system/slowdns.service <<'EOF'
[Unit]
Description=SlowDNS Server (DNSTT) - Multi Backend
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/slowdns-start.sh
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
LimitNPROC=65535
TasksMax=infinity
StandardOutput=append:/var/log/slowdns.log
StandardError=append:/var/log/slowdns.log

[Install]
WantedBy=multi-user.target
EOF

# nftables SlowDNS
mkdir -p /etc/nftables.d
cat > /etc/nftables.d/slowdns.nft <<'EOF'
table inet slowdns {
  chain prerouting {
    type nat hook prerouting priority -100; policy accept;
    udp dport 53 redirect to :5300
  }
  chain input {
    type filter hook input priority 0; policy accept;
    udp dport 5300 accept
  }
}
EOF

# Inclure la config si nécessaire
grep -q "/etc/nftables.d/slowdns.nft" /etc/nftables.conf || echo 'include "/etc/nftables.d/slowdns.nft"' >> /etc/nftables.conf

# Service nftables SlowDNS
cat > /etc/systemd/system/nftables-slowdns.service <<'EOF'
[Unit]
Description=nftables NAT redirect UDP 53 -> 5300 for SlowDNS
After=network-online.target nftables.service
Wants=network-online.target nftables.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/nftables.d/slowdns.nft
ExecStop=/usr/sbin/nft delete table inet slowdns || true

[Install]
WantedBy=multi-user.target
EOF

# Activation services
systemctl daemon-reload
systemctl enable nftables-slowdns.service
systemctl start nftables-slowdns.service
systemctl enable slowdns.service
systemctl restart slowdns.service

log "Installation terminée. SlowDNS prêt et sécurisé via nftables."
