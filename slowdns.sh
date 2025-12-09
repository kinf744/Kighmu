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
DEBIAN_FRONTEND=noninteractive apt install -y nftables curl tcpdump jq python3 python3-venv python3-pip

# Activer nftables au boot
systemctl enable nftables
systemctl start nftables

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
    --data "{"type":"A","name":"$FQDN_A","content":"$VPS_IP","ttl":120,"proxied":false}" \
    | jq .

  SUB_NS="ns-$(date +%s | sha256sum | head -c 6)"
  NS="$SUB_NS.$DOMAIN"
  log "Création du NS : $NS -> $FQDN_A"

  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{"type":"NS","name":"$NS","content":"$FQDN_A","ttl":1}" \
    | jq .

  echo -e "NS=$NS
ENV_MODE=auto" > "$ENV_FILE"
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
  echo -e "NS=$NS
ENV_MODE=man" > "$ENV_FILE"
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

# --- Kernel tuning plus agressif ---
log "Application des optimisations réseau (fichier /etc/sysctl.d/99-slowdns.conf)..."
cat > /etc/sysctl.d/99-slowdns.conf <<'EOF'
# SlowDNS tuned settings
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.core.rmem_default=8192000
net.core.wmem_default=8192000
net.core.netdev_max_backlog=60000
net.core.somaxconn=4096
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384
net.ipv4.ip_forward=1
EOF

sysctl --system

# --- Wrapper startup SlowDNS (MTU + dnstt optimisé) ---
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

# MTU adaptée aux tunnels (1400 / 1300)
log "Réglage MTU préférée à 1400 (fallback 1300)..."
if ip link set dev "$iface" mtu 1400 2>/dev/null; then
  log "MTU réglée à 1400"
else
  ip link set dev "$iface" mtu 1300 || true
  log "MTU fallback 1300 appliquée"
fi

NS=$(cat "$CONFIG_FILE" 2>/dev/null || echo "")
ssh_port=$(ss -tlnp | awk '/sshd/ {print $4; exit}' | sed -n 's/.*:([0-9]*)$/\u0001/p')
[ -z "$ssh_port" ] && ssh_port=22

log "Démarrage du serveur SlowDNS (priorité CPU augmentée, MTU dnstt fixée)..."
exec nice -n -5 "$SLOWDNS_BIN" \
  -udp :$PORT \
  -privkey-file "$SERVER_KEY" \
  -mtu 1300 \
  "$NS" 0.0.0.0:$ssh_port
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

# --- nftables : redirection DNS -> SlowDNS ---
mkdir -p /etc/nftables.d

cat > /etc/nftables.d/slowdns.nft <<'EOF'
table ip nat-slowdns {
  chain prerouting {
    type nat hook prerouting priority -100;
    policy accept;
    udp dport 53 redirect to :5300
  }

  chain output {
    type nat hook output priority -100;
    policy accept;
    # Exception pour le DNS local systemd-resolved
    ip daddr 127.0.0.53 udp dport 53 accept
    udp dport 53 redirect to :5300
  }
}
EOF

cat > /etc/systemd/system/nftables-slowdns.service <<'EOF'
[Unit]
Description=nftables NAT redirect UDP 53 -> 5300 for SlowDNS
After=network-online.target nftables.service
Wants=network-online.target nftables.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/nftables.d/slowdns.nft
ExecStop=/usr/sbin/nft delete table ip nat-slowdns || true

[Install]
WantedBy=multi-user.target
EOF

# --- Activation services ---
systemctl daemon-reload

systemctl enable nftables-slowdns.service
systemctl start nftables-slowdns.service

systemctl enable slowdns.service
systemctl restart slowdns.service

log "Installation terminée. SlowDNS démarré avec nftables (REDIRECT UDP 53 -> 5300). NS utilisé : $NS"

echo
echo "Résumé :"
echo "- slowdns.service : $(systemctl is-active slowdns.service 2>/dev/null || echo inactive)"
echo "- nftables-slowdns.service : $(systemctl is-active nftables-slowdns.service 2>/dev/null || echo inactive)"
echo
echo "Règles nftables actives (nat-slowdns) :"
nft list table ip nat-slowdns || echo "Table nat-slowdns absente"
echo
log "Tu peux ajuster la valeur -mtu dans slowdns-start.sh si ton opérateur supporte des paquets plus gros ou si tu veux encore plus de stabilité."
