#!/bin/bash
set -euo pipefail

# --- Configuration principale ---
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
ENV_FILE="$SLOWDNS_DIR/slowdns.env"

# --- Cloudflare API ---
CF_API_TOKEN="7mn4LKcZARvdbLlCVFTtaX7LGM2xsnyjHkiTAt37"
CF_ZONE_ID="7debbb8ea4946898a889c4b5745ab7eb"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# --- Vérification root ---
if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en root." >&2
    exit 1
fi

# --- Création dossier ---
mkdir -p "$SLOWDNS_DIR"

# --- Dépendances ---
log "Installation des dépendances..."
apt update -y
apt install -y socat curl tcpdump jq python3 python3-venv python3-pip

# --- Création venv ---
if [ ! -d "$SLOWDNS_DIR/venv" ]; then
    python3 -m venv "$SLOWDNS_DIR/venv"
fi

source "$SLOWDNS_DIR/venv/bin/activate"
pip install --upgrade pip
pip install cloudflare

# --- DNSTT ---
if [ ! -x "$SLOWDNS_BIN" ]; then
    log "Téléchargement du binaire DNSTT..."
    curl -L -o "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
    chmod +x "$SLOWDNS_BIN"
fi

# --- Choix du mode ---
read -rp "Choisissez le mode d'installation [auto/man] : " MODE
MODE=${MODE,,}

generate_ns_auto() {
    DOMAIN="kingom.ggff.net"
    VPS_IP=$(curl -s ipv4.icanhazip.com)

    SUB_A="vpn-$(date +%s | sha256sum | head -c 6)"
    FQDN_A="$SUB_A.$DOMAIN"
    log "Création du A : $FQDN_A -> $VPS_IP"

    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$FQDN_A\",\"content\":\"$VPS_IP\",\"ttl\":120,\"proxied\":false}" \
        | jq .

    SUB_NS="ns-$(date +%s | sha256sum | head -c 6)"
    NS="$SUB_NS.$DOMAIN"
    log "Création du NS : $NS -> $FQDN_A"

    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"NS\",\"name\":\"$NS\",\"content\":\"$FQDN_A\",\"ttl\":120}" \
        | jq .

    echo -e "NS=$NS\nENV_MODE=auto" > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    log "NS auto sauvegardé : $NS"
}

# --- Gestion du NS persistant ---
if [[ "$MODE" == "auto" ]]; then
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
        if [[ "${ENV_MODE:-}" == "auto" ]]; then
            log "NS auto existant détecté : $NS"
        else
            log "NS manuel existant → génération d'un nouveau NS auto..."
            generate_ns_auto
        fi
    else
        log "Aucun fichier NS existant → génération NS auto..."
        generate_ns_auto
    fi

elif [[ "$MODE" == "man" ]]; then
    read -rp "Entrez le NameServer (NS) à utiliser : " NS
    echo -e "NS=$NS\nENV_MODE=man" > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    log "NS manuel sauvegardé : $NS"
else
    echo "Mode invalide." >&2
    exit 1
fi

# --- Écriture du NS dans la config ---
echo "$NS" > "$CONFIG_FILE"
log "NS utilisé : $NS"

# --- Clés fixes ---
echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
chmod 600 "$SERVER_KEY"
chmod 644 "$SERVER_PUB"

# --- Kernel tuning pour haute performance ---
log "Application des optimisations réseau..."
cat <<EOF >> /etc/sysctl.conf

net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=524288
net.core.wmem_default=524288
net.core.netdev_max_backlog=250000
net.core.somaxconn=4096
net.ipv4.udp_rmem_min=32768
net.ipv4.udp_wmem_min=32768
net.ipv4.tcp_fin_timeout=10
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_mtu_probing=1
net.ipv4.ip_forward=1
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
EOF
sysctl -p

# --- Désactivation systemd-resolved ---
log "Désactivation systemd-resolved..."
systemctl stop systemd-resolved
systemctl disable systemd-resolved
rm -f /etc/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# --- Wrapper startup SlowDNS ---
cat <<'EOF' > /usr/local/bin/slowdns-start.sh
#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"

wait_for_interface() {
    iface=""
    while [ -z "$iface" ]; do
        iface=$(ip -o link show up | awk -F': ' '{print $2}' \
                    | grep -v '^lo$' \
                    | grep -vE '^(docker|veth|br|virbr|tun|tap|wl|vmnet|vboxnet)' \
                    | head -n1)
        [ -z "$iface" ] && sleep 2
    done
    echo "$iface"
}

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "Détection interface réseau..."
iface=$(wait_for_interface)
log "Interface détectée : $iface"

log "Réglage MTU à 1400..."
ip link set dev "$iface" mtu 1400 || true

NS=$(cat "$CONFIG_FILE")
ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
[ -z "$ssh_port" ] && ssh_port=22

log "Démarrage du serveur SlowDNS..."
exec nice -n -5 "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" "$NS" 0.0.0.0:$ssh_port
EOF

chmod +x /usr/local/bin/slowdns-start.sh

# --- Service systemd SlowDNS ---
cat <<EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS Server Tunnel (DNSTT)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/slowdns-start.sh
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
LimitNPROC=65535
TasksMax=infinity
StandardOutput=file:/var/log/slowdns.log
StandardError=file:/var/log/slowdns.log

[Install]
WantedBy=multi-user.target
EOF

# --- Service SOCAT 53 → 5300 ---
cat <<EOF > /etc/systemd/system/socat53.service
[Unit]
Description=Redirect UDP port 53 → 5300 using socat
After=network.target

[Service]
ExecStart=/usr/bin/socat -v UDP4-RECVFROM:53,fork,reuseaddr UDP4-SENDTO:127.0.0.1:5300
Restart=always
RestartSec=1
LimitNOFILE=1048576
LimitNPROC=65535
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOF

# --- Activation services ---
systemctl daemon-reload
systemctl enable socat53
systemctl restart socat53
systemctl enable slowdns.service
systemctl restart slowdns.service

log "SlowDNS + SOCAT installés avec succès. NS utilisé : $NS"
