#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
LOG_DIR="/var/log/slowdns"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=5300
XRAY_PORT=5400
XRAY_LOCAL_PORT=8443
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Ce script doit être exécuté en root ou via sudo." >&2
        exit 1
    fi
}

install_dependencies() {
    log "Installation des dépendances..."
    apt-get update -q
    apt-get install -y iptables ufw wget tcpdump logrotate
}

install_slowdns_bin() {
    if [ ! -x "$SLOWDNS_BIN" ]; then
        log "Téléchargement du binaire SlowDNS..."
        wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
        chmod +x "$SLOWDNS_BIN"
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
net.core.rmem_max=26214400
net.core.wmem_max=26214400
net.core.rmem_default=26214400
net.core.wmem_default=26214400
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

stop_systemd_resolved() {
    log "Arrêt de systemd-resolved..."
    systemctl stop systemd-resolved || true
    systemctl disable systemd-resolved || true
    rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
}

configure_ufw() {
    if command -v ufw >/dev/null 2>&1; then
        log "Ouverture des ports UDP $PORT et $XRAY_PORT avec UFW..."
        ufw allow "$PORT"/udp
        ufw allow "$XRAY_PORT"/udp
        ufw reload || true
    fi
}

setup_logging() {
    log "Configuration du dossier de logs..."
    mkdir -p "$LOG_DIR"
    chmod 755 "$LOG_DIR"

    cat <<EOF > /etc/logrotate.d/slowdns
$LOG_DIR/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 640 root adm
}
EOF
}

create_wrapper_script() {
    cat <<'EOF' > /usr/local/bin/slowdns-start.sh
#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
LOG_FILE="/var/log/slowdns/slowdns-ssh.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

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
    iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
    iptables -t nat -I PREROUTING -i "$interface" -p udp --dport 53 -j REDIRECT --to-ports "$PORT"
}

log "Attente de l'interface réseau..."
interface=$(wait_for_interface)
log "Interface détectée : $interface"

log "Application des règles iptables..."
setup_iptables "$interface"

log "Démarrage SlowDNS (SSH)..."
NS=$(cat "$CONFIG_FILE")
ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
[ -z "$ssh_port" ] && ssh_port=22

exec "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" "$NS" 0.0.0.0:$ssh_port >> "$LOG_FILE" 2>&1
EOF
    chmod +x /usr/local/bin/slowdns-start.sh
}

create_wrapper_script_xray() {
    cat <<'EOF' > /usr/local/bin/slowdns-xray.sh
#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
XRAY_PORT=5400
XRAY_LOCAL_PORT=8443
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
LOG_FILE="/var/log/slowdns/slowdns-xray.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "Démarrage SlowDNS (Xray)..."
NS=$(cat "$CONFIG_FILE")
exec "$SLOWDNS_BIN" -udp :$XRAY_PORT -privkey-file "$SERVER_KEY" "$NS" 127.0.0.1:$XRAY_LOCAL_PORT >> "$LOG_FILE" 2>&1
EOF
    chmod +x /usr/local/bin/slowdns-xray.sh
}

create_systemd_services() {
    cat <<EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS Server (SSH)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/slowdns-start.sh
Restart=always
RestartSec=5
StandardOutput=append:/var/log/slowdns/service.log
StandardError=append:/var/log/slowdns/error.log
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    cat <<EOF > /etc/systemd/system/slowdns-xray.service
[Unit]
Description=SlowDNS Server (Xray)
After=network-online.target xray.service
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/slowdns-xray.sh
Restart=always
RestartSec=5
StandardOutput=append:/var/log/slowdns/service.log
StandardError=append:/var/log/slowdns/error.log
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable slowdns.service slowdns-xray.service
    systemctl restart slowdns.service slowdns-xray.service
}

main() {
    check_root
    install_dependencies
    install_slowdns_bin
    install_fixed_keys
    stop_systemd_resolved

    read -rp "Entrez le NameServer (NS) (ex: ns.example.com) : " NAMESERVER
    mkdir -p "$SLOWDNS_DIR"
    echo "$NAMESERVER" > "$CONFIG_FILE"
    log "NameServer : $NAMESERVER"

    configure_sysctl
    configure_ufw
    setup_logging
    create_wrapper_script
    create_wrapper_script_xray
    create_systemd_services

    PUB_KEY=$(cat "$SERVER_PUB")
    echo ""
    echo "+--------------------------------------------+"
    echo "|         CONFIGURATION SLOWDNS              |"
    echo "+--------------------------------------------+"
    echo "Clé publique : $PUB_KEY"
    echo "NameServer  : $NAMESERVER"
    echo "SSH+SlowDNS : UDP $PORT → 127.0.0.1:22"
    echo "Xray+SlowDNS: UDP $XRAY_PORT → 127.0.0.1:$XRAY_LOCAL_PORT"
    echo "Logs : /var/log/slowdns/"
    echo "+--------------------------------------------+"
}

main "$@"
