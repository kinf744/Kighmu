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

# --- Cloudflare API (tu peux remplacer par tes valeurs) ---
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
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y nftables curl tcpdump jq python3 python3-venv python3-pip iproute2

# Activer nftables au boot
systemctl enable nftables
systemctl start nftables

# --- Création venv et paquet Cloudflare python ---
if [ ! -d "$SLOWDNS_DIR/venv" ]; then
  python3 -m venv "$SLOWDNS_DIR/venv"
fi
# shellcheck disable=SC1090
source "$SLOWDNS_DIR/venv/bin/activate"
pip install --upgrade pip >/dev/null
pip install cloudflare >/dev/null || log "pip install cloudflare failed (non fatal here)"

# --- DNSTT (binaire) ---
if [ ! -x "$SLOWDNS_BIN" ]; then
  log "Téléchargement du binaire DNSTT..."
  curl -fsSL -o "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
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

  # Note: échoue proprement si Cloudflare refuse
  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"$FQDN_A\",\"content\":\"$VPS_IP\",\"ttl\":120,\"proxied\":false}" \
    | jq . || log "Création A Cloudflare retournée avec erreur"

  SUB_NS="ns-$(date +%s | sha256sum | head -c 6)"
  NS="$SUB_NS.$DOMAIN"
  log "Création du NS : $NS -> $FQDN_A"

  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"NS\",\"name\":\"$NS\",\"content\":\"$FQDN_A\",\"ttl\":120}" \
    | jq . || log "Création NS Cloudflare retournée avec erreur"

  echo -e "NS=$NS\nENV_MODE=auto" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  log "NS auto sauvegardé : $NS"
}

# --- Gestion du NS persistant ---
if [[ "$MODE" == "auto" ]]; then
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    if [[ "${ENV_MODE:-}" == "auto" && -n "${NS:-}" ]]; then
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

# --- Clés fixes (si tu veux les remplacer, mets tes propres clés) ---
cat > "$SERVER_KEY" <<'KEY'
4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa
KEY
cat > "$SERVER_PUB" <<'PUB'
2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c
PUB
chmod 600 "$SERVER_KEY"
chmod 644 "$SERVER_PUB"

# --- Kernel tuning plus agressif (ajout des paramètres UDP importants) ---
log "Application des optimisations réseau (fichier /etc/sysctl.d/99-slowdns.conf)..."
cat > /etc/sysctl.d/99-slowdns.conf <<'EOF'
# SlowDNS tuned settings
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.core.rmem_default=8192000
net.core.wmem_default=8192000
net.core.netdev_max_backlog=60000
net.core.somaxconn=4096
net.ipv4.udp_rmem_min=32768
net.ipv4.udp_wmem_min=32768
net.ipv4.ip_forward=1

# UDP memory tuning
net.ipv4.udp_mem=4096 87380 268435456
net.core.optmem_max=65536

# Avoid packet drops for tunneled traffic
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0

# ARP/neighbor thresholds (avoid GC pauses)
net.ipv4.neigh.default.gc_thresh1=4096
net.ipv4.neigh.default.gc_thresh2=8192
net.ipv4.neigh.default.gc_thresh3=16384
EOF

sysctl --system >/dev/null || log "sysctl apply returned non-zero (check) "

# --- Wrapper startup SlowDNS (MTU dynamique + dnstt optimisé) ---
cat > /usr/local/bin/slowdns-start.sh <<'EOF'
#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Detect first non-loopback, non-virtual interface that is up
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

# MTU test: try large MTU then fallback to smaller one
log "Test MTU path MTU discovery..."
if ping -M do -s 1472 -c 1 1.1.1.1 >/dev/null 2>&1; then
  ip link set dev "$iface" mtu 1500 || true
  log "MTU réglée à 1500"
elif ping -M do -s 1412 -c 1 1.1.1.1 >/dev/null 2>&1; then
  ip link set dev "$iface" mtu 1450 || true
  log "MTU réglée à 1450"
else
  ip link set dev "$iface" mtu 1300 || true
  log "MTU fallback 1300 appliquée"
fi

NS=$(cat "$CONFIG_FILE" 2>/dev/null || echo "")
# Détection port SSH: d'abord sshd_config, sinon ss
ssh_port=""
if [ -f /etc/ssh/sshd_config ]; then
  ssh_port=$(awk '/^Port /{print $2; exit}' /etc/ssh/sshd_config || true)
fi
if [ -z "$ssh_port" ]; then
  ssh_port=$(ss -tlnp 2>/dev/null | awk -F: '/sshd/ {print $NF; exit}' || true)
fi
[ -z "$ssh_port" ] && ssh_port=22

log "Démarrage du serveur SlowDNS (priorité CPU augmentée, MTU dnstt fixée)..."
# -mtu réduit la taille utile (évite fragmentation côté UDP)
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

# --- nftables : redirection DNS -> SlowDNS (optimisée) ---
mkdir -p /etc/nftables.d

cat > /etc/nftables.d/slowdns.nft <<'EOF'
table ip nat-slowdns {
  chain prerouting {
    type nat hook prerouting priority -100;
    policy accept;
    # Prioritize DNS-to-slowdns redirect to reduce jitter
    udp dport 53 meta priority 0 redirect to :5300
  }

  chain output {
    type nat hook output priority -100;
    policy accept;
    # Exception pour le DNS local systemd-resolved
    ip daddr 127.0.0.53 udp dport 53 accept
    udp dport 53 meta priority 0 redirect to :5300
  }
}
EOF

# Ensure nftables main config includes our file (persistent across reboots)
if ! grep -q "/etc/nftables.d/slowdns.nft" /etc/nftables.conf 2>/dev/null; then
  echo "include \"/etc/nftables.d/slowdns.nft\"" >> /etc/nftables.conf
  log "Ajout de l'inclusion slowdns.nft dans /etc/nftables.conf"
fi

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
systemctl start nftables-slowdns.service || log "nftables-slowdns start failed"

systemctl enable slowdns.service
systemctl restart slowdns.service || log "slowdns service restart failed"

log "Installation terminée. SlowDNS démarré avec nftables (REDIRECT UDP 53 -> 5300). NS utilisé : $NS"

echo
echo "Résumé :"
echo "- slowdns.service : $(systemctl is-active slowdns.service 2>/dev/null || echo inactive)"
echo "- nftables-slowdns.service : $(systemctl is-active nftables-slowdns.service 2>/dev/null || echo inactive)"
echo
echo "Règles nftables actives (nat-slowdns) :"
nft list table ip nat-slowdns || echo "Table nat-slowdns absente"
echo

log "Conseils finaux :"
log " - Si tu constates encore des pertes, baisse -mtu (ex: 1100) ou augmente la mémoire UDP côté kernel."
log " - Pense à régénérer ton token Cloudflare et tes clés privées si elles sont publiques."
log " - Teste en premier sur une VM non critique."
