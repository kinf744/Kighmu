#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
MTU_VALUE=1400

# Ports utilisés
PORT_SSH=5300
PORT_V2RAY=5301
V2RAY_PORT=1080   # Port où tourne V2Ray (modifiable)

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être executé en root ou via sudo." >&2
    exit 1
  fi
}

install_dependencies() {
  log "Mise à jour des paquets et installation des dépendances..."
  apt-get update -q
  for pkg in iptables screen tcpdump wget curl; do
    if ! command -v "$pkg" &> /dev/null; then
      log "$pkg non trouvé, installation..."
      apt-get install -y "$pkg"
    else
      log "$pkg est déjà installé."
    fi
  done
}

get_active_interface() {
  ip -o link show up | awk -F': ' '{print $2}' | grep -v '^lo$' | grep -vE '^(docker|veth|br|virbr|tun|tap|wl|vmnet|vboxnet)' | head -n1
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

kill_ports() {
  for port in $PORT_SSH $PORT_V2RAY; do
    if lsof -iUDP:$port -t >/dev/null 2>&1; then
      log "Port $port occupé. Arrêt des services/processus..."
      # Tenter d'arrêter un service systemd correspondant
      SERVICES=$(systemctl list-units --type=service --all | grep -i slowdns | awk '{print $1}')
      for svc in $SERVICES; do
        log "Stopping service $svc..."
        systemctl stop "$svc" || true
        systemctl disable "$svc" || true
      done
      # Kill tout processus restant sur le port
      PIDS=$(lsof -iUDP:$port -t)
      for pid in $PIDS; do
        log "Killing process $pid sur le port $port"
        kill -9 "$pid"
      done
      log "Port $port libéré."
    fi
  done
}

setup_iptables() {
  local iface=$1
  # Supprimer anciennes règles conflit potentielles
  iptables -t nat -D PREROUTING -i "$iface" -p udp --dport 53 -j REDIRECT --to-ports $PORT_SSH 2>/dev/null || true
  iptables -D INPUT -p udp --dport $PORT_SSH -j ACCEPT 2>/dev/null || true
  iptables -t nat -D PREROUTING -i "$iface" -p udp --dport $PORT_V2RAY -j REDIRECT --to-ports $V2RAY_PORT 2>/dev/null || true
  iptables -D INPUT -p udp --dport $PORT_V2RAY -j ACCEPT 2>/dev/null || true

  # Ajouter règles iptables correctes
  iptables -t nat -I PREROUTING -i "$iface" -p udp --dport 53 -j REDIRECT --to-ports $PORT_SSH
  iptables -I INPUT -p udp --dport $PORT_SSH -j ACCEPT

  iptables -t nat -I PREROUTING -i "$iface" -p udp --dport $PORT_V2RAY -j REDIRECT --to-ports $V2RAY_PORT
  iptables -I INPUT -p udp --dport $PORT_V2RAY -j ACCEPT

  iptables-save > /etc/iptables/rules.v4
  log "Règles iptables mises à jour."
}

enable_ip_forwarding() {
  if [ "$(sysctl -n net.ipv4.ip_forward)" -ne 1 ]; then
    log "Activation du routage IP..."
    sysctl -w net.ipv4.ip_forward=1
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
      echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
  else
    log "Routage IP déjà activé."
  fi
}

create_systemd_services() {
  cat <<EOF > /etc/systemd/system/slowdns-ssh.service
[Unit]
Description=SlowDNS SSH Tunnel
After=network.target

[Service]
Type=simple
ExecStart=$SLOWDNS_BIN -udp :$PORT_SSH -privkey-file $SERVER_KEY \$(cat $CONFIG_FILE) 0.0.0.0:$SSH_PORT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat <<EOF > /etc/systemd/system/slowdns-v2ray.service
[Unit]
Description=SlowDNS V2Ray Tunnel
After=network.target

[Service]
Type=simple
ExecStart=$SLOWDNS_BIN -udp :$PORT_V2RAY -privkey-file $SERVER_KEY \$(cat $CONFIG_FILE) 0.0.0.0:$V2RAY_PORT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  log "Services systemd créés : slowdns-ssh et slowdns-v2ray"
  systemctl daemon-reload
  systemctl enable slowdns-ssh.service
  systemctl enable slowdns-v2ray.service
  systemctl restart slowdns-ssh.service
  systemctl restart slowdns-v2ray.service
}

main() {
  check_root
  install_dependencies
  mkdir -p "$SLOWDNS_DIR"

  kill_ports

  read -rp "Entrez le NameServer (NS) (ex: ns.example.com) : " NAMESERVER
  echo "$NAMESERVER" > "$CONFIG_FILE"

  if [ ! -x "$SLOWDNS_BIN" ]; then
    log "Téléchargement du binaire SlowDNS..."
    wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
    chmod +x "$SLOWDNS_BIN"
  fi

  generate_keys
  PUB_KEY=$(cat "$SERVER_PUB")

  local iface=$(get_active_interface)
  log "Interface réseau détectée : $iface"

  setup_iptables "$iface"
  enable_ip_forwarding

  ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
  if [ -z "$ssh_port" ]; then
    ssh_port=22
  fi

  create_systemd_services

  echo ""
  echo "+--------------------------------------------+"
  echo "|        CONFIG SLOWDNS (SSH + V2RAY)        |"
  echo "+--------------------------------------------+"
  echo ""
  echo "Clé publique :"
  echo "$PUB_KEY"
  echo ""
  echo "NameServer : $NAMESERVER"
  echo ""
  echo "Ports utilisés :"
  echo "  - SlowDNS SSH : UDP $PORT_SSH -> TCP $ssh_port"
  echo "  - SlowDNS V2Ray : UDP $PORT_V2RAY -> TCP $V2RAY_PORT"
  echo ""
  echo "Commandes utiles :"
  echo "  systemctl status slowdns-ssh"
  echo "  systemctl status slowdns-v2ray"
  echo ""
}

main "$@"
