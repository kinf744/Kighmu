#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
MTU_VALUE=1350  # Vous pouvez tester aussi 1300 pour plus de stabilité

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

check_root() {
  [[ $EUID -eq 0 ]] || { echo "Ce script doit être exécuté en root ou via sudo." >&2; exit 1; }
}

install_dependencies() {
  log "Mise à jour et installation des paquets requis..."
  apt-get update -q
  deps=(iptables screen tcpdump)
  missing=()
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
      missing+=("$dep")
    else
      log "$dep déjà installé."
    fi
  done
  if [ ${#missing[@]} -gt 0 ]; then
    apt-get install -y "${missing[@]}"
  fi
}

get_active_interface() {
  ip -o link show up | awk -F': ' '{print $2}' | grep -Ev '^lo$|^(docker|veth|br|virbr|tun|tap|wl|vmnet|vboxnet)' | head -n1
}

generate_keys() {
  if [ ! -s "$SERVER_KEY" ] || [ ! -s "$SERVER_PUB" ]; then
    log "Génération des clés SlowDNS..."
    "$SLOWDNS_BIN" -gen-key -privkey-file "$SERVER_KEY" -pubkey-file "$SERVER_PUB"
    chmod 600 "$SERVER_KEY"
    chmod 644 "$SERVER_PUB"
  else
    log "Clés SlowDNS déjà présentes."
  fi
}

stop_old_instance() {
  if pgrep -f "sldns-server" > /dev/null; then
    log "Arrêt de l'ancienne instance SlowDNS..."
    fuser -k "${PORT}/udp" || true
  fi
  iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null || true
  iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports "$PORT" 2>/dev/null || true
}

setup_iptables() {
  local iface=$1
  iptables-save > /etc/iptables/rules.v4.bak || true
  iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
  iptables -t nat -I PREROUTING -i "$iface" -p udp --dport 53 -j REDIRECT --to-ports "$PORT"
  iptables-save > /etc/iptables/rules.v4
  log "iptables mises à jour pour UDP port $PORT."
}

enable_ip_forwarding() {
  if [[ "$(sysctl -n net.ipv4.ip_forward)" -ne 1 ]]; then
    sysctl -w net.ipv4.ip_forward=1
    grep -qxF "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    log "Routage IP activé."
  else
    log "Routage IP déjà activé."
  fi
}

create_systemd_service() {
  local service_file="/etc/systemd/system/slowdns.service"
  local ssh_port=$1

  cat > "$service_file" <<EOF
[Unit]
Description=SlowDNS Server Tunnel
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=$SLOWDNS_BIN -udp :$PORT -privkey-file $SERVER_KEY \$(cat $CONFIG_FILE) 0.0.0.0:$ssh_port
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=slowdns-server

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable slowdns.service
  systemctl restart slowdns.service
  log "Service slowdns activé et démarré via systemd."
}

main() {
  check_root
  install_dependencies
  mkdir -p "$SLOWDNS_DIR"
  stop_old_instance

  read -rp "Entrez le NameServer (NS) (ex: ns.example.com) [par défaut DNS CAMTEL 195.24.192.33] : " NAMESERVER
  NAMESERVER=${NAMESERVER:-195.24.192.33}
  echo "$NAMESERVER" > "$CONFIG_FILE"
  log "NameServer configuré : $NAMESERVER"

  if [[ ! -x "$SLOWDNS_BIN" ]]; then
    mkdir -p /usr/local/bin
    log "Téléchargement du binaire SlowDNS..."
    wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
    chmod +x "$SLOWDNS_BIN"
    [[ -x "$SLOWDNS_BIN" ]] || { echo "Erreur téléchargement slowdns." >&2; exit 1; }
  fi

  generate_keys
  PUB_KEY=$(cat "$SERVER_PUB")

  local interface
  interface=$(get_active_interface)
  [[ -n "$interface" ]] || { echo "Échec détection interface réseau." >&2; exit 1; }
  log "Interface réseau détectée : $interface"

  ip link set dev "$interface" mtu "$MTU_VALUE"
  log "MTU réglé à $MTU_VALUE."

  sysctl -w net.core.rmem_max=26214400
  sysctl -w net.core.wmem_max=26214400
  log "Buffers UDP augmentés."

  setup_iptables "$interface"
  enable_ip_forwarding

  local ssh_port
  ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
  ssh_port=${ssh_port:-22}
  log "Port SSH détecté : $ssh_port"

  create_systemd_service "$ssh_port"

  if command -v ufw &>/dev/null; then
    ufw allow "$PORT"/udp
    ufw reload
    log "Port UDP $PORT ouvert dans UFW."
  else
    log "UFW non installé, vérifier l'ouverture du port UDP $PORT manuellement."
  fi

  echo -e "\n+--------------------------------------------+"
  echo "|               CONFIG SLOWDNS               |"
  echo "+--------------------------------------------+\n"
  echo "Clé publique :"
  echo "$PUB_KEY"
  echo ""
  echo "NameServer : $NAMESERVER"
  echo ""
  echo "Commande client (termux) :"
  echo "curl -sO https://github.com/khaledagn/DNS-AGN/raw/main/files/slowdns && chmod +x slowdns && ./slowdns $NAMESERVER $PUB_KEY"
  log "Installation et configuration SlowDNS terminées."
}

main "$@"
