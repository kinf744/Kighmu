#!/bin/bash
set -euo pipefail

##########################################################
# SlowDNS DNSTT Server - FINAL STABLE
# Debian 11/12 - Ubuntu 20.04+
# Backend : SSH / V2Ray / MIX
# Cohabitation parfaite avec UDP Request
##########################################################

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT="5300"
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
ENV_FILE="$SLOWDNS_DIR/slowdns.env"
BACKEND_CONF="$SLOWDNS_DIR/backend.conf"

CF_API_TOKEN="7mn4LKcZARvdbLlCVFTtaX7LGM2xsnyjHkiTAt37"
CF_ZONE_ID="7debbb8ea4946898a889c4b5745ab7eb"

PUB_IFACE="eth0"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

[[ "$EUID" -ne 0 ]] && echo "Exécuter en root" && exit 1
mkdir -p "$SLOWDNS_DIR"

# ================= DNS LOCAL =================
systemctl disable --now systemd-resolved >/dev/null 2>&1 || true
chattr -i /etc/resolv.conf 2>/dev/null || true
cat > /etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
options timeout:1
options attempts:1
EOF

# ================= DEPENDANCES =================
apt update -y
apt install -y nftables curl jq python3 python3-venv python3-pip iproute2
systemctl enable --now nftables

# ================= PYTHON =================
python3 -m venv "$SLOWDNS_DIR/venv" 2>/dev/null || true
source "$SLOWDNS_DIR/venv/bin/activate"
pip install -q --upgrade pip cloudflare || true

# ================= DNSTT =================
if [[ ! -x "$SLOWDNS_BIN" ]]; then
  curl -fsSL https://dnstt.network/dnstt-server-linux-amd64 -o "$SLOWDNS_BIN"
  chmod +x "$SLOWDNS_BIN"
fi

# ================= BACKEND =================
choose_backend() {
  echo "1) SSH  2) V2Ray  3) MIX"
  read -rp "Choix backend : " c
  case "$c" in
    1) BACKEND_MODE="ssh" ;;
    2) BACKEND_MODE="v2ray" ;;
    3) BACKEND_MODE="mix" ;;
    *) exit 1 ;;
  esac
  echo "BACKEND_MODE=$BACKEND_MODE" > "$BACKEND_CONF"
}
choose_backend

# ================= NS =================
read -rp "Mode NS [auto/man] : " MODE
MODE=${MODE,,}

generate_ns_auto() {
  DOMAIN="kingom.ggff.net"
  VPS_IP=$(curl -s ipv4.icanhazip.com)
  ID=$(date +%s | sha256sum | cut -c1-6)
  A="vpn-$ID.$DOMAIN"
  NS="ns-$ID.$DOMAIN"

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

if [[ "$MODE" == "auto" ]]; then
  [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
  [[ -z "${NS:-}" ]] && NS=$(generate_ns_auto)
else
  read -rp "Entrez NS : " NS
  echo -e "NS=$NS\nENV_MODE=man" > "$ENV_FILE"
fi

echo "$NS" > "$CONFIG_FILE"

# ================= KEYS =================
cat > "$SERVER_KEY" <<EOF
4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa
EOF

cat > "$SERVER_PUB" <<EOF
2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c
EOF

chmod 600 "$SERVER_KEY"

# ================= SYSCTL =================
cat > /etc/sysctl.d/99-slowdns.conf <<EOF
net.ipv4.ip_forward=1
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.core.netdev_max_backlog=60000
EOF
sysctl --system >/dev/null

# ================= START SCRIPT =================
cat > /usr/local/bin/slowdns-start.sh <<'EOF'
#!/bin/bash
set -e
DIR="/etc/slowdns"
BIN="/usr/local/bin/dnstt-server"
source "$DIR/backend.conf" 2>/dev/null || BACKEND_MODE="ssh"

case "$BACKEND_MODE" in
  ssh) TARGET="127.0.0.1:22" ;;
  v2ray) TARGET="127.0.0.1:5401" ;;
  mix) TARGET="127.0.0.1:8443" ;;
esac

exec "$BIN" -udp 127.0.0.1:5300 \
  -privkey-file "$DIR/server.key" \
  "$(cat "$DIR/ns.conf")" "$TARGET"
EOF
chmod +x /usr/local/bin/slowdns-start.sh

# ================= SYSTEMD =================
cat > /etc/systemd/system/slowdns.service <<EOF
[Unit]
Description=SlowDNS DNSTT Server
After=network-online.target
[Service]
ExecStart=/usr/local/bin/slowdns-start.sh
Restart=always
RestartSec=3
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOF

# ================= NFTABLES SAFE =================
cat > /etc/nftables.d/slowdns.nft <<EOF
table inet slowdns {
  chain output {
    type nat hook output priority -100;
    udp dport 53 redirect to :5300
  }
  chain input {
    type filter hook input priority 0;
    ip saddr 127.0.0.1 udp dport 5300 accept
  }
}
EOF

grep -q slowdns.nft /etc/nftables.conf || \
echo 'include "/etc/nftables.d/slowdns.nft"' >> /etc/nftables.conf

nft -f /etc/nftables.d/slowdns.nft
systemctl daemon-reload
systemctl enable --now slowdns

log "✅ SlowDNS STABLE + UDP Request COMPATIBLE"
