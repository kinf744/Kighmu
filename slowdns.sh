#!/bin/bash
set -euo pipefail

############################
# CONFIGURATION PRINCIPALE
############################
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300

CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
ENV_FILE="$SLOWDNS_DIR/slowdns.env"
BACKEND_CONF="$SLOWDNS_DIR/backend.conf"

CF_API_TOKEN="TON_TOKEN_CLOUDFLARE"
CF_ZONE_ID="TON_ZONE_ID"
DOMAIN="kingom.ggff.net"

log(){ echo "[$(date '+%F %T')] $*"; }

[ "$EUID" -eq 0 ] || { echo "Exécuter en root"; exit 1; }

mkdir -p "$SLOWDNS_DIR"

############################
# DNS LOCAL SAFE
############################
systemctl disable --now systemd-resolved || true
rm -f /etc/resolv.conf
cat > /etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
options timeout:1 attempts:1
EOF
chmod 644 /etc/resolv.conf

############################
# DEPENDANCES
############################
apt update -y
apt install -y curl jq nftables iproute2 tcpdump

systemctl enable nftables
systemctl start nftables

############################
# DNSTT
############################
if [ ! -x "$SLOWDNS_BIN" ]; then
  curl -fsSL -o "$SLOWDNS_BIN" \
  https://www.bamsoftware.com/software/dnstt/dnstt-server-linux-amd64
  chmod +x "$SLOWDNS_BIN"
fi

############################
# CHOIX BACKEND
############################
choose_backend(){
  echo "1) SSH"
  echo "2) V2Ray"
  echo "3) MIX"
  read -rp "Choix backend [1-3] : " c
  case "$c" in
    1) m=ssh ;;
    2) m=v2ray ;;
    3) m=mix ;;
    *) echo "Choix invalide"; exit 1 ;;
  esac
  echo "BACKEND_MODE=$m" > "$BACKEND_CONF"
}

############################
# NS AUTO (CLOUDFLARE)
############################
generate_ns_auto(){
  local ip sub fqdn ns

  ip=$(curl -s ipv4.icanhazip.com)
  sub="vpn-$(date +%s | sha256sum | head -c6)"
  fqdn="$sub.$DOMAIN"

  curl -s -X POST \
   "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
   -H "Authorization: Bearer $CF_API_TOKEN" \
   -H "Content-Type: application/json" \
   --data "{\"type\":\"A\",\"name\":\"$fqdn\",\"content\":\"$ip\",\"ttl\":120,\"proxied\":false}" >/dev/null

  ns="ns-$(date +%s | sha256sum | head -c6).$DOMAIN"

  curl -s -X POST \
   "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
   -H "Authorization: Bearer $CF_API_TOKEN" \
   -H "Content-Type: application/json" \
   --data "{\"type\":\"NS\",\"name\":\"$ns\",\"content\":\"$fqdn\",\"ttl\":120}" >/dev/null

  echo -e "NS=$ns\nENV_MODE=auto" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "$ns"
}

############################
# CHOIX MODE AUTO / MAN
############################
echo "Mode d'installation :"
echo "1) AUTO (Cloudflare – NS persistant)"
echo "2) MANUEL (NS toujours demandé)"
read -rp "Choix [1-2] : " MODE

case "$MODE" in
  1)
    if [ -f "$ENV_FILE" ]; then
      source "$ENV_FILE"
      if [ "${ENV_MODE:-}" = "auto" ] && [ -n "${NS:-}" ]; then
        log "NS auto persistant détecté : $NS"
      else
        log "NS auto invalide → génération"
        NS=$(generate_ns_auto)
      fi
    else
      log "Aucun NS auto → génération"
      NS=$(generate_ns_auto)
    fi
    echo "$NS" > "$CONFIG_FILE"
    ;;
  2)
    read -rp "Entrez le NameServer (NS) à utiliser : " NS
    echo "$NS" > "$CONFIG_FILE"
    log "NS manuel appliqué (non persistant)"
    ;;
  *)
    echo "Choix invalide"
    exit 1
    ;;
esac

choose_backend

############################
# CLES FIXES
############################
cat > "$SERVER_KEY" <<EOF
4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa
EOF

cat > "$SERVER_PUB" <<EOF
2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c
EOF

chmod 600 "$SERVER_KEY"
chmod 644 "$SERVER_PUB"

############################
# SYSCTL PROD
############################
cat > /etc/sysctl.d/99-slowdns.conf <<EOF
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.core.rmem_default=1048576
net.core.wmem_default=1048576
net.core.netdev_max_backlog=100000
net.core.somaxconn=65535
net.ipv4.udp_rmem_min=65536
net.ipv4.udp_wmem_min=65536
net.ipv4.udp_mem=262144 524288 1048576
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.ip_forward=1
EOF
sysctl --system >/dev/null

############################
# WRAPPER DNSTT
############################
cat > /usr/local/bin/slowdns-start.sh <<'EOF'
#!/bin/bash
set -euo pipefail

CONF="/etc/slowdns"
BIN="/usr/local/bin/dnstt-server"

source "$CONF/backend.conf"

case "$BACKEND_MODE" in
  ssh) tgt="0.0.0.0:22" ;;
  v2ray|mix) tgt="127.0.0.1:8443" ;;
  *) tgt="0.0.0.0:22" ;;
esac

exec nice -n -5 ionice -c2 -n0 \
"$BIN" -udp :5300 -mtu 1232 \
-privkey-file "$CONF/server.key" \
"$(cat $CONF/ns.conf)" "$tgt"
EOF

chmod +x /usr/local/bin/slowdns-start.sh

############################
# SYSTEMD
############################
cat > /etc/systemd/system/slowdns.service <<EOF
[Unit]
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/slowdns-start.sh
Restart=always
RestartSec=2
LimitNOFILE=1048576
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

############################
# NFTABLES SAFE
############################
cat > /etc/nftables.d/slowdns.nft <<EOF
table inet slowdns {
 chain prerouting {
  type nat hook prerouting priority -100;
  ip daddr != 127.0.0.1 udp dport 53 redirect to :5300
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
systemctl enable nftables slowdns
systemctl restart nftables slowdns

log "INSTALLATION SLOWDNS PROD TERMINÉE"
log "NS UTILISÉ : $(cat $CONFIG_FILE)"
log "BACKEND : $(cat $BACKEND_CONF)"
