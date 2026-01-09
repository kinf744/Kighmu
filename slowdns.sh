#!/bin/bash
set -euo pipefail

# ==========================================================
# SlowDNS DNSTT Server – Version finale consolidée
# Debian 11/12 – Ubuntu 20.04+
# Backend : SSH / V2Ray / MIX
# nftables sécurisé – Compatible UDP Request
# ==========================================================

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
ENV_FILE="$SLOWDNS_DIR/slowdns.env"
BACKEND_CONF="$SLOWDNS_DIR/backend.conf"

CF_API_TOKEN="REMPLACE_ICI"
CF_ZONE_ID="REMPLACE_ICI"

PUB_IFACE="eth0"   # ⚠️ ADAPTER À TON VPS

log() { echo "[$(date '+%F %T')] $*"; }

# ===================== ROOT =====================
[[ "$EUID" -ne 0 ]] && { echo "Exécuter en root"; exit 1; }

mkdir -p "$SLOWDNS_DIR"

# ===================== DNS LOCAL =====================
log "Configuration DNS système"
systemctl disable --now systemd-resolved 2>/dev/null || true
chattr -i /etc/resolv.conf 2>/dev/null || true

cat > /etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
options timeout:1 attempts:1
EOF

# ===================== DEPENDANCES =====================
log "Installation dépendances"
apt update -y
apt install -y nftables curl jq python3 python3-venv python3-pip iproute2
systemctl enable --now nftables

# ===================== DNSTT =====================
if [[ ! -x "$SLOWDNS_BIN" ]]; then
  curl -fsSL https://dnstt.network/dnstt-server-linux-amd64 -o "$SLOWDNS_BIN"
  chmod +x "$SLOWDNS_BIN"
fi

# ===================== BACKEND =====================
choose_backend() {
  echo "1) SSH  2) V2Ray  3) MIX"
  read -rp "Choix : " c
  case "$c" in
    1) BACKEND_MODE="ssh" ;;
    2) BACKEND_MODE="v2ray" ;;
    3) BACKEND_MODE="mix" ;;
    *) exit 1 ;;
  esac
  echo "BACKEND_MODE=$BACKEND_MODE" > "$BACKEND_CONF"
}

# ===================== NS =====================
read -rp "Mode NS [auto/man] : " MODE
MODE=${MODE,,}

generate_ns_auto() {
  DOMAIN="kingom.ggff.net"
  VPS_IP=$(curl -s ipv4.icanhazip.com)
  SUB=$(date +%s | sha256sum | cut -c1-6)
  A="vpn-$SUB.$DOMAIN"
  NS="ns-$SUB.$DOMAIN"

  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"$A\",\"content\":\"$VPS_IP\",\"ttl\":120,\"proxied\":false}" >/dev/null

  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"NS\",\"name\":\"$NS\",\"content\":\"$A\",\"ttl\":120}" >/dev/null

  echo -e "NS=$NS\nENV_MODE=auto" > "$ENV_FILE"
  echo "$NS"
}

[[ "$MODE" == "auto" ]] && NS=$(generate_ns_auto) || read -rp "NS : " NS
echo "$NS" > "$CONFIG_FILE"

choose_backend

# ===================== KEYS =====================
cat > "$SERVER_KEY" <<EOF
4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa
EOF

cat > "$SERVER_PUB" <<EOF
2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c
EOF

chmod 600 "$SERVER_KEY"

# ===================== START SCRIPT =====================
cat > /usr/local/bin/slowdns-start.sh <<'EOF'
#!/bin/bash
set -euo pipefail
DIR="/etc/slowdns"

source "$DIR/backend.conf" || BACKEND_MODE="ssh"

case "$BACKEND_MODE" in
  ssh) TARGET="127.0.0.1:22" ;;
  v2ray) TARGET="127.0.0.1:5401" ;;
  mix) TARGET="127.0.0.1:8443" ;;
esac

exec /usr/local/bin/dnstt-server -udp :5300 \
  -privkey-file "$DIR/server.key" \
  "$(cat "$DIR/ns.conf")" "$TARGET"
EOF

chmod +x /usr/local/bin/slowdns-start.sh

# ===================== SYSTEMD =====================
cat > /etc/systemd/system/slowdns.service <<EOF
[Unit]
After=network-online.target
[Service]
ExecStart=/usr/local/bin/slowdns-start.sh
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# ===================== NFTABLES (SOLUTION 1) =====================
cat > /etc/nftables.d/slowdns.nft <<EOF
table inet slowdns {
  chain prerouting {
    type nat hook prerouting priority -100;
    iifname "$PUB_IFACE" udp dport 53 redirect to :5300
  }
  chain input {
    type filter hook input priority 0;
    udp dport 5300 accept
  }
}
EOF

grep -q slowdns.nft /etc/nftables.conf || \
echo 'include "/etc/nftables.d/slowdns.nft"' >> /etc/nftables.conf

systemctl daemon-reload
nft -f /etc/nftables.d/slowdns.nft
systemctl enable --now slowdns

log "✅ SlowDNS opérationnel – UDP Request NON impacté"
