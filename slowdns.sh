#!/bin/bash
set -euo pipefail

# SlowDNS Installation Script
# Author: Adapted for GitHub usage and Xray+SlowDNS integration
# Usage: sudo bash install-slowdns.sh

SLOWDNS_DIR="/etc/slowdns"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or use sudo." >&2
    exit 1
  fi
}

install_dependencies() {
  log "Updating packages and installing dependencies..."
  apt-get update -q
  apt-get install -y iptables ufw tcpdump wget curl jq net-tools
}

get_active_interface() {
  ip -o link show up | awk -F': ' '{print $2}' \
    | grep -v '^lo$' \
    | grep -vE '^(docker|veth|br|virbr|tun|tap|wl|vmnet|vboxnet)' \
    | head -n1
}

install_fixed_keys() {
  mkdir -p "$SLOWDNS_DIR"
  echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
  echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
  chmod 600 "$SERVER_KEY" "$SERVER_PUB"
}

stop_old_instance() {
  if pgrep -f "sldns-server" >/dev/null; then
    log "Stopping old SlowDNS instance..."
    fuser -k "${PORT}/udp" || true
    pkill -f "sldns-server" || true
    sleep 2
  fi
  iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null || true
  iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports "$PORT" 2>/dev/null || true
}

setup_iptables() {
  mkdir -p /etc/iptables
  iptables-save > /etc/iptables/rules.v4.bak || true

  log "Adding iptables rule to allow UDP port $PORT"
  iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT

  log "Redirecting DNS UDP port 53 to $PORT on interface $1"
  iptables -t nat -I PREROUTING -i "$1" -p udp --dport 53 -j REDIRECT --to-ports "$PORT"

  iptables-save > /etc/iptables/rules.v4
}

enable_ip_forwarding() {
  sysctl -w net.ipv4.ip_forward=1
  if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  fi
}

optimize_sysctl() {
  log "Applying sysctl optimizations..."
  sed -i '/# SlowDNS optimizations/,+10d' /etc/sysctl.conf || true

  cat <<EOF >> /etc/sysctl.conf

# SlowDNS optimizations
net.core.rmem_max=26214400
net.core.wmem_max=26214400
net.core.rmem_default=26214400
net.core.wmem_default=26214400
net.core.optmem_max=25165824
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_fin_timeout=10
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_mtu_probing=1
EOF

  sysctl -p
}

create_systemd_service() {
  SERVICE_PATH="/etc/systemd/system/slowdns.service"
  ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
  [ -z "$ssh_port" ] && ssh_port=22

  NS=$(cat "$CONFIG_FILE")

  log "Creating systemd service file for slowdns..."
  cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=SlowDNS Server Tunnel
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=$SLOWDNS_BIN -udp :$PORT -privkey-file $SERVER_KEY $NS 0.0.0.0:$ssh_port
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=slowdns-server
LimitNOFILE=1048576
Nice=-5
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=99

[Install]
WantedBy=multi-user.target
EOF

  log "Reloading systemd and enabling slowdns service..."
  systemctl daemon-reload
  systemctl enable slowdns.service
  systemctl restart slowdns.service
  log "SlowDNS service enabled and started."
}

main() {
  check_root
  install_dependencies
  mkdir -p "$SLOWDNS_DIR"
  stop_old_instance

  read -rp "Enter your NameServer (NS) (e.g. ns.example.com): " NAMESERVER
  if [[ -z "$NAMESERVER" ]]; then
    echo "Invalid NameServer input." >&2
    exit 1
  fi
  echo "$NAMESERVER" > "$CONFIG_FILE"
  log "Nameserver saved to $CONFIG_FILE"

  if [ ! -x "$SLOWDNS_BIN" ]; then
    mkdir -p /usr/local/bin
    log "Downloading SlowDNS binary..."
    wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
    chmod +x "$SLOWDNS_BIN"
    if [ ! -x "$SLOWDNS_BIN" ]; then
      echo "ERROR: Failed to download SlowDNS binary." >&2
      exit 1
    fi
  fi

  install_fixed_keys
  PUB_KEY=$(cat "$SERVER_PUB")

  interface=$(get_active_interface)
  if [ -z "$interface" ]; then
    echo "Failed to detect active network interface. Please specify manually." >&2
    exit 1
  fi
  log "Detected network interface: $interface"

  MTU_VALUE=132
  log "Setting MTU on $interface to $MTU_VALUE..."
  ip link set dev "$interface" mtu "$MTU_VALUE"

  optimize_sysctl
  setup_iptables "$interface"
  enable_ip_forwarding
  create_systemd_service

  if command -v ufw >/dev/null 2>&1; then
    log "Allowing UDP port $PORT through UFW."
    ufw allow "$PORT"/udp
    ufw reload
  fi

  echo ""
  echo "+--------------------------------------------+"
  echo "|          SLOWDNS CONFIGURATION             |"
  echo "+--------------------------------------------+"
  echo ""
  echo "Public key:"
  echo "$PUB_KEY"
  echo ""
  echo "NameServer : $NAMESERVER"
  echo ""
  log "SlowDNS installation and configuration completed successfully."
}

main "$@"
