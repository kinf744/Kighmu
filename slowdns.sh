#!/bin/bash
set -euo pipefail

# -------------------- CONFIG --------------------
SLOWDNS_DIR="/etc/slowdns"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
MTU_VALUE=1440

# -------------------- LOG --------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# -------------------- CHECK ROOT --------------------
check_root() {
    [[ "$EUID" -ne 0 ]] && { echo "Ce script doit être exécuté en root ou via sudo." >&2; exit 1; }
}

# -------------------- DEPENDENCIES --------------------
install_dependencies() {
    log "Mise à jour des paquets et installation des dépendances..."
    apt-get update -q
    apt-get install -y iptables ufw tcpdump wget
}

# -------------------- NETWORK INTERFACE --------------------
get_active_interface() {
    ip -o link show up | awk -F': ' '{print $2}' \
        | grep -v '^lo$' \
        | grep -vE '^(docker|veth|br|virbr|tun|tap|wl|vmnet|vboxnet)' \
        | head -n1
}

# -------------------- KEYS --------------------
install_fixed_keys() {
    mkdir -p "$SLOWDNS_DIR"
    echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
    echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
    chmod 600 "$SERVER_KEY"
    chmod 644 "$SERVER_PUB"
}

# -------------------- STOP OLD INSTANCE --------------------
stop_old_instance() {
    if pgrep -f "sldns-server" >/dev/null; then
        log "Arrêt de l'ancienne instance SlowDNS..."
        fuser -k "${PORT}/udp" || true
        pkill -f "sldns-server" || true
        sleep 2
    fi
    iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null || true
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports "$PORT" 2>/dev/null || true
}

# -------------------- IPTABLES --------------------
setup_iptables() {
    local iface="$1"
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4.bak || true

    log "Ajout règle iptables pour UDP port $PORT"
    iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT

    log "Redirection DNS UDP 53 → $PORT sur interface $iface"
    iptables -t nat -I PREROUTING -i "$iface" -p udp --dport 53 -j REDIRECT --to-ports "$PORT"

    iptables-save > /etc/iptables/rules.v4
}

# -------------------- IP FORWARD --------------------
enable_ip_forwarding() {
    sysctl -w net.ipv4.ip_forward=1
    grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
}

# -------------------- SYSCTL OPTIMIZATION --------------------
optimize_sysctl() {
    log "Application des optimisations SYSCTL avancées pour SlowDNS..."
    sed -i '/# Optimisations SlowDNS/,+20d' /etc/sysctl.conf || true

    cat <<EOF >> /etc/sysctl.conf

# Optimisations SlowDNS
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.core.rmem_default=33554432
net.core.wmem_default=33554432
net.core.optmem_max=33554432
net.ipv4.udp_rmem_min=65536
net.ipv4.udp_wmem_min=65536
net.ipv4.tcp_fin_timeout=5
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_tw_recycle=1
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_probes=5
net.ipv4.tcp_keepalive_intvl=10
EOF

    sysctl -p
}

# -------------------- SYSTEMD SERVICE --------------------
create_systemd_service() {
    local ssh_port NS SERVICE_PATH
    ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
    [ -z "$ssh_port" ] && ssh_port=22
    NS=$(cat "$CONFIG_FILE")
    SERVICE_PATH="/etc/systemd/system/slowdns.service"

    log "Création du service systemd slowdns.service..."
    cat <<EOF > "$SERVICE_PATH"
[Unit]
Description=SlowDNS Server Tunnel
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=$SLOWDNS_BIN -udp :$PORT -privkey-file $SERVER_KEY $NS 0.0.0.0:$ssh_port
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=slowdns-server
LimitNOFILE=1048576
Nice=-5
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=99

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable slowdns.service
    systemctl restart slowdns.service
    log "Service SlowDNS activé et démarré avec succès."
}

# -------------------- MAIN --------------------
main() {
    check_root
    install_dependencies
    mkdir -p "$SLOWDNS_DIR"
    stop_old_instance

    read -rp "Entrez le NameServer (NS) : " NAMESERVER
    [[ -z "$NAMESERVER" ]] && { echo "NameServer invalide." >&2; exit 1; }
    echo "$NAMESERVER" > "$CONFIG_FILE"
    log "NameServer enregistré : $CONFIG_FILE"

    if [ ! -x "$SLOWDNS_BIN" ]; then
        log "Téléchargement du binaire SlowDNS..."
        wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
        chmod +x "$SLOWDNS_BIN"
        [[ ! -x "$SLOWDNS_BIN" ]] && { echo "ERREUR : Échec du téléchargement du binaire." >&2; exit 1; }
    fi

    install_fixed_keys
    local PUB_KEY
    PUB_KEY=$(cat "$SERVER_PUB")

    local interface
    interface=$(get_active_interface)
    [[ -z "$interface" ]] && { echo "Échec détection interface réseau."; exit 1; }
    log "Interface réseau détectée : $interface"

    log "Réglage MTU sur interface $interface à $MTU_VALUE..."
    ip link set dev "$interface" mtu "$MTU_VALUE"

    optimize_sysctl
    setup_iptables "$interface"
    enable_ip_forwarding
    create_systemd_service

    command -v ufw >/dev/null 2>&1 && { log "Ouverture du port UDP $PORT avec UFW."; ufw allow "$PORT"/udp; ufw reload; }

    echo ""
    echo "+--------------------------------------------+"
    echo "|          CONFIGURATION SLOWDNS             |"
    echo "+--------------------------------------------+"
    echo "Clé publique : $PUB_KEY"
    echo "NameServer  : $NAMESERVER"
    echo ""
    log "Installation et configuration SlowDNS terminées avec optimisations avancées."
}

main "$@"
