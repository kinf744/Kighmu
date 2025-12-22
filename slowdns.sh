#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"

# Backend par défaut (sera redéfini par le choix utilisateur)
BACKEND_MODE=""   # ssh | v2ray | mix

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
        wget -q -O "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
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
    log "Désactivation non-destructive du stub DNS systemd-resolved (libère le port 53 localement)..."
    systemctl stop systemd-resolved || true
    systemctl disable systemd-resolved || true
    rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
}

configure_nftables() {
    log "Configuration du pare-feu via nftables..."

    # Détecter l'interface principale (non loopback)
    interface=$(ip -o link show up | awk -F': ' '{print $2}' | grep -v '^lo$' | head -n1)
    log "Interface détectée pour nftables : $interface"

    # Créer table slowdns si inexistante
    nft list table inet slowdns &>/dev/null || nft add table inet slowdns

    # Créer chaîne prerouting pour NAT si inexistante
    nft list chain inet slowdns prerouting &>/dev/null || \
        nft add chain inet slowdns prerouting { type nat hook prerouting priority 0; }

    # Redirection UDP 53 vers le port SlowDNS
    nft list rule inet slowdns prerouting &>/dev/null || \
        nft add rule inet slowdns prerouting udp dport 53 counter redirect to :$PORT

    # Créer table filter si inexistante
    nft list table inet filter &>/dev/null || nft add table inet filter

    # Créer chaîne input si inexistante
    nft list chain inet filter input &>/dev/null || \
        nft add chain inet filter input { type filter hook input priority 0; policy accept; }

    # Autoriser le port SlowDNS
    nft list rule inet filter input udp dport $PORT &>/dev/null || \
        nft add rule inet filter input udp dport $PORT accept

    # Autoriser le port V2Ray
    nft list rule inet filter input udp dport 5401 &>/dev/null || \
        nft add rule inet filter input udp dport 5401 accept

    log "nftables configuré : port $PORT (SlowDNS) et 5401 (V2Ray) ouverts, redirection UDP 53 active."
}

# Choix du backend (SSH / V2Ray / MIX)
choose_backend() {
    echo ""
    echo "+--------------------------------------------+"
    echo "|      CHOIX DU MODE BACKEND SLOWDNS         |"
    echo "+--------------------------------------------+"
    echo "1) SSH direct (DNSTT → 127.0.0.1:22)"
    echo "2) V2Ray direct (DNSTT → 127.0.0.1:5401)"
    echo "3) MIX (DNSTT → 127.0.0.1:5401, V2Ray gère SSH + VLESS/VMESS/Trojan)"
    echo ""
    read -rp "Sélectionnez le mode [1-3] : " mode
    case "$mode" in
        1) BACKEND_MODE="ssh" ;;
        2) BACKEND_MODE="v2ray" ;;
        3) BACKEND_MODE="mix" ;;
        *) echo "Mode invalide."; exit 1 ;;
    esac
    echo "BACKEND_MODE=$BACKEND_MODE" > /etc/slowdns/backend.conf
}

create_wrapper_script() {
    cat <<'EOF' > /usr/local/bin/slowdns-start.sh
#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
BACKEND_CONF="$SLOWDNS_DIR/backend.conf"

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

setup_nftables() {
    interface="$1"
    log "Configuration des règles nftables pour SlowDNS..."

    # Création table et chaîne si inexistante
    nft list table inet slowdns &>/dev/null || nft add table inet slowdns
    nft list chain inet slowdns prerouting &>/dev/null || \
        nft add chain inet slowdns prerouting { type nat hook prerouting priority 0 \; }

    # Redirection UDP 53 vers SlowDNS PORT uniquement
    nft list rule inet slowdns prerouting &>/dev/null || \
        nft add rule inet slowdns prerouting udp dport 53 counter redirect to :$PORT

    # Autoriser le port SlowDNS en INPUT
    nft list chain inet filter input &>/dev/null || \
        nft add table inet filter
    nft list chain inet filter input &>/dev/null || \
        nft add chain inet filter input { type filter hook input priority 0 \; policy accept }
    nft list rule inet filter input &>/dev/null || \
        nft add rule inet filter input udp dport $PORT accept

    log "nftables configuré : port $PORT ouvert pour SlowDNS, redirection UDP 53 active."
}

select_backend_target() {
    local mode target ssh_port
    mode="ssh"
    if [ -f "$BACKEND_CONF" ]; then
        # shellcheck disable=SC1090
        source "$BACKEND_CONF"
        mode="${BACKEND_MODE:-ssh}"
    fi

    case "$mode" in
        ssh)
            # SSH direct
            ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
            [ -z "$ssh_port" ] && ssh_port=22
            target="127.0.0.1:$ssh_port"
            printf '[%s] Mode backend : SSH (%s)
' "$(date '+%Y-%m-%d %H:%M:%S')" "$target" >&2
            ;;
        v2ray)
            # V2Ray direct uniquement
            target="127.0.0.1:5401"
            printf '[%s] Mode backend : V2Ray (%s)
' "$(date '+%Y-%m-%d %H:%M:%S')" "$target" >&2
            ;;
        mix)
            # MIX : V2Ray 5401 (qui pourra gérer SSH, VLESS, VMESS, TROJAN)
            target="127.0.0.1:5401"
            printf '[%s] Mode backend : MIX (via V2Ray %s)
' "$(date '+%Y-%m-%d %H:%M:%S')" "$target" >&2
            ;;
        *)
            # fallback
            target="127.0.0.1:22"
            printf '[%s] Mode backend inconnu, fallback SSH (%s)
' "$(date '+%Y-%m-%d %H:%M:%S')" "$target" >&2
            ;;
    esac

    # UNIQUEMENT l'adresse sur stdout (pas de log)
    echo "$target"
}

log "Attente de l'interface réseau..."
interface=$(wait_for_interface)
log "Interface détectée : $interface"

log "Réglage MTU à 1350 pour éviter la fragmentation DNS..."
ip link set dev "$interface" mtu 1350 || log "Échec réglage MTU, continuer"

log "Application des règles iptables..."
setup_nftables "$interface"

log "Démarrage du serveur SlowDNS..."

NS=$(cat "$CONFIG_FILE")
backend_target=$(select_backend_target)

exec nice -n 0 "$SLOWDNS_BIN" -udp ":$PORT" -privkey-file "$SERVER_KEY" "$NS" "$backend_target"
EOF

    chmod +x /usr/local/bin/slowdns-start.sh
}

create_systemd_service() {
    cat <<EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS Server Tunnel (multi-backend)
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
Nice=0
CPUSchedulingPolicy=other
IOSchedulingClass=best-effort
IOSchedulingPriority=4
TimeoutStartSec=20

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
    mkdir -p "$SLOWDNS_DIR"
    echo "$NAMESERVER" > "$CONFIG_FILE"
    log "NameServer enregistré dans $CONFIG_FILE"

    choose_backend

    configure_sysctl
    configure_nftables
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
    echo "Port UDP    : $PORT"
    echo ""
    echo "Mode backend sélectionné : $BACKEND_MODE"
    echo "  - ssh   : DNSTT → SSH (port 22 détecté)"
    echo "  - v2ray : DNSTT → 127.0.0.1:5401"
    echo "  - mix   : DNSTT → 127.0.0.1:5401 (V2Ray gère SSH + VLESS/VMESS/TROJAN)"
    echo ""
    echo "IMPORTANT : Pour améliorer le débit SSH, modifiez manuellement /etc/ssh/sshd_config en ajoutant :"
    echo "Ciphers aes128-ctr,aes192-ctr,aes128-gcm@openssh.com"
    echo "MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-256"
    echo "Compression yes"
    echo "Puis redémarrez SSH avec : systemctl restart sshd"
    echo ""
    echo "Le MTU du tunnel est fixé à 1350 via le script de démarrage pour limiter la fragmentation DNS."
    echo ""
    log "Installation et configuration SlowDNS terminées."
}

main "$@"
