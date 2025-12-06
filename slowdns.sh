#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=53
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
CF_API_TOKEN="TON_CLOUDFLARE_API_TOKEN"
CF_ZONE_ID="TON_CLOUDFLARE_ZONE_ID"
DOMAIN_ROOT="kingdom.qzz.io"  # Ton domaine Cloudflare principal

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

check_root() {
    [ "$EUID" -ne 0 ] && { echo "Ce script doit être exécuté en root."; exit 1; }
}

install_dependencies() {
    log "Installation des dépendances..."
    apt update -y
    apt install -y curl jq python3 python3-venv iptables iptables-persistent tcpdump
}

setup_python_env() {
    mkdir -p "$SLOWDNS_DIR/venv"
    python3 -m venv "$SLOWDNS_DIR/venv"
    source "$SLOWDNS_DIR/venv/bin/activate"
    pip install --upgrade pip
    pip install cloudflare
}

create_cf_records() {
    local subdomain=$1
    local ip=$2
    log "Création de l'enregistrement A et NS sur Cloudflare..."

    # Vérifie si A record existe déjà
    existing=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?type=A&name=$subdomain" \
        -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" | jq -r '.result | length')
    if [ "$existing" -eq 0 ]; then
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$subdomain\",\"content\":\"$ip\",\"ttl\":120,\"proxied\":false}" >/dev/null
    fi

    # NS record
    ns_name="$subdomain"
    ns_content="$DOMAIN_ROOT"
    existing_ns=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?type=NS&name=$ns_name" \
        -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" | jq -r '.result | length')
    if [ "$existing_ns" -eq 0 ]; then
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"NS\",\"name\":\"$ns_name\",\"content\":\"$ns_content\",\"ttl\":120}" >/dev/null
    fi
    log "Enregistrements Cloudflare créés : $subdomain -> $ip"
}

generate_ns() {
    local ip=$1
    sub="tun-$(head /dev/urandom | tr -dc a-z0-9 | head -c6)"
    fqdn="$sub.$DOMAIN_ROOT"
    create_cf_records "$fqdn" "$ip"
    echo "$fqdn"
}

install_dnstt() {
    [ ! -x "$SLOWDNS_BIN" ] && {
        log "Téléchargement DNSTT..."
        curl -L -o "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
        chmod +x "$SLOWDNS_BIN"
    }
}

setup_keys() {
    mkdir -p "$SLOWDNS_DIR"
    echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
    echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
    chmod 600 "$SERVER_KEY"
    chmod 644 "$SERVER_PUB"
}

create_wrapper() {
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
}

create_systemd_service() {
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
}

main() {
    check_root
    install_dependencies
    setup_python_env
    install_dnstt
    setup_keys
    create_wrapper

    read -rp "Choisissez le mode d'installation [auto/man] : " MODE
    if [[ "$MODE" == "auto" ]]; then
        IP=$(curl -s ipv4.icanhazip.com)
        NS=$(generate_ns "$IP")
    else
        read -rp "Entrez le NameServer (NS) existant : " NS
    fi

    echo "$NS" > "$CONFIG_FILE"
    log "NS configuré : $NS"

    create_systemd_service
    log "SlowDNS installé et démarré avec NS : $NS"
}

main "$@"
