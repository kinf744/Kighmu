#!/bin/bash
set -euo pipefail

# --- Configuration principale ---
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
LOG_FILE="/var/log/slowdns.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# --- Vérification root ---
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Ce script doit être exécuté en root." >&2
        exit 1
    fi
}

# --- Dépendances ---
install_dependencies() {
    log "Installation des dépendances..."
    apt-get update -q
    apt-get install -y nftables iptables iptables-persistent wget curl jq
}

# --- Installation SlowDNS binaire ---
install_slowdns_bin() {
    if [ ! -x "$SLOWDNS_BIN" ]; then
        log "Téléchargement du binaire SlowDNS..."
        wget -q -O "$SLOWDNS_BIN" \
          https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
        chmod +x "$SLOWDNS_BIN"
    fi
}

# --- Clés fixes ---
install_fixed_keys() {
    mkdir -p "$SLOWDNS_DIR"
    echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
    echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
    chmod 600 "$SERVER_KEY"
    chmod 644 "$SERVER_PUB"
}

# --- Désactivation systemd-resolved ---
disable_systemd_resolved() {
    log "Désactivation du stub DNS systemd-resolved..."
    systemctl stop systemd-resolved || true
    systemctl disable systemd-resolved || true

    cat <<EOF > /etc/resolv.conf
nameserver 8.8.8.8
nameserver 1.1.1.1
options timeout:1 attempts:1
EOF
}

# --- IPTABLES (SANS PORT 53) ---
configure_iptables() {
    log "Configuration iptables minimale (sans DNS)..."

    if ! iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT &>/dev/null; then
        iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
    fi

    iptables-save > /etc/iptables/rules.v4
    systemctl enable netfilter-persistent
    systemctl restart netfilter-persistent
}

# --- Cloudflare NS auto ---
CF_API_TOKEN="7mn4LKcZARvdbLlCVFTtaX7LGM2xsnyjHkiTAt37"
CF_ZONE_ID="7debbb8ea4946898a889c4b5745ab7eb"
DOMAIN="kingom.ggff.net"

generate_ns_cloudflare() {
    log "Génération automatique du NameServer via Cloudflare..."
    VPS_IP=$(curl -s ipv4.icanhazip.com)

    SUB_A="vpn-$(date +%s | sha256sum | head -c 6)"
    FQDN_A="$SUB_A.$DOMAIN"

    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"$FQDN_A\",\"content\":\"$VPS_IP\",\"ttl\":120}"

    SUB_NS="ns-$(date +%s | sha256sum | head -c 6)"
    NS="$SUB_NS.$DOMAIN"

    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"NS\",\"name\":\"$NS\",\"content\":\"$FQDN_A\",\"ttl\":120}"

    echo "$NS" > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    log "NS généré : $NS"
}

# --- Wrapper SlowDNS ---
create_wrapper_script() {
cat <<'EOF' > /usr/local/bin/slowdns-start.sh
#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

wait_iface() {
    while :; do
        iface=$(ip -o link show up | awk -F': ' '{print $2}' | grep -v lo | head -n1)
        [ -n "$iface" ] && echo "$iface" && return
        sleep 2
    done
}

setup_nftables() {
    nft list table ip slowdns_classic >/dev/null 2>&1 || nft add table ip slowdns_classic
    nft list chain ip slowdns_classic prerouting >/dev/null 2>&1 || \
        nft add chain ip slowdns_classic prerouting { type nat hook prerouting priority -100 \; }

    nft add rule ip slowdns_classic prerouting udp dport 53 redirect to "$PORT" 2>/dev/null || true

    mkdir -p /etc/nftables.d
    nft list table ip slowdns_classic > /etc/nftables.d/slowdns_classic.nft
    grep -q 'include "/etc/nftables.d/*.nft"' /etc/nftables.conf || \
        echo 'include "/etc/nftables.d/*.nft"' >> /etc/nftables.conf

    systemctl enable nftables >/dev/null 2>&1 || true
}

iface=$(wait_iface)
ip link set dev "$iface" mtu 1180 || true

setup_nftables

NS=$(cat "$CONFIG_FILE")
exec "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" "$NS" 0.0.0.0:22
EOF

chmod +x /usr/local/bin/slowdns-start.sh
}

# --- systemd ---
create_systemd_service() {
cat <<EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS Classic Tunnel
After=network-online.target nftables.service
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/slowdns-start.sh
Restart=always
RestartSec=3
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE
LimitNOFILE=1048576
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable slowdns
systemctl restart slowdns
}

# --- MAIN ---
main() {
    check_root
    install_dependencies
    install_slowdns_bin
    install_fixed_keys
    disable_systemd_resolved

    read -rp "Mode NS [auto/man] : " MODE
    [[ "$MODE" == "auto" ]] && generate_ns_cloudflare || read -rp "NS : " NAMESERVER && echo "$NAMESERVER" > "$CONFIG_FILE"

    configure_iptables
    create_wrapper_script
    create_systemd_service

    echo "✔ SlowDNS classique installé sans conflit"
}

main "$@"
