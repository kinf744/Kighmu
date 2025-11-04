#!/bin/bash
# Script SlowDNS modifié pour pointer vers le port Xray (127.0.0.1:10800)

set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Ce script doit être executé en root ou via sudo." >&2
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
    # Clés hardcodées de l'utilisateur
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
    log "Arrêt de systemd-resolved pour libérer le port 53..."
    systemctl stop systemd-resolved || true
    systemctl disable systemd-resolved || true
    rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
}

configure_iptables() {
    log "Configuration du pare-feu via iptables..."
    # Règle SlowDNS
    iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
    # Règle SSH (port 22)
    iptables -I INPUT -p tcp --dport 22 -j ACCEPT
    
    # Ajout des ports Xray pour s'assurer qu'ils sont ouverts
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p udp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 8443 -j ACCEPT
    iptables -A INPUT -p udp --dport 8443 -j ACCEPT
    iptables -A INPUT -p tcp --dport 2083 -j ACCEPT
    iptables -A INPUT -p udp --dport 2083 -j ACCEPT
    
    iptables-save > /etc/iptables/rules.v4
    log "Règles iptables appliquées et sauvegardées dans /etc/iptables/rules.v4"
    
    # Assurer la persistance au redémarrage
    systemctl enable netfilter-persistent || true
    systemctl restart netfilter-persistent || true
    log "Persistance iptables activée via netfilter-persistent."
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
    # Règle de redirection du port 53 vers le port d'écoute de sldns-server (5300)
    iptables -t nat -I PREROUTING -i "$interface" -p udp --dport 53 -j REDIRECT --to-ports "$PORT"
}

log "Attente de l'interface réseau..."
interface=$(wait_for_interface)
log "Interface détectée : $interface"

log "Application des règles iptables de redirection..."
setup_iptables "$interface"

log "Démarrage SlowDNS pointant vers Xray SOCKS (127.0.0.1:10800)..."
NS=$(cat "$CONFIG_FILE")

# MODIFICATION CRUCIALE : Pointe vers le port SOCKS de Xray (10800) au lieu du port SSH
exec "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" "$NS" 127.0.0.1:10800
EOF
    chmod +x /usr/local/bin/slowdns-start.sh
}

create_systemd_service() {
    cat <<EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS Server Tunnel (Combiné Xray)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/slowdns-start.sh
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
}

main() {
    check_root
    install_dependencies
    install_slowdns_bin
    install_fixed_keys
    stop_systemd_resolved

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
    log "Fichier slowdns.env généré avec succès."

    PUB_KEY=$(cat "$SERVER_PUB")
    echo ""
    echo "+--------------------------------------------+"
    echo "|          CONFIGURATION SLOWDNS             |"
    echo "+--------------------------------------------+"
    echo ""
    echo "Clé publique : $PUB_KEY"
    echo "NameServer  : $NAMESERVER"
    echo "Le tunnel SlowDNS pointe maintenant vers Xray SOCKS (127.0.0.1:10800)."
    echo ""
    log "Installation et configuration SlowDNS terminées."
}

main "$@"
