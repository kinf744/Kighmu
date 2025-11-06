#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
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
    apt-get install -y iptables iptables-persistent wget tcpdump
}

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

install_fixed_keys() {
    mkdir -p "$SLOWDNS_DIR"
    echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
    echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
    chmod 600 "$SERVER_KEY"
    chmod 644 "$SERVER_PUB"
}

disable_systemd_resolved() {
    log "Libération du port 53 localement..."
    systemctl stop systemd-resolved || true
    systemctl disable systemd-resolved || true
    rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
}

configure_sysctl() {
    log "Optimisation sysctl..."
    sed -i '/# Optimisations SlowDNS/,+20d' /etc/sysctl.conf || true
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
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_no_metrics_save=1
EOF
    sysctl -p
}

configure_iptables() {
    log "Configuration du pare-feu via iptables..."
    if ! iptables -C INPUT -p udp --dport 53 -j ACCEPT &>/dev/null; then
        iptables -I INPUT -p udp --dport 53 -j ACCEPT
    fi
    iptables-save > /etc/iptables/rules.v4
    systemctl enable netfilter-persistent
    systemctl restart netfilter-persistent
    log "Persistance iptables activée via netfilter-persistent."
}

create_wrapper_script() {
    cat <<'EOF' > /usr/local/bin/slowdns-start.sh
#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=53
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "Initialisation du service SlowDNS..."

# Récupération du NS et du port SSH
NS=$(cat "$CONFIG_FILE")
ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
[ -z "$ssh_port" ] && ssh_port=22

# Lancement du serveur en mode UDP DNS correct
log "Démarrage du serveur SlowDNS sur le port $PORT..."
exec "$SLOWDNS_BIN" -udp :$PORT -privkey "$SERVER_KEY" -domain "$NS" -forward 127.0.0.1:$ssh_port
EOF

    chmod +x /usr/local/bin/slowdns-start.sh
}

create_systemd_service() {
    cat <<EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS Server Tunnel
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

main() {
    check_root
    install_dependencies
    install_slowdns_bin
    install_fixed_keys
    disable_systemd_resolved

    read -rp "Entrez le NameServer (NS) (ex: ns.example.com) : " NAMESERVER
    if [[ -z "$NAMESERVER" ]]; then
        echo "NameServer invalide." >&2
        exit 1
    fi
    echo "$NAMESERVER" > "$CONFIG_FILE"
    log "NameServer enregistré dans $CONFIG_FILE"

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

    PUB_KEY=$(cat "$SERVER_PUB")
    echo ""
    echo "+--------------------------------------------+"
    echo "|          CONFIGURATION SLOWDNS             |"
    echo "+--------------------------------------------+"
    echo ""
    echo "Clé publique : $PUB_KEY"
    echo "NameServer  : $NAMESERVER"
    echo ""
    log "Installation et configuration SlowDNS terminées (version corrigée et optimisée)."
}

main "$@"
