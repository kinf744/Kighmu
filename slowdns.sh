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

# --- Cloudflare API (tu peux garder les valeurs existantes) ---
CF_API_TOKEN="7mn4LKcZARvdbLlCVFTtaX7LGM2xsnyjHkiTAt37"
CF_ZONE_ID="7debbb8ea4946898a889c4b5745ab7eb"

# DNS publics pour le serveur lui-même (ne pas rediriger ces adresses)
LOCAL_DNS=("8.8.8.8" "1.1.1.1")

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
apt update -y || true
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

# --- Détection IP publique/VPS principal ---
VPS_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || echo "127.0.0.1")
log "IP principale du VPS : $VPS_IP"

# --- Choix du mode ---
read -rp "Choisissez le mode d'installation [auto/man] : " MODE
MODE=${MODE,,}

generate_ns_auto() {
  DOMAIN="kingom.ggff.net"
  SUB_A="vpn-$(date +%s | sha256sum | head -c 6)"
  FQDN_A="$SUB_A.$DOMAIN"
  log "Création du A : $FQDN_A -> $VPS_IP"

  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"$FQDN_A\",\"content\":\"$VPS_IP\",\"ttl\":300,\"proxied\":false}" | jq .

  SUB_NS="ns-$(date +%s | sha256sum | head -c 6)"
  NS="$SUB_NS.$DOMAIN"
  log "Création du NS : $NS -> $FQDN_A"

  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"NS\",\"name\":\"$NS\",\"content\":\"$FQDN_A\",\"ttl\":300}" | jq .

  echo -e "NS=$NS\nENV_MODE=auto" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  log "NS auto sauvegardé : $NS"
}

# --- Gestion NS persistant ---
if [[ "$MODE" == "auto" ]]; then
  if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
    if [[ "${ENV_MODE:-}" == "auto" ]]; then
      log "NS auto existant détecté : $NS"
    else
      log "NS manuel existant → génération d'un nouveau NS auto..."
      generate_ns_auto
      source "$ENV_FILE"
    fi
  else
    log "Aucun fichier NS existant → génération NS auto..."
    generate_ns_auto
    source "$ENV_FILE"
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
log "Application des optimisations réseau..."
cat > /etc/sysctl.d/99-slowdns.conf <<'EOF'
net.core.rmem_max=26214400
net.core.wmem_max=26214400
net.core.rmem_default=4194304
net.core.wmem_default=4194304
net.core.netdev_max_backlog=50000
net.core.somaxconn=4096
net.ipv4.udp_rmem_min=131072
net.ipv4.udp_wmem_min=131072
net.ipv4.ip_forward=1
EOF
sysctl --system

# --- Wrapper startup SlowDNS corrigé ---
cat > /usr/local/bin/slowdns-start.sh <<'EOF'
#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

iface=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
[ -z "$iface" ] && iface=$(ip -o link show up | awk -F': ' '{print $2}' | grep -v '^lo$' | head -n1)

log "Interface détectée : $iface"

preferred_mtu=1500
if ip link set dev "$iface" mtu "$preferred_mtu" 2>/dev/null; then
  log "MTU réglée à $preferred_mtu"
else
  current_mtu=$(ip -o link show "$iface" | awk '{for(i=1;i<=NF;i++) if($i=="mtu"){print $(i+1); exit}}')
  if [ -n "$current_mtu" ]; then
    ip link set dev "$iface" mtu "$current_mtu" 2>/dev/null || true
    log "MTU fallback conservée : $current_mtu"
  else
    ip link set dev "$iface" mtu 1480 || true
    log "MTU fallback 1480 appliquée"
  fi
fi

NS=$(cat "$CONFIG_FILE" 2>/dev/null || "")
ssh_port=$(ss -tlnp | awk '/sshd/ {print $4; exit}' | sed -n 's/.*:\([0-9]*\)$/\1/p')
[ -z "$ssh_port" ] && ssh_port=22

log "Démarrage du serveur SlowDNS -> UDP :$PORT -> SSH :$ssh_port"
exec nice -n 0 "$SLOWDNS_BIN" -udp ":$PORT" -privkey-file "$SERVER_KEY" "$NS" "0.0.0.0:$ssh_port"
EOF
chmod +x /usr/local/bin/slowdns-start.sh

# --- Service systemd ---
cat > /etc/systemd/system/slowdns.service <<'EOF'
[Unit]
Description=SlowDNS Server Tunnel (DNSTT)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/slowdns-start.sh
Restart=always
RestartSec=3
WatchdogSec=20
TimeoutStartSec=30
LimitNOFILE=1048576
LimitNPROC=65535
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOF

# --- nftables ---
log "Création règles nftables SlowDNS..."
mkdir -p /etc/nftables.d
NFT_FILE="/etc/nftables.d/slowdns.nft"

cat > "$NFT_FILE" <<EOF
table ip slowdns {
    chain prerouting {
        type nat hook prerouting priority -100; policy accept;
        ip saddr != $VPS_IP udp dport 53 redirect to $PORT
    }
    chain output {
        type nat hook output priority -100; policy accept;
        ip daddr { ${LOCAL_DNS[0]}, ${LOCAL_DNS[1]} } udp dport 53 accept
        oifname "lo" accept
        ip daddr $VPS_IP udp dport 53 accept
    }
}
EOF

if ! grep -q '/etc/nftables.d/*.nft' /etc/nftables.conf 2>/dev/null; then
    echo "include \"/etc/nftables.d/*.nft\"" >> /etc/nftables.conf
fi

log "Activation des règles nftables..."
nft -f /etc/nftables.conf || nft list ruleset

# --- Activation services ---
systemctl daemon-reload
systemctl enable slowdns.service
systemctl restart slowdns.service

if ! systemctl is-enabled nftables >/dev/null 2>&1; then
  systemctl enable --now nftables || true
fi

log "Installation terminée. SlowDNS démarré avec règles nftables ciblées."
echo
echo "Résumé :"
echo "- slowdns.service : $(systemctl is-active slowdns.service 2>/dev/null || echo inactive)"
echo "- nftables (table slowdns) :"
nft list table ip slowdns || echo "table slowdns non trouvée"
