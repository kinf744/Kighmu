#!/bin/bash
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
    # Clés statiques (conservées comme demandé)
    echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
    echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
    chmod 600 "$SERVER_KEY"
    chmod 644 "$SERVER_PUB"
}

configure_sysctl() {
    log "Optimisation sysctl (valeurs ajustées)..."
    # Supprime l'ancienne section si présente
    sed -i '/# Optimisations SlowDNS/,+20d' /etc/sysctl.conf || true
    cat <<EOF >> /etc/sysctl.conf

# Optimisations SlowDNS
# Valeurs raisonnables pour éviter d'engorger la pile réseau
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

stop_systemd_resolved() {
    log "Désactivation non-destructive du stub DNS systemd-resolved (libère le port 53 localement)..."
    # On désactive le DNSStubListener au lieu de désactiver totalement systemd-resolved
    if [ -f /etc/systemd/resolved.conf ]; then
        sed -i 's/^#*DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf || echo "DNSStubListener=no" >> /etc/systemd/resolved.conf
        systemctl restart systemd-resolved || true
        # Lien propre vers resolv.conf géré par systemd-resolved
        ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
        log "systemd-resolved configuré pour ne pas écouter le stub, /etc/resolv.conf lié vers /run/systemd/resolve/resolv.conf"
    else
        log "Aucun /etc/systemd/resolved.conf trouvé — skip."
    fi
}

configure_iptables() {
    log "Configuration du pare-feu via iptables (idempotent)..."

    # Ouvre UDP 53 et le port d'écoute SLOWDNS
    for port in 53 ${PORT}; do
        if ! iptables -C INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null; then
            iptables -I INPUT -p udp --dport "$port" -j ACCEPT
            log "Rule added: ACCEPT udp dport $port"
        else
            log "Rule exists: ACCEPT udp dport $port"
        fi
    done

    # Assure que SSH est accessible
    if ! iptables -C INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p tcp --dport 22 -j ACCEPT
        log "Rule added: ACCEPT tcp dport 22"
    fi

    iptables-save > /etc/iptables/rules.v4
    log "Règles iptables appliquées et sauvegardées dans /etc/iptables/rules.v4"

    # Activer netfilter-persistent si disponible
    if command -v netfilter-persistent >/dev/null 2>&1; then
        systemctl enable netfilter-persistent || true
        systemctl restart netfilter-persistent || true
        log "Persistance iptables activée via netfilter-persistent."
    fi
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
    # Ajoute les règles seulement si elles n'existent pas (idempotent)
    if ! iptables -t nat -C PREROUTING -i "$interface" -p udp --dport 53 -j REDIRECT --to-ports "$PORT" 2>/dev/null; then
        iptables -t nat -I PREROUTING -i "$interface" -p udp --dport 53 -j REDIRECT --to-ports "$PORT"
        log "NAT redirige 53 -> ${PORT} sur $interface"
    else
        log "NAT PREROUTING déjà présent"
    fi

    if ! iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
        log "ACCEPT udp dport $PORT ajouté"
    fi

    if ! iptables -C INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p udp --dport 53 -j ACCEPT
        log "ACCEPT udp dport 53 ajouté"
    fi

    # Sauvegarde
    iptables-save > /etc/iptables/rules.v4 || true
}

log "Attente de l'interface réseau..."
interface=$(wait_for_interface)
log "Interface détectée : $interface"

log "Application des règles iptables..."
setup_iptables "$interface"

log "Démarrage SlowDNS..."
NS=$(cat "$CONFIG_FILE")
ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
[ -z "$ssh_port" ] && ssh_port=22

# Lancement avec options d'optimisation (TTL et taille max de packet DNS pour réduire fragmentation)
exec "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" -dns-ttl 60 -max-packet-size 1252 "$NS" 0.0.0.0:$ssh_port
EOF
    chmod +x /usr/local/bin/slowdns-start.sh
    log "/usr/local/bin/slowdns-start.sh créé"
}

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
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=slowdns-server
LimitNOFILE=1048576
Nice=-5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable slowdns.service
    systemctl restart slowdns.service || true
    log "Service systemd slowdns installé et redémarré"
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
    mkdir -p "$SLOWDNS_DIR"
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
    echo ""
    log "Installation et configuration SlowDNS terminées."
}

main "$@"
