#!/bin/bash
set -euo pipefail

# ============================
# VARIABLES PRINCIPALES
# ============================
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
ENV_FILE="$SLOWDNS_DIR/slowdns.env"

# ⚠️ Remplacez par vos infos Cloudflare si nécessaire
CF_API_TOKEN="7mn4LKcZARvdbLlCVFTtaX7LGM2xsnyjHkiTAt37"
CF_ZONE_ID="7debbb8ea4946898a889c4b5745ab7eb"
DOMAIN="kingom.ggff.net"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ============================
# FONCTIONS DE BASE
# ============================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Ce script doit être exécuté en root." >&2
        exit 1
    fi
}

install_dependencies() {
    log "Installation des dépendances..."
    apt-get update -q
    apt-get install -y nftables wget tcpdump curl jq python3 python3-venv python3-pip
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
    log "Optimisation sysctl pour VPS léger..."

    # Supprimer ancienne section SlowDNS si existante
    sed -i '/# Optimisations SlowDNS/,+20d' /etc/sysctl.conf || true

    cat <<EOF >> /etc/sysctl.conf

# Optimisations SlowDNS légères pour VPS 2c/2Go
net.core.rmem_max=2097152       # 2MB
net.core.wmem_max=2097152       # 2MB
net.core.rmem_default=131072    # 128KB
net.core.wmem_default=131072    # 128KB
net.core.optmem_max=8388608     # 8MB
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_fin_timeout=10
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_mtu_probing=0       # Désactivé pour réduire CPU
net.ipv4.ip_forward=1
EOF

    sysctl -p
    log "✅ Paramètres sysctl appliqués"
}

disable_systemd_resolved() {
    log "Gestion sûre de systemd-resolved (Ubuntu compatible)..."

    if systemctl list-unit-files | grep -q "^systemd-resolved.service"; then
        systemctl stop systemd-resolved || true
        systemctl disable systemd-resolved || true
    fi

    # Ne jamais supprimer resolv.conf (Ubuntu 22+/24+)
    if [ -L /etc/resolv.conf ]; then
        log "/etc/resolv.conf est un lien symbolique – laissé intact"
    else
        log "/etc/resolv.conf protégé – aucune modification"
    fi
}

configure_nftables() {
    log "⚡ Configuration nftables SlowDNS (stable et compatible VPN HTTP Custom)..."

    # Activation nftables
    systemctl enable nftables >/dev/null 2>&1 || true
    systemctl start nftables >/dev/null 2>&1 || true

    DNS_PORT=53
    SLOWDNS_PORT="$PORT"

    # Nettoyage de la table SlowDNS
    nft delete table inet slowdns 2>/dev/null || true
    nft add table inet slowdns

    # Chaîne INPUT
    nft add chain inet slowdns input { type filter hook input priority 0 \; policy accept \; }
    nft add rule inet slowdns input ct state established,related accept
    nft add rule inet slowdns input iif lo accept
    nft add rule inet slowdns input ip protocol icmp accept
    nft add rule inet slowdns input udp dport "$SLOWDNS_PORT" accept
    nft add rule inet slowdns input tcp dport 22 accept

    # PREROUTING NAT (DNS → SlowDNS)
    # On garde la redirection, mais on s'assure qu'elle ne bloque pas HTTP Custom
    nft add chain inet slowdns prerouting { type nat hook prerouting priority dstnat \; policy accept \; }
    nft add rule inet slowdns prerouting udp dport "$DNS_PORT" redirect to :"$SLOWDNS_PORT"

    # ⚠️ Ajouter éventuellement une règle de journalisation pour debug
    # nft add rule inet slowdns input udp dport "$SLOWDNS_PORT" log prefix "SlowDNS UDP: " level info

    log "✅ nftables SlowDNS appliqué correctement et compatible VPN HTTP Custom"
}

# ============================
# CHOIX BACKEND
# ============================
choose_backend() {
    echo ""
    echo "+--------------------------------------------+"
    echo "|      CHOIX DU MODE BACKEND SLOWDNS         |"
    echo "+--------------------------------------------+"
    echo "1) SSH"
    echo "2) V2Ray"
    echo "3) WS"
    echo ""
    read -rp "Sélectionnez le backend [1-3] : " BACKEND_CHOICE
    case "$BACKEND_CHOICE" in
        1) BACKEND="ssh" ;;
        2) BACKEND="v2ray" ;;
        3) BACKEND="mix" ;;
        *) echo "Choix invalide." >&2; exit 1 ;;
    esac
    echo "Backend sélectionné : $BACKEND"
}

# ============================
# CHOIX MODE AUTO / MAN
# ============================
choose_mode() {
    echo ""
    echo "+--------------------------------------------+"
    echo "|        CHOIX MODE AUTO / MANUEL            |"
    echo "+--------------------------------------------+"
    echo "1) AUTO (NS Cloudflare généré automatiquement)"
    echo "2) MAN (NS à saisir manuellement)"
    echo ""
    read -rp "Sélectionnez le mode [1-2] : " MODE_CHOICE
    case "$MODE_CHOICE" in
        1) MODE="auto" ;;
        2) MODE="man" ;;
        *) echo "Choix invalide." >&2; exit 1 ;;
    esac
    echo "Mode sélectionné : $MODE"
}

# ============================
# GESTION NS
# ============================

create_ns_cloudflare() {
    VPS_IP=$(curl -s https://ipv4.icanhazip.com || curl -s https://ifconfig.me)

    if [[ -z "$VPS_IP" ]]; then
        echo "Impossible de détecter l'IP publique du VPS" >&2
        exit 1
    fi

    SUB_A="a$(date +%s | tail -c 6)"
    SUB_NS="ns$(date +%s | tail -c 6)"

    A_FQDN="$SUB_A.$DOMAIN"
    NS_FQDN="$SUB_NS.$DOMAIN"

    log "Création A record : $A_FQDN → $VPS_IP"

    curl -fsSL -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{
            \"type\":\"A\",
            \"name\":\"$A_FQDN\",
            \"content\":\"$VPS_IP\",
            \"ttl\":120,
            \"proxied\":false
        }" | jq -e '.success' >/dev/null || {
            echo "Erreur création A record Cloudflare" >&2
            exit 1
        }

    log "Création NS record : $NS_FQDN → $A_FQDN"

    curl -fsSL -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{
            \"type\":\"NS\",
            \"name\":\"$NS_FQDN\",
            \"content\":\"$A_FQDN\",
            \"ttl\":120
        }" | jq -e '.success' >/dev/null || {
            echo "Erreur création NS record Cloudflare" >&2
            exit 1
        }

    echo "$NS_FQDN"
}

get_ns() {
    if [[ "$MODE" == "auto" ]]; then
        if [[ -f "$CONFIG_FILE" ]]; then
            NS=$(cat "$CONFIG_FILE")
            log "NS auto existant détecté : $NS"
        else
            log "Aucun NS auto trouvé, création via Cloudflare..."
            NS=$(create_ns_cloudflare)
            echo "$NS" > "$CONFIG_FILE"
            log "NS Cloudflare créé et sauvegardé : $NS"
        fi
    else
        read -rp "Entrez le NameServer (NS) (ex: ns.example.com) : " NS
        if [[ -z "$NS" ]]; then
            echo "NameServer invalide." >&2
            exit 1
        fi
        echo "$NS" > "$CONFIG_FILE"
    fi
}

# ============================
# GESTION DU WRAPPER
# ============================
create_wrapper_script() {
cat <<'EOF' > /usr/local/bin/slowdns-start.sh
#!/bin/bash
set -euo pipefail

SLOWDNS_BIN="/usr/local/bin/dnstt-server"
SLOWDNS_DIR="/etc/slowdns"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
ENV_FILE="$SLOWDNS_DIR/slowdns.env"
SERVER_KEY="$SLOWDNS_DIR/server.key"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

[ -f "$ENV_FILE" ] || { echo "slowdns.env manquant"; exit 1; }
source "$ENV_FILE"

wait_for_interface() {
    while true; do
        iface=$(ip -o link show up | awk -F': ' '{print $2}' \
            | grep -Ev 'lo|docker|veth|br-|tun|tap|virbr|wl')
        [ -n "$iface" ] && echo "$iface" && return
        sleep 2
    done
}

log "Attente de l'interface réseau..."
IFACE=$(wait_for_interface)
log "Interface détectée : $IFACE"

MTU=$(ip link show "$IFACE" | awk '/mtu/ {print $5}')
log "MTU détecté : $MTU"

NS=$(cat "$CONFIG_FILE")

case "$BACKEND" in
    ssh) backend_port=22 ;;
    v2ray) backend_port=5401 ;;
    mix) backend_port=80 ;;
    *) backend_port=22 ;;
esac

exec "$SLOWDNS_BIN" \
    -udp :$PORT \
    -privkey-file "$SERVER_KEY" \
    "$NS" 127.0.0.1:$backend_port
EOF

chmod +x /usr/local/bin/slowdns-start.sh
}

# ============================
# SERVICE SYSTEMD
# ============================
create_systemd_service() {
    cat <<EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS Server Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/slowdns-start.sh
Restart=on-failure
RestartSec=5
StandardOutput=append:/var/log/slowdns.log
StandardError=append:/var/log/slowdns.log
LimitNOFILE=1048576
TimeoutStartSec=60
SyslogIdentifier=slowdns
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now slowdns.service
    log "Service systemd slowdns créé et démarré"
}

# ============================
# MAIN
# ============================
main() {
    check_root
    install_dependencies
    install_slowdns_bin
    install_fixed_keys
    disable_systemd_resolved
    configure_sysctl
    configure_nftables

    choose_backend
    choose_mode
    get_ns

    # Génération fichier slowdns.env avant le wrapper
    cat <<EOF > "$ENV_FILE"
NS=$NS
PUB_KEY=$(cat "$SERVER_PUB")
PRIV_KEY=$(cat "$SERVER_KEY")
BACKEND=$BACKEND
MODE=$MODE
EOF
    chmod 600 "$ENV_FILE"
    log "Fichier slowdns.env généré avec succès."

    create_wrapper_script
    create_systemd_service

    PUB_KEY=$(cat "$SERVER_PUB")
    echo ""
    echo "+--------------------------------------------+"
    echo "|          CONFIGURATION SLOWDNS             |"
    echo "+--------------------------------------------+"
    echo ""
    echo "Clé publique : $PUB_KEY"
    echo "NameServer  : $NS"
    echo "Backend     : $BACKEND"
    echo "Mode        : $MODE"
    echo ""
    echo "IMPORTANT : Pour améliorer le débit SSH, modifiez /etc/ssh/sshd_config :"
    echo "Ciphers aes128-ctr,aes192-ctr,aes128-gcm@openssh.com"
    echo "MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-256"
    echo "Compression yes"
    echo "Puis redémarrez SSH : systemctl restart sshd"
    echo ""
    echo ""
    log "Installation et configuration SlowDNS terminées."
}

main "$@"
