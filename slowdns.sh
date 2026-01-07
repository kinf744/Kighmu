#!/bin/bash
set -euo pipefail

# ==========================================================
# SLOWDNS INSTALL AUTOMATIQUE (ONE-LINER)
# ==========================================================

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300
MTU=1300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
ENV_FILE="$SLOWDNS_DIR/slowdns.env"

CF_API_TOKEN="7mn4LKcZARvdbLlCVFTtaX7LGM2xsnyjHkiTAt37"
CF_ZONE_ID="7debbb8ea4946898a889c4b5745ab7eb"
DOMAIN="kingom.ggff.net"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

check_root() {
  [[ $EUID -ne 0 ]] && { echo "Ce script doit être exécuté en root."; exit 1; }
}

cleanup() {
  log "Nettoyage installation SlowDNS..."
  systemctl stop slowdns.service 2>/dev/null || true
  systemctl disable slowdns.service 2>/dev/null || true
  rm -f /etc/systemd/system/slowdns.service
  rm -f /usr/local/bin/slowdns-start.sh
  rm -rf "$SLOWDNS_DIR"
  systemctl daemon-reload
}

install_dependencies() {
  log "Installation dépendances..."
  apt-get update -q
  apt-get install -y nftables wget curl jq python3 dnsutils
}

install_slowdns_bin() {
  mkdir -p "$(dirname "$SLOWDNS_BIN")"
  log "Téléchargement binaire SlowDNS..."
  wget -q -O "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
  chmod +x "$SLOWDNS_BIN"
  [[ ! -x "$SLOWDNS_BIN" ]] && { echo "Erreur téléchargement SlowDNS"; exit 1; }
}

install_fixed_keys() {
  mkdir -p "$SLOWDNS_DIR"
  echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
  echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
  chmod 600 "$SERVER_KEY"
  chmod 644 "$SERVER_PUB"
}

disable_systemd_resolved() {
  log "Désactivation systemd-resolved..."
  if systemctl list-unit-files | grep -q "^systemd-resolved.service"; then
    systemctl stop systemd-resolved || true
    systemctl disable systemd-resolved || true
  fi
  rm -f /etc/resolv.conf
  echo "nameserver 8.8.8.8" > /etc/resolv.conf
}

configure_nftables() {
  log "Configuration nftables..."
  systemctl enable nftables >/dev/null 2>&1 || true
  systemctl start nftables >/dev/null 2>&1 || true
  nft flush table inet slowdns || true
  nft add table inet slowdns
  nft add chain inet slowdns input { type filter hook input priority 0 \; policy accept \; }
  nft add rule inet slowdns input ct state established,related accept
  nft add rule inet slowdns input iif lo accept
  nft add rule inet slowdns input udp dport "$PORT" accept
  nft add rule inet slowdns input tcp dport 22 accept
}

create_ns_cloudflare() {
  VPS_IP=$(curl -s ifconfig.me || curl -s icanhazip.com)
  [[ -z "$VPS_IP" ]] && { echo "Impossible de détecter IP"; exit 1; }
  SUB_A="a$(date +%s | tail -c6)"
  SUB_NS="ns$(date +%s | tail -c6)"
  A_FQDN="$SUB_A.$DOMAIN"
  NS_FQDN="$SUB_NS.$DOMAIN"

  log "Création A record : $A_FQDN -> $VPS_IP"
  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"$A_FQDN\",\"content\":\"$VPS_IP\",\"ttl\":120,\"proxied\":false}" | jq -e '.success' >/dev/null

  log "Création NS record : $NS_FQDN -> $A_FQDN"
  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"NS\",\"name\":\"$NS_FQDN\",\"content\":\"$A_FQDN\",\"ttl\":120}" | jq -e '.success' >/dev/null
  echo "$NS_FQDN"
}

create_env() {
  NS=$(create_ns_cloudflare)
  echo "$NS" > "$CONFIG_FILE"
  cat <<EOF > "$ENV_FILE"
NS=$NS
PUB_KEY=$(cat "$SERVER_PUB")
PRIV_KEY=$(cat "$SERVER_KEY")
BACKEND=ssh
MODE=auto
EOF
  chmod 600 "$ENV_FILE"
}

create_wrapper() {
  cat <<'EOF' > /usr/local/bin/slowdns-start.sh
#!/bin/bash
set -euo pipefail
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300
MTU=1300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
ENV_FILE="$SLOWDNS_DIR/slowdns.env"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
[[ -f "$ENV_FILE" ]] || { echo "Fichier $ENV_FILE manquant"; exit 1; }
source "$ENV_FILE"
interface=$(ip -o link show up | awk -F': ' '{print $2}' | grep -v '^lo$' | head -n1)
ip link set dev "$interface" mtu $MTU
log "Interface $interface MTU=$MTU"
NS=$(cat "$CONFIG_FILE")
for i in {1..5}; do dig +short "$NS" @8.8.8.8 && break || { log "DNS $NS non résolu ($i/5)"; sleep 2; }; done
exec "$SLOWDNS_BIN" -udp ":$PORT" -privkey-file "$SERVER_KEY" "$NS" 127.0.0.1:22 -v
EOF
  chmod +x /usr/local/bin/slowdns-start.sh
}

create_systemd() {
  cat <<EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS Server HTTP Custom
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/slowdns-start.sh
Restart=on-failure
RestartSec=5
StandardOutput=append:/var/log/slowdns.log
StandardError=append:/var/log/slowdns.log
LimitNOFILE=1048576
TimeoutStartSec=60
SyslogIdentifier=slowdns
NoNewPrivileges=yes
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now slowdns.service
}

main() {
  check_root
  cleanup
  install_dependencies
  install_slowdns_bin
  install_fixed_keys
  disable_systemd_resolved
  configure_nftables
  create_env
  create_wrapper
  create_systemd
  log "✅ SlowDNS installé et actif sur port $PORT (Backend SSH, NS auto Cloudflare)"
  echo "NS=$NS"
  echo "Port UDP=$PORT"
}

main
