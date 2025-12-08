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
SSH_PORT=22

# --- Cloudflare API ---
CF_API_TOKEN="7mn4LKcZARvdbLlCVFTtaX7LGM2xsnyjHkiTAt37"
CF_ZONE_ID="7debbb8ea4946898a889c4b5745ab7eb"

# Couleurs
RED='\u001B[0;31m'; GREEN='\u001B[0;32m'; YELLOW='\u001B[0;33m'; CYAN='\u001B[0;36m'; NC='\u001B[0m'
log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${GREEN}$*${NC}"; }
error() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${RED}ERREUR: $*${NC}" >&2; exit 1; }

if [ "$EUID" -ne 0 ]; then error "Exécuter en root"; fi

mkdir -p "$SLOWDNS_DIR"

main() {
    log "✅ Installation SlowDNS + nftables (PORT $PORT)"

    # Dépendances
    apt update -y
    apt install -y nftables tcpdump curl jq python3 python3-pip

    # DNSTT
    [ -x "$SLOWDNS_BIN" ] || {
        log "📥 dnstt-server-linux-amd64..."
        curl -L -o "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
        chmod +x "$SLOWDNS_BIN"
    }

    # Cloudflare NS (votre logique)
    read -rp "${CYAN}Mode [auto/man]: ${NC}" MODE
    MODE=${MODE,,}
    
    if [[ "$MODE" == "auto" ]]; then
        if [[ ! -f "$ENV_FILE" || "$(grep ENV_MODE "$ENV_FILE" | cut -d= -f2)" != "auto" ]]; then
            generate_ns_auto
        else
            source "$ENV_FILE"
            log "NS auto: $NS"
        fi
    elif [[ "$MODE" == "man" ]]; then
        read -rp "${CYAN}NS man: ${NC}" NS
        echo -e "NS=$NS
ENV_MODE=man" > "$ENV_FILE"
        chmod 600 "$ENV_FILE"
        log "NS manuel: $NS"
    else
        error "Mode invalide"
    fi

    echo "$NS" > "$CONFIG_FILE"
    log "NS actif: $NS"

    generate_ns_auto() {
        DOMAIN="kingom.ggff.net"
        VPS_IP=$(curl -s ipv4.icanhazip.com)
        SUB_A="vpn-$(date +%s | sha256sum | head -c 6)"
        FQDN_A="$SUB_A.$DOMAIN"
        
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
            --data "{"type":"A","name":"$FQDN_A","content":"$VPS_IP","ttl":120,"proxied":false}" | jq .
        
        SUB_NS="ns-$(date +%s | sha256sum | head -c 6)"
        NS="$SUB_NS.$DOMAIN"
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
            --data "{"type":"NS","name":"$NS","content":"$FQDN_A","ttl":120}" | jq .
        
        echo -e "NS=$NS
ENV_MODE=auto" > "$ENV_FILE"
        chmod 600 "$ENV_FILE"
        log "NS auto: $NS"
    }

    # Clés fixes
    echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
    echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
    chmod 600 "$SERVER_KEY" && chmod 644 "$SERVER_PUB"

    # Kernel tuning
    cat <<EOF > /etc/sysctl.d/99-slowdns.conf
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=524288
net.core.wmem_default=524288
net.core.netdev_max_backlog=250000
net.core.somaxconn=4096
net.ipv4.udp_rmem_min=32768
net.ipv4.udp_wmem_min=32768
net.ipv4.tcp_fin_timeout=10
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_mtu_probing=1
net.ipv4.ip_forward=1
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
EOF
    sysctl -p /etc/sysctl.d/99-slowdns.conf

    # systemd-resolved off
    systemctl disable --now systemd-resolved || true
    rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" > /etc/resolv.conf

    # ✅ NFTABLES CORRIGÉ (ip6 family + dnat ip)
    cat > /etc/nftables.conf << 'NFT'
#!/usr/sbin/nft -f
flush ruleset

table ip slowdns_nat {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        udp dport 53 dnat ip to 127.0.0.1:5300
    }
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
    }
}

table ip slowdns_filter {
    chain forward {
        type filter hook forward priority filter; policy drop;
        ct state {established,related} accept
        ip daddr 127.0.0.1 tcp dport 22 accept
        udp dport 5300 accept
        log prefix "SLOWDNS-DROP: " drop
    }
    chain input {
        type filter hook input priority filter; policy accept;
        udp dport {53, 5300} accept
        ct state {established,related} accept
    }
}
NFT

    nft -f /etc/nftables.conf && log "✅ nftables OK: UDP/53 → 127.0.0.1:$PORT"
    systemctl enable --now nftables

    # Wrapper SlowDNS
    cat <<'EOF' > /usr/local/bin/slowdns-start.sh
#!/bin/bash
set -euo pipefail
SLOWDNS_DIR="/etc/slowdns"; SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300; CONFIG_FILE="$SLOWDNS_DIR/ns.conf"; SERVER_KEY="$SLOWDNS_DIR/server.key"

wait_for_interface() {
    ip -o link show up | awk -F': ' '{print $2}' | grep -v '^lo$' | grep -vE '^(docker|veth|br|virbr|tun|tap|wl|vmnet|vboxnet)' | head -n1
}

iface=$(wait_for_interface)
[ -n "$iface" ] && ip link set dev "$iface" mtu 1400

NS=$(cat "$CONFIG_FILE")
ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2 || echo 22)

exec nice -n -5 "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" "$NS" 0.0.0.0:$ssh_port
EOF
    chmod +x /usr/local/bin/slowdns-start.sh

    # Service SlowDNS
    cat > /etc/systemd/system/slowdns.service <<EOF
[Unit]
Description=SlowDNS (DNSTT) + nftables
After=network-online.target nftables.service
Wants=network-online.target nftables.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/slowdns-start.sh
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
LimitNPROC=65535
TasksMax=infinity
StandardOutput=file:/var/log/slowdns.log
StandardError=file:/var/log/slowdns.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nftables slowdns.service
    systemctl restart nftables slowdns.service

    log "🚀 TERMINÉ! NS: $NS"
    log "🔍 nft list ruleset"
    log "📊 tail -f /var/log/slowdns.log"
    log "🧪 tcpdump -i any udp port 53 -c 10"
}

main "$@"
