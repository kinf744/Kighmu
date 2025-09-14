#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
MTU_VALUE=1400

# Remplacez cette clé privée par la vôtre issue du script original
FIXED_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----
MIIBVwIBADANBgkqhkiG9w0BAQEFAASCAT8wggE7AgEAAkEAxZQx6VkBbZg0Rlzi
... (contenu tronqué, insérer la vraie clé privée) ...
-----END PRIVATE KEY-----"

# Clé publique correspondante (existe aussi dans le script original)
FIXED_PUBLIC_KEY="7fbd1f8aa0abfe15a7903e837f78aba39cf61d36f183bd604daa2fe4ef3b7b59"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en root ou via sudo." >&2
    exit 1
  fi
}

install_dependencies() {
  log "Mise à jour des paquets et installation des dépendances..."
  apt-get update -q
  for pkg in wget curl iptables screen tcpdump; do
    if ! command -v "$pkg" &>/dev/null; then
      log "$pkg non trouvé, installation..."
      apt-get install -y "$pkg"
    else
      log "$pkg est déjà installé."
    fi
  done
}

deploy_keys() {
  log "Déploiement clés SlowDNS fixe..."
  mkdir -p "$SLOWDNS_DIR"
  echo "$FIXED_PRIVATE_KEY" > "$SERVER_KEY"
  chmod 600 "$SERVER_KEY"
  echo "$FIXED_PUBLIC_KEY" > "$SERVER_PUB"
  chmod 644 "$SERVER_PUB"
}

download_sldns() {
  if [ ! -x "$SLOWDNS_BIN" ]; then
    log "Téléchargement binaire SlowDNS..."
    wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
    chmod +x "$SLOWDNS_BIN"
  else
    log "Binaire SlowDNS déjà présent."
  fi
}

create_systemd_service() {
  local service_path="/etc/systemd/system/slowdns.service"
  log "Création fichier systemd slowdns.service..."

  cat > "$service_path" << EOF
[Unit]
Description=SlowDNS Server Tunnel
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=$SLOWDNS_BIN -udp :$PORT -privkey-file $SERVER_KEY \$(cat $CONFIG_FILE) 0.0.0.0:\$(ss -tlnp | grep sshd | head -1 | awk '{print \$4}' | cut -d: -f2)
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
  log "Service slowdns activé et démarré."
}

setup_iptables() {
  local interface="$1"

  iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
  iptables -t nat -I PREROUTING -i "$interface" -p udp --dport 53 -j REDIRECT --to-port "$PORT"

  iptables-save > /etc/iptables/rules.v4 || true
}

enable_ip_forwarding() {
  if [ "$(sysctl -n net.ipv4.ip_forward)" -ne 1 ]; then
    sysctl -w net.ipv4.ip_forward=1
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
      echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
  fi
}

main() {
  check_root
  install_dependencies
  download_sldns
  deploy_keys

  read -rp "Entrez NameServer (ex: ns.example.com) : " NAMESERVER
  if [[ -z "$NAMESERVER" ]]; then
    echo "NameServer invalide." >&2
    exit 1
  fi
  echo "$NAMESERVER" > "$CONFIG_FILE"

  local interface
  interface=$(ip -o link show up | awk -F': ' '{print $2}' | grep -v '^lo$' | head -n1)
  if [ -z "$interface" ]; then
    echo "Erreur détection interface réseau." >&2
    exit 1
  fi

  log "Configuration interface $interface MTU=$MTU_VALUE"
  ip link set dev "$interface" mtu "$MTU_VALUE"

  setup_iptables "$interface"
  enable_ip_forwarding

  create_systemd_service

  if command -v ufw >/dev/null 2>&1; then
    ufw allow "$PORT"/udp
    ufw reload
    log "UFW : port $PORT UDP ouvert."
  fi

  # Affichage du message de confirmation à la fin
  PUB_KEY="$FIXED_PUBLIC_KEY"
  echo ""
  echo "+--------------------------------------------+"
  echo "|               CONFIG SLOWDNS               |"
  echo "+--------------------------------------------+"
  echo ""
  echo "Clé publique :"
  echo "$PUB_KEY"
  echo ""
  echo "NameServer  : $NAMESERVER"
  echo ""

  log "Installation terminée. SlowDNS écoute sur UDP port $PORT."
}

main "$@"
