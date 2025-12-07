#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
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
    echo "❌ Ce script doit être exécuté en root."
    exit 1
fi

# ---------- Détection IP publique ----------
log "Détection IP publique..."
PUBLIC_IP=$(hostname -I | awk '{print $1}')
if [[ -z "$PUBLIC_IP" ]]; then
    echo "❌ Impossible de détecter l'IP publique."
    exit 1
fi
log "IP publique détectée : $PUBLIC_IP"

# ---------- Installation DNSTT ----------
mkdir -p "$SLOWDNS_DIR"
if [[ ! -f "$SLOWDNS_BIN" ]]; then
    log "Téléchargement dnstt-server..."
    wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/ycd/dnstt/main/dnstt-server
    chmod +x "$SLOWDNS_BIN"
fi

# ---------- Clés fixes ----------
if [[ ! -f "$SERVER_KEY" ]] || [[ ! -f "$SERVER_PUB" ]]; then
    log "Création clés DNSTT (fixes)..."
    $SLOWDNS_BIN -gen-key -privkey "$SERVER_KEY" -pubkey "$SERVER_PUB"
else
    log "Clés existantes détectées : pas de régénération."
fi

# ---------- Choix mode ----------
read -rp "Choisissez le mode d'installation [auto/man] : " MODE
MODE=${MODE,,}

if [[ "$MODE" == "auto" ]]; then
    # Création A + NS automatiques
    SUB_A="vpn-$(date +%s | sha256sum | head -c 6)"
    FQDN_A="$SUB_A.$DOMAIN"
    SUB_NS="ns-$(date +%s | sha256sum | head -c 6)"
    DOMAIN_NS="$SUB_NS.$DOMAIN"

    log "Mode AUTO sélectionné."
    log "Création enregistrement A : $FQDN_A -> $PUBLIC_IP"
    ADD_A=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$FQDN_A\",\"content\":\"$PUBLIC_IP\",\"ttl\":1,\"proxied\":false}")
    log_debug "Réponse Cloudflare A : $ADD_A"

    log "Création enregistrement NS : $DOMAIN_NS -> $FQDN_A"
    ADD_NS=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"NS\",\"name\":\"$DOMAIN_NS\",\"content\":\"$FQDN_A\",\"ttl\":1}")
    log_debug "Réponse Cloudflare NS : $ADD_NS"

elif [[ "$MODE" == "man" ]]; then
    read -rp "Entrez le NS pour le client (ex: ns1.example.com) : " DOMAIN_NS
    FQDN_A="$DOMAIN"   # Le serveur DNSTT utilisera toujours le domaine principal / A-record existant
else
    echo "❌ Mode invalide."
    exit 1
fi

# ---------- Configuration DNSTT ----------
echo "$FQDN_A" > "$CONFIG_FILE"
log "A-record utilisé par DNSTT : $FQDN_A"
log "NS pour le client : $DOMAIN_NS"

# ---------- Optimisations système ----------
log "Application des optimisations noyau..."
cat <<'EOF' >/etc/sysctl.d/slowdns-opt.conf
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
sysctl --system >/dev/null

# ---------- IPTABLES ----------
log "Configuration iptables..."
iptables -I INPUT -p udp --dport 53 -j ACCEPT
iptables -I INPUT -p tcp --dport 22 -j ACCEPT
netfilter-persistent save >/dev/null 2>&1 || true
netfilter-persistent reload >/dev/null 2>&1 || true

# ---------- Script démarrage ----------
cat > /usr/local/bin/slowdns-start.sh <<EOF
#!/bin/bash
SLOWDNS_BIN="$SLOWDNS_BIN"
SERVER_KEY="$SERVER_KEY"
CONFIG_FILE="$CONFIG_FILE"
DOMAIN=\$(cat "\$CONFIG_FILE")
exec "\$SLOWDNS_BIN" -udp $PUBLIC_IP:53 -privkey-file "\$SERVER_KEY" "\$DOMAIN" 127.0.0.1:22
EOF
chmod +x /usr/local/bin/slowdns-start.sh

# ---------- Systemd service ----------
cat > /etc/systemd/system/slowdns.service <<EOF
[Unit]
Description=SlowDNS Tunnel DNSTT (SSH)
After=network.target

[Service]
Type=simple
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
log "✔️ NS pour le client : $DOMAIN_NS"
log "✔️ A-record utilisé par le serveur DNSTT : $FQDN_A"
log "✔️ Clé publique (à mettre dans le client) :"
cat "$SERVER_PUB"
