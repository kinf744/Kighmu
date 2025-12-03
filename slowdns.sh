#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=53
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Ce script doit être exécuté en root." >&2
        exit 1
    fi
}

install_dependencies() {
    log "Installation des dépendances..."
    apt-get update -q
    apt-get install -y iptables iptables-persistent curl tcpdump
}

install_slowdns_bin() {
    if [ ! -x "$SLOWDNS_BIN" ]; then
        log "Téléchargement du binaire officiel DNSTT depuis dnstt.network..."
        curl -L -o "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
        chmod +x "$SLOWDNS_BIN"

        # Vérification que le binaire n'est pas vide
        if [ ! -s "$SLOWDNS_BIN" ]; then
            echo "ERREUR : le binaire DNSTT téléchargé est vide !" >&2
            rm -f "$SLOWDNS_BIN"
            exit 1
        fi
        log "Binaire DNSTT téléchargé et prêt."
    fi
}

install_fixed_keys() {
    mkdir -p "$SLOWDNS_DIR"
    echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
    echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
    chmod 600 "$SERVER_KEY"
    chmod 644 "$SERVER_PUB"
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
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_fin_timeout=10
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_mtu_probing=1
net.ipv4.ip_forward=1
EOF
    sysctl -p
}

disable_systemd_resolved() {
    log "Désactivation de systemd-resolved..."
    systemctl stop systemd-resolved
    systemctl disable systemd-resolved
    rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
}

configure_iptables() {
    log "Configuration iptables..."
    if ! iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT &>/dev/null; then
        iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
        log "Règle ajoutée : ACCEPT udp dport $PORT"
    fi
    iptables-save > /etc/iptables/rules.v4
    systemctl enable netfilter-persistent
    systemctl restart netfilter-persistent
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

log "Recherche de l'interface réseau..."
interface=$(wait_for_interface)
log "Interface utilisée : $interface"

log "Réglage MTU à 1400..."
ip link set dev "$interface" mtu 1400 || log "Échec réglage MTU"

log "Démarrage DNSTT (SlowDNS amélioré)..."
NS=$(cat "$CONFIG_FILE")
ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
[ -z "$ssh_port" ] && ssh_port=22

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
    install_dependencies
    install_slowdns_bin
    install_fixed_keys
    disable_systemd_resolved

    read -rp "Entrez le NameServer (NS) (ex: ns.example.com) : " NAMESERVER
    mkdir -p "$SLOWDNS_DIR"
    echo "$NAMESERVER" > "$CONFIG_FILE"
    log "NameServer enregistré."

    configure_sysctl
    configure_iptables
    create_wrapper_script
    create_systemd_service

    cat <<EOF > /etc/slowdns/slowdns.env
NS=$NAMESERVER
PUB_KEY=$(cat "$SERVER_PUB")
PRIV_KEY=$(cat "$SERVER_KEY")
EOF
    chmod 600 /etc/slowdns/slowdns.env

    log "Installation SlowDNS (DNSTT) terminée."
}

main "$@"
