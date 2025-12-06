#!/bin/bash
set -euo pipefail

# ---------- CONFIG ----------
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=53
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
CF_API_TOKEN="7mn4LKcZARvdbLlCVFTtaX7LGM2xsnyjHkiTAt37"
CF_ZONE_ID="7debbb8ea4946898a889c4b5745ab7eb"
DOMAIN="kingom.ggff.net"
DEBUG=true

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
log_debug() { if [ "$DEBUG" = true ]; then echo "[DEBUG] $*"; fi; }

if [ "$EUID" -ne 0 ]; then
    echo "❌ Ce script doit être exécuté en root." >&2
    exit 1
fi

# ---------- Vérification DNS avant installation ----------
check_dns() {
    if ! ping -c 1 1.1.1.1 &>/dev/null; then
        log "⚠️ Résolution DNS problématique, vérification /etc/resolv.conf..."
        # Si pas de résolveur valide, ajoute Cloudflare et Google
        if ! grep -q "1.1.1.1" /etc/resolv.conf; then
            echo "nameserver 1.1.1.1" >> /etc/resolv.conf
        fi
        if ! grep -q "8.8.8.8" /etc/resolv.conf; then
            echo "nameserver 8.8.8.8" >> /etc/resolv.conf
        fi
    fi
}
check_dns

# ---------- Prérequis ----------
log "Installation des paquets requis..."
apt update -y || true
apt install -y curl jq iptables-persistent net-tools || true

mkdir -p "$SLOWDNS_DIR"
chmod 700 "$SLOWDNS_DIR"

# ---------- Fonctions Cloudflare (auto seulement) ----------
verify_cloudflare_token() {
    log "Vérification du token Cloudflare..."
    RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" || true)
    if ! echo "$RESPONSE" | grep -q '"status":"active"' ; then
        echo "❌ Token Cloudflare invalide ou permissions insuffisantes."
        echo "$RESPONSE"
        exit 1
    fi
    log "✔️ Token Cloudflare valide."
}

verify_cloudflare_zone() {
    log "Vérification de la zone Cloudflare..."
    ZONE_INFO=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID" \
        -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" || true)
    if ! echo "$ZONE_INFO" | grep -q '"success":true' ; then
        echo "❌ Zone ID Cloudflare invalide : $CF_ZONE_ID"
        echo "$ZONE_INFO"
        exit 1
    fi
    ZONE_NAME=$(echo "$ZONE_INFO" | jq -r .result.name)
    log_debug "Zone trouvée : $ZONE_NAME"
    if [[ "$DOMAIN" != *"$ZONE_NAME" ]]; then
        echo "❌ Domaine '$DOMAIN' n'appartient pas à la zone Cloudflare '$ZONE_NAME'"
        exit 1
    fi
    log "✔️ Zone Cloudflare valide : $ZONE_NAME"
}

# ---------- Téléchargement DNSTT ----------
if [ ! -x "$SLOWDNS_BIN" ]; then
    log "Téléchargement du binaire DNSTT..."
    curl -L -o "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
    chmod +x "$SLOWDNS_BIN"
fi

# ---------- Choix mode ----------
read -rp "Choisissez le mode d'installation [auto/man] : " MODE
MODE=${MODE,,}

if [[ "$MODE" == "auto" ]]; then
    verify_cloudflare_token
    verify_cloudflare_zone

    log "Mode AUTO sélectionné."
    VPS_IP=$(curl -s ipv4.icanhazip.com)
    SUB_A="vpn-$(date +%s | sha256sum | head -c 6)"
    FQDN_A="$SUB_A.$DOMAIN"

    log "Création de l'enregistrement A : $FQDN_A -> $VPS_IP"
    ADD_A=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$FQDN_A\",\"content\":\"$VPS_IP\",\"ttl\":1,\"proxied\":false}")
    log_debug "Réponse Cloudflare A : $ADD_A"

    SUB_NS="ns-$(date +%s | sha256sum | head -c 6)"
    DOMAIN_NS="$SUB_NS.$DOMAIN"

    log "Création de l'enregistrement NS : $DOMAIN_NS → $FQDN_A"
    ADD_NS=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
        --data "{\"type\":\"NS\",\"name\":\"$DOMAIN_NS\",\"content\":\"$FQDN_A\",\"ttl\":1}")
    log_debug "Réponse Cloudflare NS : $ADD_NS"

elif [[ "$MODE" == "man" ]]; then
    read -rp "Entrez le NS (ex: ns1.exemple.com) : " DOMAIN_NS
else
    echo "❌ Mode invalide."
    exit 1
fi

echo "$DOMAIN_NS" > "$CONFIG_FILE"
log "NS sélectionné : $DOMAIN_NS"

# ---------- Clés serveur (fixes) ----------
cat > "$SERVER_KEY" <<'EOF'
4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa
EOF
chmod 600 "$SERVER_KEY"

cat > "$SERVER_PUB" <<'EOF'
2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c
EOF
chmod 644 "$SERVER_PUB"

# ---------- Optimisations système ----------
log "Application des optimisations noyau..."
cat <<'EOF' >> /etc/sysctl.conf

# ---- Optim DNSTT (UDP heavy) ----
net.core.rmem_max = 2500000
net.core.wmem_max = 2500000
net.core.rmem_default = 2500000
net.core.wmem_default = 2500000
net.ipv4.udp_rmem_min = 2500000
net.ipv4.udp_wmem_min = 2500000
net.core.netdev_max_backlog = 5000
net.core.somaxconn = 1024
net.ipv4.tcp_low_latency = 1
EOF
sysctl -p || true

# ---------- IPTABLES ----------
log "Configuration iptables pour UDP/53 et SSH..."
iptables -I INPUT -p udp --dport 53 -j ACCEPT
iptables -I INPUT -p tcp --dport 53 -j ACCEPT
iptables -I INPUT -p tcp --dport 22 -j ACCEPT
netfilter-persistent save || true
netfilter-persistent reload || true

# ---------- Script démarrage ----------
cat > /usr/local/bin/slowdns-start.sh <<'EOF'
#!/bin/bash
SLOWDNS_DIR="/etc/slowdns"
PORT=53
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SSH_PORT=22

NS=$(cat "$CONFIG_FILE")
exec "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" "$NS" 0.0.0.0:$SSH_PORT
EOF
chmod +x /usr/local/bin/slowdns-start.sh

# ---------- Systemd service ----------
cat > /etc/systemd/system/slowdns.service <<'EOF'
[Unit]
Description=SlowDNS Tunnel (DNSTT) - SSH only
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStartPre=/bin/sleep 2
ExecStart=/usr/local/bin/slowdns-start.sh
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
Nice=-5
SyslogIdentifier=slowdns
CPUAffinity=0
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now slowdns.service || true
systemctl restart slowdns.service || true

log "✔️ SlowDNS (SSH-only) installé et démarré."
log "✔️ NS utilisé : $(cat $CONFIG_FILE)"
