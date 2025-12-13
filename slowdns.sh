#!/bin/bash
set -euo pipefail

# --- Configuration principale ---
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# --- Détection IP automatique IPv4/IPv6 ---
detect_ip_addresses() {
    local ipv4="" ipv6=""
    
    # Détection IPv4 globale
    ipv4=$(ip -4 addr show scope global | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)
    
    # Détection IPv6 globale
    ipv6=$(ip -6 addr show scope global | awk '/inet6 /{print $2}' | cut -d/ -f1 | head -n1 | grep -v '^fe80')
    
    echo "ipv4=$ipv4"
    echo "ipv6=$ipv6"
}

get_main_ip() {
    local ipv4 ipv6
    eval $(detect_ip_addresses)
    
    if [[ -n "$ipv4" ]]; then
        echo "$ipv4"
        return 0
    elif [[ -n "$ipv6" ]]; then
        echo "$ipv6"
        return 0
    else
        echo "127.0.0.1"
        return 1
    fi
}

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
    apt-get install -y iptables iptables-persistent wget tcpdump curl jq iproute2
}

# --- Installation SlowDNS binaire ---
install_slowdns_bin() {
    if [ ! -x "$SLOWDNS_BIN" ]; then
        log "Téléchargement du binaire SlowDNS..."
        wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
        chmod +x "$SLOWDNS_BIN"
        if [ ! -x "$SLOWDNS_BIN" ]; then
            echo "ERREUR : Échec du téléchargement du binaire SlowDNS." >&2
            exit 1
        fi
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

# --- Sysctl optimisations ---
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
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_fin_timeout=10
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_mtu_probing=1
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
EOF
    sysctl -p
}

# --- Désactivation systemd-resolved ---
disable_systemd_resolved() {
    log "Tentative de désactivation du stub DNS systemd-resolved..."
    systemctl stop systemd-resolved || true
    systemctl disable systemd-resolved || true

    if [ -w /etc/resolv.conf ] || chattr -i /etc/resolv.conf 2>/dev/null; then
        cat <<EOF > /etc/resolv.conf
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 2606:4700:4700::1111
nameserver 2606:4700:4700::1001
options timeout:1 attempts:1
EOF
        log "/etc/resolv.conf mis à jour avec succès"
    else
        log "Impossible de modifier /etc/resolv.conf, continuer l'installation"
    fi
}

# --- IPTables IPv4/IPv6 ---
configure_iptables() {
    log "Configuration du pare-feu via iptables (IPv4)..."
    if ! iptables -C INPUT -p udp --dport 53 -j ACCEPT &>/dev/null; then
        iptables -I INPUT -p udp --dport 53 -j ACCEPT
    fi
    if ! iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT &>/dev/null; then
        iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
    fi
    
    log "Configuration du pare-feu via ip6tables (IPv6)..."
    if command -v ip6tables >/dev/null 2>&1; then
        if ! ip6tables -C INPUT -p udp --dport 53 -j ACCEPT &>/dev/null; then
            ip6tables -I INPUT -p udp --dport 53 -j ACCEPT
        fi
        if ! ip6tables -C INPUT -p udp --dport "$PORT" -j ACCEPT &>/dev/null; then
            ip6tables -I INPUT -p udp --dport "$PORT" -j ACCEPT
        fi
    fi
    
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
    systemctl enable netfilter-persistent
    systemctl restart netfilter-persistent
    log "Persistance iptables/ip6tables activée."
}

# --- Cloudflare NS auto IPv4/IPv6 ---
CF_API_TOKEN="7mn4LKcZARvdbLlCVFTtaX7LGM2xsnyjHkiTAt37"
CF_ZONE_ID="7debbb8ea4946898a889c4b5745ab7eb"
DOMAIN="kingom.ggff.net"

generate_ns_cloudflare() {
    log "Génération automatique du NameServer via Cloudflare..."
    eval $(detect_ip_addresses)
    
    # Priorité IPv4, fallback IPv6
    if [[ -n "$ipv4" ]]; then
        VPS_IP="$ipv4"
        RECORD_TYPE="A"
        log "IPv4 détectée : $VPS_IP"
    elif [[ -n "$ipv6" ]]; then
        VPS_IP="$ipv6"
        RECORD_TYPE="AAAA"
        log "IPv6 détectée : $VPS_IP"
    else
        log "Aucune IP publique détectée"
        exit 1
    fi
    
    SUB_A="vpn-$(date +%s | sha256sum | head -c 6)"
    FQDN_A="$SUB_A.$DOMAIN"

    log "Création du $RECORD_TYPE record : $FQDN_A -> $VPS_IP"
    RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "{"type":"$RECORD_TYPE","name":"$FQDN_A","content":"$VPS_IP","ttl":120,"proxied":false}")

    if ! echo "$RESPONSE" | grep -q '"success":true'; then
        log "Erreur lors de la création de l'$RECORD_TYPE record Cloudflare"
        exit 1
    fi

    SUB_NS="ns-$(date +%s | sha256sum | head -c 6)"
    NS="$SUB_NS.$DOMAIN"
    log "Création du NS record : $NS -> $FQDN_A"

    RESPONSE_NS=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "{"type":"NS","name":"$NS","content":"$FQDN_A","ttl":120}")

    if ! echo "$RESPONSE_NS" | grep -q '"success":true'; then
        log "Erreur lors de la création du NS record Cloudflare"
        exit 1
    fi

    echo "$NS" > "$CONFIG_FILE"
    cat <<EOF > "$SLOWDNS_DIR/slowdns.env"
NS=$NS
PUB_KEY=$(cat "$SERVER_PUB")
PRIV_KEY=$(cat "$SERVER_KEY")
VPS_IP=$VPS_IP
RECORD_TYPE=$RECORD_TYPE
EOF
    chmod 600 "$CONFIG_FILE" "$SLOWDNS_DIR/slowdns.env"
    log "NameServer Cloudflare généré automatiquement : $NS ($RECORD_TYPE)"
}

# --- Wrapper SlowDNS IPv4/IPv6 ---
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

wait_for_interface() {
    interface=""
    while [ -z "$interface" ]; do
        interface=$(ip -o link show up | awk -F': ' '{print $2}' \
                    | grep -v '^lo$' \
                    | grep -vE '^(docker|veth|br|virbr|tun|tap|wl|vmnet|vboxnet)' \
                    | head -n1)
        [ -z "$interface" ] && sleep 2
    done
    echo "$interface"
}

setup_iptables() {
    interface="$1"
    if ! iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT &>/dev/null; then
        iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
    fi
    if ! iptables -t nat -C PREROUTING -i "$interface" -p udp --dport 53 -j REDIRECT --to-ports "$PORT" &>/dev/null; then
        iptables -t nat -I PREROUTING -i "$interface" -p udp --dport 53 -j REDIRECT --to-ports "$PORT"
    fi
    
    # IPv6 si disponible
    if command -v ip6tables >/dev/null 2>&1; then
        if ! ip6tables -C INPUT -p udp --dport "$PORT" -j ACCEPT &>/dev/null; then
            ip6tables -I INPUT -p udp --dport "$PORT" -j ACCEPT
        fi
        if ! ip6tables -t nat -C PREROUTING -i "$interface" -p udp --dport 53 -j REDIRECT --to-ports "$PORT" &>/dev/null; then
            ip6tables -t nat -I PREROUTING -i "$interface" -p udp --dport 53 -j REDIRECT --to-ports "$PORT"
        fi
    fi
}

log "Attente de l'interface réseau..."
interface=$(wait_for_interface)
log "Interface détectée : $interface"

log "Réglage MTU à 1400 pour éviter la fragmentation DNS..."
ip link set dev "$interface" mtu 1400 || log "Échec réglage MTU, continuer"

log "Application des règles iptables/ip6tables..."
setup_iptables "$interface"

log "Démarrage du serveur SlowDNS..."
NS=$(cat "$CONFIG_FILE")
ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
[ -z "$ssh_port" ] && ssh_port=22

# Écoute IPv4 + IPv6 si disponibles
exec "$SLOWDNS_BIN" \
  -udp :$PORT \
  -privkey-file "$SERVER_KEY" \
  "$NS" \
  0.0.0.0:$ssh_port \
  [::]:$ssh_port
EOF
    chmod +x /usr/local/bin/slowdns-start.sh
}

# --- systemd service ---
create_systemd_service() {
    cat <<EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS Server Tunnel (IPv4/IPv6)
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/fisabiliyusri/SLDNS

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
Nice=0
CPUSchedulingPolicy=other
IOSchedulingClass=best-effort
IOSchedulingPriority=4
TimeoutStartSec=20
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable slowdns.service
    systemctl restart slowdns.service
}

# --- Main ---
main() {
    check_root
    install_dependencies
    install_slowdns_bin
    install_fixed_keys
    disable_systemd_resolved

    read -rp "Mode d'installation du NS [auto/man] : " MODE
    MODE=${MODE,,}

    if [[ "$MODE" == "auto" ]]; then
        generate_ns_cloudflare
        NAMESERVER=$(cat "$CONFIG_FILE")
    else
        read -rp "Entrez le NameServer (NS) (ex: ns.example.com) : " NAMESERVER
        if [[ -z "$NAMESERVER" ]]; then
            echo "NameServer invalide." >&2
            exit 1
        fi
        echo "$NAMESERVER" > "$CONFIG_FILE"
        eval $(detect_ip_addresses)
        cat <<EOF > "$SLOWDNS_DIR/slowdns.env"
NS=$NAMESERVER
PUB_KEY=$(cat "$SERVER_PUB")
PRIV_KEY=$(cat "$SERVER_KEY")
VPS_IP=${ipv4:-$ipv6}
EOF
        chmod 600 "$CONFIG_FILE" "$SLOWDNS_DIR/slowdns.env"
        log "NameServer enregistré manuellement : $NAMESERVER"
    fi

    configure_sysctl
    configure_iptables
    create_wrapper_script
    create_systemd_service

    PUB_KEY=$(cat "$SERVER_PUB")
    VPS_IP=$(get_main_ip)
    echo ""
    echo "+--------------------------------------------+"
    echo "|          CONFIGURATION SLOWDNS             |"
    echo "+--------------------------------------------+"
    echo ""
    echo "IP publique  : $VPS_IP"
    echo "Clé publique : $PUB_KEY"
    echo "NameServer   : $NAMESERVER"
    echo ""
    echo "MTU du tunnel : 1400"
    log "Installation et configuration SlowDNS terminées."
}

main "$@"
