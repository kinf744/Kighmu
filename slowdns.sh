#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
MTU_VALUE=1400

# Clé privée base64 one-liner (remplacez par votre clé privée correcte)
FIXED_PRIVATE_KEY="MIIBVwIBADANBgkqhkiG9w0BAQEFAASCAT8wggE7AgEAAkEAxZQx6VkBbZg0Rlzi..."

# Clé publique base64 one-liner
FIXED_PUBLIC_KEY="7fbd1f8aa0abfe15a7903e837f78aba39cf61d36f183bd604daa2fe4ef3b7b59"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

check_root() {
  [ "$EUID" -ne 0 ] && { echo "Ce script doit être exécuté en root." >&2; exit 1; }
}

install_deps() {
  log "Installation dépendances..."
  apt-get update -q
  for pkg in iptables screen tcpdump; do
    if ! command -v "$pkg" &> /dev/null; then
      log "Installation de $pkg..."
      apt-get install -y "$pkg"
    else
      log "$pkg déjà installé."
    fi
  done
}

get_if() {
  ip -o link show up | awk -F': ' '{print $2}' | grep -v '^lo$' | grep -vE '^(docker|veth|br|virbr|tun|tap|wl|vmnet|vboxnet)' | head -1
}

generate_keys() {
  if [ ! -s "$SERVER_KEY" ] || [ ! -s "$SERVER_PUB" ]; then
    log "Installation des clés fixes..."
    echo "$FIXED_PRIVATE_KEY" > "$SERVER_KEY"
    echo "$FIXED_PUBLIC_KEY" > "$SERVER_PUB"
    chmod 600 "$SERVER_KEY"
    chmod 644 "$SERVER_PUB"
  else
    log "Clés déjà présentes."
  fi
}

cleanup() {
  if pgrep -f sldns-server > /dev/null; then
    log "Arrêt SlowDNS existant..."
    fuser -k "${PORT}/udp" || true
    sleep 2
  fi
  iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null || true
  iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports "$PORT" 2>/dev/null || true
}

setup_iptables() {
  mkdir -p /etc/iptables
  log "Sauvegarde règles iptables..."
  iptables-save > /etc/iptables/rules.v4.bak || true
  log "Ouverture port UDP $PORT..."
  iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
  log "Redirection port DNS 53 vers $PORT..."
  iptables -t nat -I PREROUTING -i "$1" -p udp --dport 53 -j REDIRECT --to-ports "$PORT"
  iptables-save > /etc/iptables/rules.v4
}

enable_ip_forward() {
  if [ "$(sysctl -n net.ipv4.ip_forward)" -ne 1 ]; then
    log "Activation routage IP..."
    sysctl -w net.ipv4.ip_forward=1
    grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
  else
    log "Routage IP déjà activé."
  fi
}

create_service() {
  local service="/etc/systemd/system/slowdns.service"
  local ns=$(cat "$CONFIG_FILE")
  cat <<EOF > "$service"
[Unit]
Description=SlowDNS Server Tunnel
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=$SLOWDNS_BIN -udp :$PORT -privkey-file $SERVER_KEY $ns 0.0.0.0:22
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=slowdns-server

[Install]
WantedBy=multi-user.target
EOF
  log "Activation service systemd..."
  systemctl daemon-reload
  systemctl enable slowdns.service
  systemctl restart slowdns.service
}

main() {
  check_root
  install_deps
  mkdir -p "$SLOWDNS_DIR"

  cleanup

  read -rp "Entrez le NameServer (ex: ns.example.com) : " NS
  if [ -z "$NS" ]; then
    echo "NameServer invalide." >&2
    exit 1
  fi
  echo "$NS" > "$CONFIG_FILE"
  log "NameServer enregistré."

  if [ ! -x "$SLOWDNS_BIN" ]; then
    log "Téléchargement du binaire SlowDNS..."
    wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
    chmod +x "$SLOWDNS_BIN"
  fi

  generate_keys

  local iface=$(get_if)
  if [ -z "$iface" ]; then
    echo "Interface réseau non détectée." >&2
    exit 1
  fi
  log "Interface détectée : $iface"

  log "Réglage MTU à $MTU_VALUE..."
  ip link set dev "$iface" mtu "$MTU_VALUE"

  log "Augmentation buffers UDP..."
  sysctl -w net.core.rmem_max=26214400
  sysctl -w net.core.wmem_max=26214400

  setup_iptables "$iface"
  enable_ip_forward

  log "Démarrage SlowDNS sur UDP $PORT avec NS $NS..."
  screen -dmS slowdns_session "$SLOWDNS_BIN" -udp ":$PORT" -privkey-file "$SERVER_KEY" "$NS" 0.0.0.0:22
  sleep 3
  if pgrep -f sldns-server > /dev/null; then
    log "SlowDNS démarre avec succès."
  else
    echo "ERREUR : SlowDNS n'a pas démarré." >&2
    exit 1
  fi

  create_service

  if command -v ufw > /dev/null 2>&1; then
    ufw allow "$PORT"/udp
    ufw reload
    log "Port UDP $PORT ouvert avec UFW."
  fi

  echo ""
  echo "+---------------- Configuration SlowDNS ----------------+"
  echo "NameServer : $NS"
  echo "Clé publique :"
  cat "$SERVER_PUB"
  echo ""
  echo "Commande client (Termux) :"
  echo "curl -sO https://github.com/khaledagn/DNS-AGN/raw/main/files/slowdns && chmod +x slowdns && ./slowdns $NS $(cat "$SERVER_PUB")"
  echo "+-------------------------------------------------------+"
}

main "$@"
