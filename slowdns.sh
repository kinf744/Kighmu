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

# -------------------------------------------------------
check_root() {
    [ "$EUID" -ne 0 ] && { echo "❌ Ce script doit être exécuté en root."; exit 1; }
}

install_dependencies() {
    log "Installation des dépendances..."
    apt update -q
    apt install -y iptables iptables-persistent curl jq python3 python3-venv python3-pip
}

setup_python_env() {
    python3 -m venv "$SLOWDNS_DIR/venv"
    source "$SLOWDNS_DIR/venv/bin/activate"
    pip install --upgrade pip
    pip install cloudflare flask
}

install_dnstt_bin() {
    if [ ! -x "$SLOWDNS_BIN" ]; then
        log "Téléchargement du binaire DNSTT..."
        curl -L -o "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
        chmod +x "$SLOWDNS_BIN"
        [ ! -x "$SLOWDNS_BIN" ] && { echo "❌ Échec téléchargement DNSTT"; exit 1; }
    fi
}

verify_cloudflare_token() {
    log "Vérification du token Cloudflare..."
    RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")
    echo "$RESPONSE" | grep -q '"status":"active"' || { echo "❌ Token Cloudflare invalide."; exit 1; }
    log_debug "$RESPONSE"
}

verify_cloudflare_zone() {
    log "Vérification zone Cloudflare..."
    ZONE_INFO=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID" \
        -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")
    echo "$ZONE_INFO" | grep -q '"success":true' || { echo "❌ Zone Cloudflare invalide."; exit 1; }
    ZONE_NAME=$(echo "$ZONE_INFO" | jq -r .result.name)
    [[ "$DOMAIN" != *"$ZONE_NAME" ]] && { echo "❌ Domaine '$DOMAIN' n'appartient pas à la zone '$ZONE_NAME'"; exit 1; }
    log "✔️ Zone valide : $ZONE_NAME"
}

configure_sysctl() {
    log "Optimisation sysctl..."
    sed -i '/# Optimisations SlowDNS/,+10d' /etc/sysctl.conf || true
    cat <<EOF >> /etc/sysctl.conf

# Optimisations SlowDNS
net.core.rmem_max=8388608
net.core.wmem_max=8388608
net.core.rmem_default=262144
net.core.wmem_default=262144
net.core.optmem_max=25165824
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384
net.ipv4.ip_forward=1
EOF
    sysctl -p
}

configure_iptables() {
    log "Configuration iptables..."
    if ! iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT &>/dev/null; then
        iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
    fi
    iptables-save > /etc/iptables/rules.v4
    systemctl enable netfilter-persistent
    systemctl restart netfilter-persistent
}

create_keys() {
    mkdir -p "$SLOWDNS_DIR"
    echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
    echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
    chmod 600 "$SERVER_KEY"
    chmod 644 "$SERVER_PUB"
}

setup_ns_record() {
    read -rp "Mode installation [auto/man] : " MODE
    MODE=${MODE,,}
    if [[ "$MODE" == "auto" ]]; then
        VPS_IP=$(curl -s ipv4.icanhazip.com)
        SUB_A="vpn-$(date +%s | sha256sum | head -c 6)"
        FQDN_A="$SUB_A.$DOMAIN"
        log "Création enregistrement A : $FQDN_A -> $VPS_IP"
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"$FQDN_A\",\"content\":\"$VPS_IP\",\"ttl\":1,\"proxied\":false}" \
            | log_debug
        SUB_NS="ns-$(date +%s | sha256sum | head -c 6)"
        DOMAIN_NS="$SUB_NS.$DOMAIN"
        log "Création enregistrement NS : $DOMAIN_NS -> $FQDN_A"
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
            --data "{\"type\":\"NS\",\"name\":\"$DOMAIN_NS\",\"content\":\"$FQDN_A\",\"ttl\":1}" \
            | log_debug
    elif [[ "$MODE" == "man" ]]; then
        read -rp "Entrez le NS : " DOMAIN_NS
    else
        echo "❌ Mode invalide." && exit 1
    fi

    # Vérification que le NS n'est pas vide
    [ -z "$DOMAIN_NS" ] && { echo "❌ NS vide, installation annulée"; exit 1; }

    echo "$DOMAIN_NS" > "$CONFIG_FILE"
    log "NS utilisé : $DOMAIN_NS"
}

create_wrapper_script() {
    cat <<'EOF' > /usr/local/bin/slowdns-start.sh
#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=53
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"

# Lecture du NS
NS=$(cat "$CONFIG_FILE")
ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
[ -z "$ssh_port" ] && ssh_port=22

exec "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" "$NS" 0.0.0.0:$ssh_port
EOF

    chmod 755 /usr/local/bin/slowdns-start.sh
}

create_systemd_service() {
    cat <<EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS Tunnel (DNSTT)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/slowdns-start.sh
Restart=always
RestartSec=3
StartLimitBurst=5
StartLimitIntervalSec=60
StandardOutput=append:/var/log/slowdns.log
StandardError=append:/var/log/slowdns.log
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable slowdns.service
    systemctl restart slowdns.service
}

# ----------------- MAIN -----------------
main() {
    check_root
    install_dependencies
    setup_python_env
    install_dnstt_bin
    verify_cloudflare_token
    verify_cloudflare_zone
    configure_sysctl
    configure_iptables
    create_keys
    setup_ns_record
    create_wrapper_script
    create_systemd_service

    # ---------------- Message final coloré ----------------
    GREEN="\e[32m"
    YELLOW="\e[33m"
    RESET="\e[0m"

    PUB_KEY=$(cat "$SERVER_PUB")
    DOMAIN_NS=$(cat "$CONFIG_FILE")

    echo -e ""
    echo -e "${GREEN}+--------------------------------------------+${RESET}"
    echo -e "${GREEN}|           SLOWDNS DNSTT CONFIG             |${RESET}"
    echo -e "${GREEN}+--------------------------------------------+${RESET}"
    echo -e "${YELLOW}Port UDP utilisé  : ${RESET}$PORT"
    echo -e "${YELLOW}NameServer (NS)   : ${RESET}$DOMAIN_NS"
    echo -e "${YELLOW}Clé publique      : ${RESET}$PUB_KEY"
    echo -e "${GREEN}+--------------------------------------------+${RESET}"
    echo -e ""
    echo -e "${GREEN}✔️ Installation terminée avec succès !${RESET}"
}

main "$@"
