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
PORT=5300
SSH_PORT=22

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
    curl -L -o "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
    chmod +x "$SLOWDNS_BIN"
fi

# ---------- Clés fixes ----------
cat > "$SERVER_KEY" <<'EOF'
4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa
EOF
chmod 600 "$SERVER_KEY"

cat > "$SERVER_PUB" <<'EOF'
2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c
EOF
chmod 644 "$SERVER_PUB"
log "Clés fixes installées."

# ---------- Choix mode ----------
read -rp "Choisissez le mode d'installation [auto/man] : " MODE
MODE=${MODE,,}

if [[ "$MODE" == "auto" ]]; then
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
else
    echo "❌ Mode invalide."
    exit 1
fi

# ---------- Enregistrement NS dans ns.conf ----------
echo "$DOMAIN_NS" > "$CONFIG_FILE"
log "NS pour le client enregistré dans ns.conf : $DOMAIN_NS"

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
iptables -I INPUT -p udp --dport $PORT -j ACCEPT
iptables -I INPUT -p tcp --dport $SSH_PORT -j ACCEPT
netfilter-persistent save >/dev/null 2>&1 || true
netfilter-persistent reload >/dev/null 2>&1 || true

# ---------- Script démarrage ----------
cat > /usr/local/bin/slowdns-start.sh <<EOF
#!/bin/bash
SLOWDNS_BIN="$SLOWDNS_BIN"
SERVER_KEY="$SERVER_KEY"
NS="\$(cat "$CONFIG_FILE")"
exec "\$SLOWDNS_BIN" -udp :$PORT -privkey-file "\$SERVER_KEY" "\$NS" 0.0.0.0:$SSH_PORT
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
log "✔️ Clé publique (à mettre dans le client) :"
cat "$SERVER_PUB"
