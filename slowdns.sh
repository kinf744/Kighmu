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
BACKEND_CONF="$SLOWDNS_DIR/backend.conf"

# --- Cloudflare API (actuel) ---
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

# --- Désactivation propre de systemd-resolved pour éviter blocages DNS ---
systemctl disable --now systemd-resolved.service || true
rm -f /etc/resolv.conf
cat <<EOF > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
options timeout:1
options attempts:1
EOF
chattr +i /etc/resolv.conf

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
source "$SLOWDNS_DIR/venv/bin/activate"
pip install --upgrade pip >/dev/null
pip install cloudflare >/dev/null || log "pip install cloudflare failed (non fatal here)"

# --- DNSTT (binaire) ---
if [ ! -x "$SLOWDNS_BIN" ]; then
  log "Téléchargement du binaire DNSTT..."
  curl -fsSL -o "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
  chmod +x "$SLOWDNS_BIN"
fi

# --- Choix du backend (SSH / V2Ray / MIX) ---
choose_backend() {
    echo ""
    echo "+--------------------------------------------+"
    echo "|      CHOIX DU MODE BACKEND SLOWDNS         |"
    echo "+--------------------------------------------+"
    echo "1) SSH direct (DNSTT → 0.0.0.0:22)"
    echo "2) V2Ray direct (DNSTT → 0.0.0.0:5401)"
    echo "3) MIX (DNSTT → 0.0.0.0:5401, V2Ray gère SSH + VLESS/VMESS/Trojan)"
    echo ""
    read -rp "Sélectionnez le mode [1-3] : " mode
    case "$mode" in
        1) BACKEND_MODE="ssh" ;;
        2) BACKEND_MODE="v2ray" ;;
        3) BACKEND_MODE="mix" ;;
        *) echo "Mode invalide."; exit 1 ;;
    esac
    echo "BACKEND_MODE=$BACKEND_MODE" > "$BACKEND_CONF"
    log "Mode backend sélectionné : $BACKEND_MODE"
}

# --- Choix du mode NS ---
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
    | jq . || log "Création A Cloudflare retournée avec erreur"

  SUB_NS="ns-$(date +%s | sha256sum | head -c 6)"
  NS="$SUB_NS.$DOMAIN"
  log "Création du NS : $NS -> $FQDN_A"

  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{"type":"NS","name":"$NS","content":"$FQDN_A","ttl":120}" \
    | jq . || log "Création NS Cloudflare retournée avec erreur"

  echo -e "NS=$NS
ENV_MODE=auto" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  log "NS auto sauvegardé : $NS"
}

# --- Gestion du NS persistant ---
if [[ "$MODE" == "auto" ]]; then
  if [[ -f "$ENV_FILE" ]]; then
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
  echo -e "NS=$NS
ENV_MODE=man" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  log "NS manuel sauvegardé : $NS"
else
  echo "Mode invalide." >&2
  exit 1
fi

# --- Choix backend AVANT écriture config ---
choose_backend

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

# --- Kernel tuning optimisé pour tunnel UDP ---
log "Application des optimisations réseau..."
cat > /etc/sysctl.d/99-slowdns.conf <<'EOF'
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.core.rmem_default=8192000
net.core.wmem_default=8192000
net.core.netdev_max_backlog=60000
net.core.somaxconn=4096
net.ipv4.udp_rmem_min=32768
net.ipv4.udp_wmem_min=32768
net.ipv4.udp_mem=4096 87380 268435456
net.core.optmem_max=65536
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.neigh.default.gc_thresh1=4096
net.ipv4.neigh.default.gc_thresh2=8192
net.ipv4.neigh.default.gc_thresh3=16384
EOF
sysctl --system >/dev/null || log "sysctl apply returned non-zero"

# --- Fonction select_backend_target pour le wrapper ---
select_backend_target() {
    local mode target ssh_port
    mode="ssh"
    if [ -f "$BACKEND_CONF" ]; then
        # shellcheck disable=SC1090
        source "$BACKEND_CONF"
        mode="${BACKEND_MODE:-ssh}"
    fi

    case "$mode" in
        ssh)
            # SSH direct
            ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
            [ -z "$ssh_port" ] && ssh_port=22
            target="0.0.0.0:$ssh_port"
            printf '[%s] Mode backend : SSH (%s)
' "$(date '+%Y-%m-%d %H:%M:%S')" "$target" >&2
            ;;
        v2ray)
            # V2Ray direct uniquement
            target="0.0.0.0:5401"
            printf '[%s] Mode backend : V2Ray (%s)
' "$(date '+%Y-%m-%d %H:%M:%S')" "$target" >&2
            ;;
        mix)
            # MIX : V2Ray 5401 (qui pourra gérer SSH, VLESS, VMESS, TROJAN)
            target="0.0.0.0:5401"
            printf '[%s] Mode backend : MIX (via V2Ray %s)
' "$(date '+%Y-%m-%d %H:%M:%S')" "$target" >&2
            ;;
        *)
            # fallback
            target="0.0.0.0:22"
            printf '[%s] Mode backend inconnu, fallback SSH (%s)
' "$(date '+%Y-%m-%d %H:%M:%S')" "$target" >&2
            ;;
    esac
    echo "$target"
}

# --- Wrapper SlowDNS startup (MTU dynamique + backend multi-mode) ---
cat > /usr/local/bin/slowdns-start.sh <<EOF
#!/bin/bash
set -euo pipefail
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
BACKEND_CONF="$SLOWDNS_DIR/backend.conf"

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

select_backend_target() {
$(declare -f select_backend_target)
}

iface=$(wait_for_interface)
log "Interface détectée : $iface"

# MTU dynamique
for mtu in 1500 1450 1400 1300 932; do
  if ping -M do -s $((mtu-28)) -c 1 1.1.1.1 >/dev/null 2>&1; then
    ip link set dev "$iface" mtu $mtu || true
    log "MTU réglée à $mtu"
    break
  fi
done

NS=$(cat "$CONFIG_FILE" 2>/dev/null || echo "")
backend_target=$(select_backend_target)

log "Démarrage SlowDNS → $backend_target"
exec nice -n 0 "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" "$NS" "$backend_target"
EOF

chmod +x /usr/local/bin/slowdns-start.sh

# --- Service systemd ---
cat > /etc/systemd/system/slowdns.service <<'EOF'
[Unit]
Description=SlowDNS Server Tunnel (DNSTT) - Multi Backend
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
StandardOutput=append:/var/log/slowdns.log
StandardError=append:/var/log/slowdns.log

[Install]
WantedBy=multi-user.target
EOF

# --- nftables optimisée pour SlowDNS ---
mkdir -p /etc/nftables.d
cat > /etc/nftables.d/slowdns.nft <<'EOF'
table inet slowdns {
  chain prerouting {
    type nat hook prerouting priority -100; policy accept;
    udp dport 53 redirect to :5300
  }
  chain input {
    type filter hook input priority 0; policy accept;
    udp dport 5300 accept
  }
}
EOF

# Ajout persistant
if ! grep -q "/etc/nftables.d/slowdns.nft" /etc/nftables.conf 2>/dev/null; then
  echo 'include "/etc/nftables.d/slowdns.nft"' >> /etc/nftables.conf
fi

# --- systemd pour nftables SlowDNS ---
cat > /etc/systemd/system/nftables-slowdns.service <<'EOF'
[Unit]
Description=nftables NAT redirect UDP 53 -> 5300 for SlowDNS
After=network-online.target nftables.service
Wants=network-online.target nftables.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/nftables.d/slowdns.nft
ExecStop=/usr/sbin/nft delete table inet slowdns || true

[Install]
WantedBy=multi-user.target
EOF

# --- Activation services ---
systemctl daemon-reload
systemctl enable nftables-slowdns.service
systemctl start nftables-slowdns.service
systemctl enable slowdns.service
systemctl restart slowdns.service

log "Installation terminée."
log "SlowDNS démarré avec nftables (REDIRECT UDP 53 -> 5300). NS: $NS | Backend: $BACKEND_MODE"
echo "Clé publique : $(cat "$SERVER_PUB")"
echo "Configuration : $NS → $BACKEND_MODE"
