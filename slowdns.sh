#!/bin/bash
set -euo pipefail

# --- Configuration principale ---
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# --- Vérification root ---
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Ce script doit être exécuté en root." >&2
        exit 1
    fi
}

# --- Dépendances ---
install_dependencies() {
    log "Installation des dépendances..."
    apt-get update -q
    apt-get install -y iptables iptables-persistent wget tcpdump curl jq
}

# --- Installation SlowDNS binaire ---
install_slowdns_bin() {
    if [ ! -x "$SLOWDNS_BIN" ]; then
        log "Téléchargement du binaire DNSTT..."
        wget -O "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
        chmod +x "$SLOWDNS_BIN"

        if ! file "$SLOWDNS_BIN" | grep -q ELF; then
            echo "ERREUR : binaire DNSTT invalide" >&2
            exit 1
        fi
    fi
}

# --- Clés fixes ---
install_fixed_keys() {
    mkdir -p "$SLOWDNS_DIR"
    echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
    echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
    chmod 600 "$SERVER_KEY"
    chmod 644 "$SERVER_PUB"
}

# --- Sysctl optimisations ---
configure_sysctl() {
    log "Optimisation sysctl..."
    sed -i '/# Optimisations SlowDNS/,+10d' /etc/sysctl.conf || true
    cat <<EOF >> /etc/sysctl.conf

# Optimisations SlowDNS
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=524288
net.core.wmem_default=524288
net.core.optmem_max=25165824

net.ipv4.udp_rmem_min=32768
net.ipv4.udp_wmem_min=32768
net.ipv4.udp_mem=262144 524288 1048576

net.ipv4.tcp_fastopen=3
net.ipv4.tcp_fin_timeout=10
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_low_latency=1

net.ipv4.ip_forward=1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl -p
}

# --- Désactivation systemd-resolved ---
disable_systemd_resolved() {
    log "Configuration du DNS système..."

    if systemctl list-unit-files | grep -q '^systemd-resolved.service'; then
        log "systemd-resolved détecté, désactivation..."
        systemctl stop systemd-resolved
        systemctl disable systemd-resolved
    else
        log "systemd-resolved non présent, aucune action nécessaire"
    fi

    # Déverrouillage si immutable
    chattr -i /etc/resolv.conf 2>/dev/null || true

    cat <<EOF > /etc/resolv.conf
nameserver 8.8.8.8
nameserver 1.1.1.1
options timeout:1 attempts:1
EOF

    chmod 644 /etc/resolv.conf
    log "/etc/resolv.conf mis à jour avec succès"
}

# --- IPTables ---
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

# --- Cloudflare NS auto ---
CF_API_TOKEN="7mn4LKcZARvdbLlCVFTtaX7LGM2xsnyjHkiTAt37"
CF_ZONE_ID="7debbb8ea4946898a889c4b5745ab7eb"
DOMAIN="kingom.ggff.net" # domaine géré sur Cloudflare

generate_ns_cloudflare() {

    # 🔒 Si un NS auto existe déjà, on le réutilise
    if [[ -f "$SLOWDNS_DIR/ns.auto" ]]; then
        NS=$(cat "$SLOWDNS_DIR/ns.auto")
        log "NS auto existant détecté, réutilisation : $NS"

        echo "$NS" > "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"

        return 0
    fi

    # 🚀 Sinon, création Cloudflare
    log "Aucun NS auto trouvé, génération Cloudflare..."

    VPS_IP=$(curl -s ipv4.icanhazip.com || echo "127.0.0.1")

    SUB_A="vpn-$(date +%s | sha256sum | head -c 6)"
    FQDN_A="$SUB_A.$DOMAIN"

    log "Création du A record : $FQDN_A -> $VPS_IP"
    RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"$FQDN_A\",\"content\":\"$VPS_IP\",\"ttl\":120,\"proxied\":false}")

    echo "$RESPONSE" | jq -e '.success == true' >/dev/null || {
        log "Erreur création A record Cloudflare"
        exit 1
    }

    SUB_NS="ns-$(date +%s | sha256sum | head -c 6)"
    NS="$SUB_NS.$DOMAIN"

    log "Création du NS record : $NS -> $FQDN_A"
    RESPONSE_NS=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"NS\",\"name\":\"$NS\",\"content\":\"$FQDN_A\",\"ttl\":120}")

    echo "$RESPONSE_NS" | jq -e '.success == true' >/dev/null || {
        log "Erreur création NS record Cloudflare"
        exit 1
    }

    # 💾 Sauvegarde persistante
    echo "$NS" > "$SLOWDNS_DIR/ns.auto"
    chmod 600 "$SLOWDNS_DIR/ns.auto"

    # 🔄 NS actif
    echo "$NS" > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"

    # 🌍 ENV
    cat <<EOF > "$SLOWDNS_DIR/slowdns.env"
NS=$NS
PUB_KEY=$(cat "$SERVER_PUB")
PRIV_KEY=$(cat "$SERVER_KEY")
EOF
    chmod 600 "$SLOWDNS_DIR/slowdns.env"

    log "NS Cloudflare auto généré et sauvegardé : $NS"
}

# --- Wrapper SlowDNS ---
create_wrapper_script() {
    cat <<'EOF' > /usr/local/bin/slowdns-start.sh
#!/bin/bash
set -euo pipefail
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
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
    if ! iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT &>/dev/null; then
        iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
    fi
    if ! iptables -t nat -C PREROUTING -i "$interface" -p udp --dport 53 -j REDIRECT --to-ports "$PORT" &>/dev/null; then
        iptables -t nat -I PREROUTING -i "$interface" -p udp --dport 53 -j REDIRECT --to-ports "$PORT"
    fi
}

restart_dnstt() {
    [ -n "${DNSTT_PID-}" ] && kill "$DNSTT_PID" 2>/dev/null || true
    NS=$(cat "$CONFIG_FILE")
    log "Démarrage DNSTT sur 127.0.0.1:$TCP_PORT"
    nice -n 0 "$SLOWDNS_BIN" -udp ":$PORT" -privkey-file "$SERVER_KEY" "$NS" "127.0.0.1:$TCP_PORT" &
    DNSTT_PID=$!
}

log "Attente de l'interface réseau..."
interface=$(wait_for_interface)
log "Interface détectée : $interface"

log "Réglage MTU à 1400..."
ip link set dev "$interface" mtu 1400 || log "Échec réglage MTU"

log "Application des règles iptables..."
setup_iptables "$interface"

CURRENT_PORT=0
DNSTT_PID=""

# Boucle de détection dynamique du port
while true; do
    if ss -tlnp | grep -q ":5401"; then
        TCP_PORT=5401
    else
        TCP_PORT=22
    fi

    if [ "$TCP_PORT" -ne "$CURRENT_PORT" ]; then
        CURRENT_PORT=$TCP_PORT
        restart_dnstt
    fi

    sleep 10
done
EOF
    chmod +x /usr/local/bin/slowdns-start.sh
}

# --- systemd service ---
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

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable slowdns.service
    systemctl restart slowdns.service
}

# --- Main ---
main() {
    check_root
    install_dependencies
    install_slowdns_bin
    install_fixed_keys
    disable_systemd_resolved

    read -rp "Mode d'installation du NS [auto/man] : " MODE
    MODE=${MODE,,}

    if [[ "$MODE" == "auto" ]]; then
        generate_ns_cloudflare
        NAMESERVER=$(cat "$CONFIG_FILE")
    else
        read -rp "Entrez le NameServer (NS) manuel : " NAMESERVER
[[ -z "$NAMESERVER" ]] && { echo "NS invalide"; exit 1; }

# Sauvegarde du NS manuel
echo "$NAMESERVER" > "$SLOWDNS_DIR/ns.manual"
chmod 600 "$SLOWDNS_DIR/ns.manual"

# NS utilisé par le tunnel
echo "$NAMESERVER" > "$CONFIG_FILE"

log "NS manuel utilisé : $NAMESERVER"
log "NS auto conservé (si existant)"
        cat <<EOF > "$SLOWDNS_DIR/slowdns.env"
NS=$NAMESERVER
PUB_KEY=$(cat "$SERVER_PUB")
PRIV_KEY=$(cat "$SERVER_KEY")
EOF
        chmod 600 "$CONFIG_FILE" "$SLOWDNS_DIR/slowdns.env"
        log "NameServer enregistré manuellement : $NAMESERVER"
    fi

    configure_sysctl
    configure_iptables
    create_wrapper_script
    create_systemd_service

    PUB_KEY=$(cat "$SERVER_PUB")
    echo ""
    echo "+--------------------------------------------+"
    echo "|          CONFIGURATION SLOWDNS             |"
    echo "+--------------------------------------------+"
    echo ""
    echo "Clé publique : $PUB_KEY"
    echo "NameServer  : $NAMESERVER"
    echo ""
    echo "MTU du tunnel : 1400"
    log "Installation et configuration SlowDNS terminées."
}

main "$@"
