#!/bin/bash
set -euo pipefail

# ================================
#  CONFIGURATION PRINCIPALE
# ================================
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=53

CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
LOG_FILE="/var/log/slowdns.log"

# ================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# ================================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "❌ Ce script doit être exécuté en root"
        exit 1
    fi
}

# ================================
install_dependencies() {
    log "Installation des dépendances..."
    apt-get update -q
    apt-get install -y wget curl iptables iptables-persistent jq
}

# ================================
install_slowdns_bin() {
    if [ ! -x "$SLOWDNS_BIN" ]; then
        log "Téléchargement du binaire SlowDNS..."
        wget -q -O "$SLOWDNS_BIN" \
            https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
        chmod +x "$SLOWDNS_BIN"
    fi
}

# ================================
install_fixed_keys() {
    log "Installation des clés DNSTT fixes..."
    mkdir -p "$SLOWDNS_DIR"

    echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
    echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"

    chmod 600 "$SERVER_KEY"
    chmod 644 "$SERVER_PUB"
}

# ================================
disable_systemd_resolved() {
    log "Désactivation de systemd-resolved..."
    systemctl stop systemd-resolved || true
    systemctl disable systemd-resolved || true

    chattr -i /etc/resolv.conf 2>/dev/null || true
    cat <<EOF > /etc/resolv.conf
nameserver 8.8.8.8
nameserver 1.1.1.1
options timeout:1 attempts:1
EOF
}

# ================================
configure_iptables() {
    log "Ouverture du port UDP 53 (iptables)..."

    if ! iptables -C INPUT -p udp --dport 53 -j ACCEPT &>/dev/null; then
        iptables -I INPUT -p udp --dport 53 -j ACCEPT
    fi

    iptables-save > /etc/iptables/rules.v4
    systemctl enable netfilter-persistent
    systemctl restart netfilter-persistent
}

# ================================
generate_ns_manual() {
    read -rp "Entrez le NameServer (ex: ns.example.com) : " NS
    if [[ -z "$NS" ]]; then
        echo "❌ NameServer invalide"
        exit 1
    fi

    echo "$NS" > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
}

# ================================
create_wrapper_script() {
    log "Création du script de démarrage SlowDNS..."

    cat <<'EOF' > /usr/local/bin/slowdns-start.sh
#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=53

CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Détection interface principale
detect_interface() {
    ip -o link show up | awk -F': ' '{print $2}' \
        | grep -vE '^(lo|docker|veth|br|virbr|tun|tap|wl|vmnet)' \
        | head -n1
}

iface=""
while [ -z "$iface" ]; do
    iface=$(detect_interface)
    sleep 1
done

log "Interface détectée : $iface"
log "Réglage MTU à 1180..."
ip link set dev "$iface" mtu 1180 || true

NS=$(cat "$CONFIG_FILE")

log "Démarrage SlowDNS sur UDP 53..."
exec "$SLOWDNS_BIN" -udp :53 -privkey-file "$SERVER_KEY" "$NS" 0.0.0.0:22
EOF

    chmod +x /usr/local/bin/slowdns-start.sh
}

# ================================
create_systemd_service() {
    log "Création du service systemd..."

    cat <<EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS Classique (UDP 53)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
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

# ================================
main() {
    check_root
    install_dependencies
    install_slowdns_bin
    install_fixed_keys
    disable_systemd_resolved
    configure_iptables
    generate_ns_manual
    create_wrapper_script
    create_systemd_service

    echo ""
    echo "======================================"
    echo "  SLOWDNS CLASSIQUE INSTALLÉ"
    echo "======================================"
    echo "Port UDP     : 53"
    echo "NameServer   : $(cat "$CONFIG_FILE")"
    echo "Clé publique : $(cat "$SERVER_PUB")"
    echo "Logs         : journalctl -u slowdns -f"
    echo "======================================"
}

main "$@"
