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
CF_API_TOKEN="TON_CLOUDFLARE_API_TOKEN"
CF_ZONE_ID="TON_CLOUDFLARE_ZONE_ID"
DOMAIN="ton-domaine.com"

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
    apt-get install -y iptables iptables-persistent wget tcpdump curl jq python3 python3-venv python3-pip
}

install_slowdns_bin() {
    if [ ! -x "$SLOWDNS_BIN" ]; then
        log "Téléchargement du binaire SlowDNS..."
        wget -q -O "$SLOWDNS_BIN" https://github.com/Mygod/dnstt/releases/download/v20241021/dnstt-server-linux-amd64
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
EOF
    sysctl -p
}

disable_systemd_resolved() {
    log "Désactivation non-destructive du stub DNS systemd-resolved..."
    systemctl stop systemd-resolved
    systemctl disable systemd-resolved
    rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
}

configure_iptables() {
    log "Configuration du pare-feu via iptables..."
    if ! iptables -C INPUT -p udp --dport 53 -j ACCEPT &>/dev/null; then
        iptables -I INPUT -p udp --dport 53 -j ACCEPT
    fi
    if ! iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT &>/dev/null; then
        iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
    fi
    iptables-save > /etc/iptables/rules.v4
    systemctl enable netfilter-persistent
    systemctl restart netfilter-persistent
    log "Persistance iptables activée via netfilter-persistent."
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
    echo "3) MIX (SSH + V2Ray)"
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
get_ns() {
    if [[ "$MODE" == "auto" ]]; then
        # NS automatique via Cloudflare API ou aléatoire
        if [[ -f "$CONFIG_FILE" ]]; then
            NS=$(cat "$CONFIG_FILE")
            echo "NS existant trouvé : $NS"
        else
            NS="ns$((RANDOM % 9999)).$DOMAIN"
            echo "NS généré automatiquement : $NS"
            echo "$NS" > "$CONFIG_FILE"
        fi
    else
        # Mode manuel
        read -rp "Entrez le NameServer (NS) (ex: ns.example.com) : " NS
        if [[ -z "$NS" ]]; then
            echo "NameServer invalide." >&2
            exit 1
        fi
        echo "$NS" > "$CONFIG_FILE"
    fi
    log "NameServer enregistré dans $CONFIG_FILE"
}

# ============================
# GESTION DU WRAPPER
# ============================
create_wrapper_script() {
    cat <<'EOF' > /usr/local/bin/slowdns-start.sh
#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
ENV_FILE="$SLOWDNS_DIR/slowdns.env"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Charger variables depuis .env
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    echo "Fichier $ENV_FILE manquant !" >&2
    exit 1
fi

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
    else
        log "Règles NAT déjà présentes pour le port 53"
    fi
}

log "Attente de l'interface réseau..."
interface=$(wait_for_interface)
log "Interface détectée : $interface"

log "Réglage MTU à 1400 pour éviter la fragmentation DNS..."
ip link set dev "$interface" mtu 1400 || log "Échec réglage MTU, continuer"

log "Application des règles iptables..."
setup_iptables "$interface"

log "Démarrage du serveur SlowDNS..."

NS=$(cat "$CONFIG_FILE")

# Déterminer le port backend selon le choix
if [[ "$BACKEND" == "ssh" ]]; then
    backend_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
    [ -z "$backend_port" ] && backend_port=22
elif [[ "$BACKEND" == "v2ray" ]] || [[ "$BACKEND" == "mix" ]]; then
    backend_port=8443
fi

# Lancer SlowDNS
exec "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" "$NS" 0.0.0.0:$backend_port
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
    configure_iptables

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
    echo "Le MTU du tunnel est fixé à 1400 via le script de démarrage pour limiter la fragmentation DNS."
    echo ""
    log "Installation et configuration SlowDNS terminées."
}

main "$@"
