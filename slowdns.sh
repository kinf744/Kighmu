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
DEBIAN_FRONTEND=noninteractive apt install -y curl jq python3 python3-venv python3-pip nftables tcpdump

# --- Création venv et paquet Cloudflare python ---
if [ ! -d "$SLOWDNS_DIR/venv" ]; then
  python3 -m venv "$SLOWDNS_DIR/venv"
fi
source "$SLOWDNS_DIR/venv/bin/activate"
pip install --upgrade pip >/dev/null
pip install cloudflare >/dev/null

# --- DNSTT (binaire) ---
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
  VPS_IP=$(curl -s ipv4.icanhazip.com || echo "127.0.0.1")

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
    --data "{\"type\":\"NS\",\"name\":\"$NS\",\"content\":\"$FQDN_A\",\"ttl\":1}" \
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
chmod 644 "$CONFIG_FILE"
log "NS utilisé : $NS"

# --- Clés fixes ---
cat > "$SERVER_KEY" <<'KEY'
4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa
KEY
cat > "$SERVER_PUB" <<'PUB'
2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c
PUB
chmod 600 "$SERVER_KEY"
chmod 644 "$SERVER_PUB"

# --- Kernel tuning ---
log "Application des optimisations réseau (fichier /etc/sysctl.d/99-slowdns.conf)..."
cat > /etc/sysctl.d/99-slowdns.conf <<'EOF'
net.core.rmem_max=26214400
net.core.wmem_max=26214400
net.core.rmem_default=524288
net.core.wmem_default=524288
net.core.netdev_max_backlog=50000
net.core.somaxconn=4096
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
net.ipv4.ip_forward=1
EOF
sysctl --system

# --- Wrapper startup SlowDNS ---
cat > /usr/local/bin/slowdns-start.sh <<'EOF'
#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

wait_for_interface() {
  local iface=""
  while [ -z "$iface" ]; do
    iface=$(ip -o link show up | awk -F': ' '{print $2}' \
      | grep -v '^lo$' \
      | grep -vE '^(docker|veth|br|virbr|tun|tap|wl|vmnet|vboxnet)' \
      | head -n1)
    [ -z "$iface" ] && sleep 1
  done
  echo "$iface"
}

log "Détection interface réseau..."
iface=$(wait_for_interface)
log "Interface détectée : $iface"

log "Réglage MTU préféré à 1500 (fallback 1480)..."
if ip link set dev "$iface" mtu 1500 2>/dev/null; then
  log "MTU réglée à 1500"
else
  ip link set dev "$iface" mtu 1480 || true
  log "MTU fallback 1480 appliquée"
fi

NS=$(cat "$CONFIG_FILE" 2>/dev/null || echo "")
ssh_port=$(ss -tlnp | awk '/sshd/ {print $4; exit}' | sed -n 's/.*:\([0-9]*\)$/\1/p')
[ -z "$ssh_port" ] && ssh_port=22

log "Démarrage du serveur SlowDNS (nice 0)..."
exec nice -n 0 "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" "$NS" 0.0.0.0:$ssh_port
EOF
chmod +x /usr/local/bin/slowdns-start.sh

# --- Service systemd SlowDNS ---
cat > /etc/systemd/system/slowdns.service <<'EOF'
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

[Install]
WantedBy=multi-user.target
EOF

# --- Configuration nftables ---
log "Création règles nftables SlowDNS..."
mkdir -p /etc/nftables.d
NFT_FILE="/etc/nftables.d/slowdns.nft"

cat > "$NFT_FILE" <<'EOF'
flush table ip slowdns

table ip slowdns {
    chain prerouting {
        type nat hook prerouting priority -100;
        udp dport 53 redirect to 5300
    }

    chain output {
        type nat hook output priority -100;
        udp dport 53 redirect to 5300
    }
}
EOF

if ! grep -q "/etc/nftables.d/*.nft" /etc/nftables.conf 2>/dev/null; then
    echo "include \"/etc/nftables.d/*.nft\"" >> /etc/nftables.conf
fi

nft -f /etc/nftables.conf

# --- Service systemd nftables ---
cat > /etc/systemd/system/nftables-redirect.service <<'EOF'
[Unit]
Description=SlowDNS nftables redirect (UDP 53 → 5300)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/nft -f /etc/nftables.conf
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# --- Activation services ---
systemctl daemon-reload
systemctl enable nftables-redirect.service
systemctl start nftables-redirect.service
systemctl enable slowdns.service
systemctl restart slowdns.service

# --- Résumé ---
log "Installation terminée. SlowDNS démarré avec nftables REDIRECT actif."

echo
echo "Résumé :"
echo "- slowdns.service : $(systemctl is-active slowdns.service 2>/dev/null || echo inactive)"
echo "- nftables-redirect.service : $(systemctl is-active nftables-redirect.service 2>/dev/null || echo inactive)"
echo "- Règles nftables NAT SlowDNS :"
nft list table ip slowdns
