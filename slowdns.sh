#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=53
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"

# Infos Cloudflare
CF_API_TOKEN="TON_TOKEN_CLOUDFLARE"
CF_ZONE_ID="TON_ZONE_ID_CLOUDFLARE"
DOMAIN="kingdom.qzz.io"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Ce script doit être exécuté en root." >&2
        exit 1
    fi
}

install_deps() {
    log "Installation des dépendances..."
    apt update -y
    apt install -y curl jq python3 python3-pip
    pip3 install cloudflare
}

install_dnstt() {
    if [ ! -x "$SLOWDNS_BIN" ]; then
        log "Téléchargement du binaire DNSTT..."
        curl -L -o "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
        chmod +x "$SLOWDNS_BIN"
    fi
}

generate_ids() {
    RANDOM_ID=$(tr -dc a-z0-9 </dev/urandom | head -c6)
    SUB="tun-$RANDOM_ID"
    NS_SUB="ns-$SUB"
    FQDN="$SUB.$DOMAIN"
    NS_FQDN="$NS_SUB.$DOMAIN"
}

create_cloudflare_records() {
    log "Création des enregistrements DNS sur Cloudflare..."
    IP=$(curl -s ipv4.icanhazip.com)

    # Création A
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$SUB\",\"content\":\"$IP\",\"ttl\":120,\"proxied\":false}" >/dev/null

    # Création NS
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"NS\",\"name\":\"$NS_SUB\",\"content\":\"$FQDN\",\"ttl\":120}" >/dev/null

    echo "$NS_FQDN" > "$CONFIG_FILE"
    log "DNS configuré : $NS_FQDN"
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
PORT=53
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
NS=$(cat "$CONFIG_FILE")
ssh_port=22
exec "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" "$NS" 0.0.0.0:$ssh_port
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
    install_deps
    install_dnstt
    setup_keys
    create_wrapper

    read -rp "Choisissez le mode d'installation [auto/man] : " MODE

    if [[ "$MODE" == "auto" ]]; then
        log "Mode AUTO sélectionné : génération automatique du NS"
        generate_ids
        create_cloudflare_records
    else
        read -rp "Entrez le NameServer (NS) à utiliser : " NS_MAN
        echo "$NS_MAN" > "$CONFIG_FILE"
        log "NS manuel utilisé : $NS_MAN"
    fi

    create_systemd_service
    log "SlowDNS installé et démarré avec NS : $(cat $CONFIG_FILE)"
}

main "$@"
