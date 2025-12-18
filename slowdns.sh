#!/bin/bash
set -euo pipefail

# ================================
# CONFIGURATION PRINCIPALE
# ================================
CLASSIC_PORT=5300
V2RAY_PORT=5600
MUX_PORT=53

SLOWDNS_CLASSIC_DIR="/etc/slowdns"
SLOWDNS_CLASSIC_BIN="/usr/local/bin/sldns-server"
SLOWDNS_V2RAY_DIR="/etc/slowdns_v2ray"
SLOWDNS_V2RAY_BIN="/usr/local/bin/dnstt-server"

CONFIG_CLASSIC="$SLOWDNS_CLASSIC_DIR/ns.conf"
CONFIG_V2RAY="$SLOWDNS_V2RAY_DIR/ns.conf"
SUBDOMAIN_V2RAY="$SLOWDNS_V2RAY_DIR/subdomain.conf"

LOG_CLASSIC="/var/log/slowdns.log"
LOG_V2RAY="/var/log/slowdns_v2ray.log"
LOG_MUX="/var/log/slowdns_mux.log"

# ================================
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "❌ Ce script doit être exécuté en root"
        exit 1
    fi
}

install_dependencies() {
    log "Installation des dépendances..."
    apt-get update -q
    apt-get install -y wget curl iptables iptables-persistent socat jq
}

# ================================
install_classic() {
    log "Installation SlowDNS classique..."
    mkdir -p "$SLOWDNS_CLASSIC_DIR"
    wget -q -O "$SLOWDNS_CLASSIC_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
    chmod +x "$SLOWDNS_CLASSIC_BIN"

    echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SLOWDNS_CLASSIC_DIR/server.key"
    echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SLOWDNS_CLASSIC_DIR/server.pub"
    chmod 600 "$SLOWDNS_CLASSIC_DIR/server.key"
    chmod 644 "$SLOWDNS_CLASSIC_DIR/server.pub"

    if [ ! -f "$CONFIG_CLASSIC" ]; then
        read -rp "Entrez le NameServer SlowDNS classique (ex: ns.example.com) : " NS
        echo "$NS" > "$CONFIG_CLASSIC"
        chmod 600 "$CONFIG_CLASSIC"
    fi

    # Wrapper
    cat <<EOF > /usr/local/bin/slowdns_classic_start.sh
#!/bin/bash
exec "$SLOWDNS_CLASSIC_BIN" -udp :$CLASSIC_PORT -privkey-file "$SLOWDNS_CLASSIC_DIR/server.key" \$(cat "$CONFIG_CLASSIC") 0.0.0.0:22 >> "$LOG_CLASSIC" 2>&1
EOF
    chmod +x /usr/local/bin/slowdns_classic_start.sh

    # systemd
    cat <<EOF > /etc/systemd/system/slowdns_classic.service
[Unit]
Description=SlowDNS Classique
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/slowdns_classic_start.sh
Restart=always
RestartSec=3
StandardOutput=append:$LOG_CLASSIC
StandardError=append:$LOG_CLASSIC
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable slowdns_classic
    systemctl restart slowdns_classic
}

# ================================
install_v2ray() {
    log "Installation SlowDNS V2Ray..."
    mkdir -p "$SLOWDNS_V2RAY_DIR"
    wget -q -O "$SLOWDNS_V2RAY_BIN" https://dnstt.network/dnstt-server-linux-amd64
    chmod +x "$SLOWDNS_V2RAY_BIN"

    echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SLOWDNS_V2RAY_DIR/server.key"
    echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SLOWDNS_V2RAY_DIR/server.pub"
    chmod 600 "$SLOWDNS_V2RAY_DIR/server.key"
    chmod 644 "$SLOWDNS_V2RAY_DIR/server.pub"

    if [ ! -f "$CONFIG_V2RAY" ]; then
        read -rp "Entrez le NameServer SlowDNS V2Ray (ex: ns.example.com) : " NS
        echo "$NS" > "$CONFIG_V2RAY"
        chmod 600 "$CONFIG_V2RAY"
    fi

    if [ ! -f "$SUBDOMAIN_V2RAY" ]; then
        read -rp "Entrez le sous-domaine V2Ray (ex: v2ray.ns.example.com) : " SUB
        echo "$SUB" > "$SUBDOMAIN_V2RAY"
        chmod 600 "$SUBDOMAIN_V2RAY"
    fi

    # Wrapper
    cat <<EOF > /usr/local/bin/slowdns_v2ray_start.sh
#!/bin/bash
exec "$SLOWDNS_V2RAY_BIN" -udp ":$V2RAY_PORT" -privkey-file "$SLOWDNS_V2RAY_DIR/server.key" \$(cat "$CONFIG_V2RAY") 127.0.0.1:5401 >> "$LOG_V2RAY" 2>&1
EOF
    chmod +x /usr/local/bin/slowdns_v2ray_start.sh

    # systemd
    cat <<EOF > /etc/systemd/system/slowdns_v2ray.service
[Unit]
Description=SlowDNS V2Ray
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/slowdns_v2ray_start.sh
Restart=always
RestartSec=3
StandardOutput=append:$LOG_V2RAY
StandardError=append:$LOG_V2RAY
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable slowdns_v2ray
    systemctl restart slowdns_v2ray
}

# ================================
install_mux() {
    log "Installation du multiplexeur UDP 53..."
    cat <<'EOF' > /usr/local/bin/slowdns_mux.sh
#!/bin/bash
CLASSIC_PORT=5300
V2RAY_PORT=5600
SUBDOMAIN_V2RAY_FILE="/etc/slowdns_v2ray/subdomain.conf"
LOG_MUX="/var/log/slowdns_mux.log"

SUBDOMAIN_V2RAY=$(cat "$SUBDOMAIN_V2RAY_FILE")

exec socat -v UDP-LISTEN:53,fork SYSTEM:"awk '{if (\$4 ~ /'$SUBDOMAIN_V2RAY'/) print \"UDP:127.0.0.1:'$V2RAY_PORT'\"; else print \"UDP:127.0.0.1:'$CLASSIC_PORT'\"}' | socat - UDP-DATAGRAM:localhost:\$1" >> "$LOG_MUX" 2>&1
EOF
    chmod +x /usr/local/bin/slowdns_mux.sh

    # systemd
    cat <<EOF > /etc/systemd/system/slowdns_mux.service
[Unit]
Description=Multiplexeur SlowDNS UDP 53
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/slowdns_mux.sh
Restart=always
RestartSec=3
StandardOutput=append:$LOG_MUX
StandardError=append:$LOG_MUX
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable slowdns_mux
    systemctl restart slowdns_mux
}

# ================================
main() {
    check_root
    install_dependencies
    install_classic
    install_v2ray
    install_mux

    echo ""
    echo "======================================"
    echo "  INSTALLATION TERMINÉE"
    echo "======================================"
    echo "SlowDNS classique  : UDP $CLASSIC_PORT"
    echo "SlowDNS V2Ray     : UDP $V2RAY_PORT -> TCP 5401"
    echo "Multiplexeur      : UDP $MUX_PORT"
    echo "Logs classiques   : journalctl -u slowdns_classic -f"
    echo "Logs V2Ray        : journalctl -u slowdns_v2ray -f"
    echo "Logs multiplexeur : journalctl -u slowdns_mux -f"
    echo "======================================"
}

main "$@"
