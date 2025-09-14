#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
MTU_VALUE=1350
PORT=5300

NS_BLUE="195.24.192.33"
NS_GOOGLE="8.8.8.8"

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
  log "Installation des dépendances..."
  apt-get update -q
  for pkg in iptables screen tcpdump; do
    if ! command -v "$pkg" &> /dev/null; then
      log "Installation de $pkg..."
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

stop_slowdns() {
  if pgrep -f "sldns-server" >/dev/null; then
    log "Arrêt des instances SlowDNS..."
    pkill -f "sldns-server" || true
    sleep 2
  fi
  iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null || true
  iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports "$PORT" 2>/dev/null || true
}

setup_iptables() {
  local iface=$1
  mkdir -p /etc/iptables
  log "Sauvegarde des règles iptables..."
  iptables-save > /etc/iptables/rules.v4.bak || true

  log "Ajout règle iptables: autoriser UDP port $PORT"
  iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT

  log "Redirection port UDP 53 vers $PORT sur interface $iface"
  iptables -t nat -I PREROUTING -i "$iface" -p udp --dport 53 -j REDIRECT --to-ports "$PORT"

  log "Sauvegarde des règles iptables mises à jour..."
  iptables-save > /etc/iptables/rules.v4
}

enable_ip_forwarding() {
  if [ "$(sysctl -n net.ipv4.ip_forward)" -ne 1 ]; then
    log "Activation du routage IP..."
    sysctl -w net.ipv4.ip_forward=1
    grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  else
    log "Routage IP déjà activé."
  fi
}

create_systemd_service() {
  local service_name="slowdns.service"
  local svc_path="/etc/systemd/system/$service_name"

  log "Création du service systemd $service_name..."

  cat <<EOF > "$svc_path"
[Unit]
Description=SlowDNS Server Tunnel on port $PORT
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=$SLOWDNS_BIN -udp :$PORT -privkey-file $SERVER_KEY \$(cat $CONFIG_FILE) 0.0.0.0:$ssh_port
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal
SyslogIdentifier=slowdns-server

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$service_name"
  systemctl restart "$service_name"
  log "Service $service_name activé et démarré."
}

main() {
  check_root
  install_dependencies
  mkdir -p "$SLOWDNS_DIR"

  if [ ! -x "$SLOWDNS_BIN" ]; then
    mkdir -p /usr/local/bin
    log "Téléchargement du binaire SlowDNS..."
    wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
    chmod +x "$SLOWDNS_BIN"
  fi

  generate_keys

  echo ""
  echo "Sélectionnez le NameServer (NS) :"
  echo "  [1] BLUE Cameroun (195.24.192.33)"
  echo "  [2] Google DNS (8.8.8.8, fallback)"
  read -rp "Choix (1/2, 1 recommandé) : " CHOIX_NS
  case "$CHOIX_NS" in
    1|"") NAMESERVER="$NS_BLUE" ;;
    2) NAMESERVER="$NS_GOOGLE" ;;
    *) NAMESERVER="$NS_BLUE" ;;
  esac
  echo "$NAMESERVER" > "$CONFIG_FILE"
  log "NameServer sélectionné : $NAMESERVER"

  stop_slowdns

  interface=$(get_active_interface)
  if [ -z "$interface" ]; then
    echo "Erreur détection interface réseau. Spécifiez-la manuellement." >&2
    exit 1
  fi
  log "Interface réseau détectée : $interface"

  log "Réglage MTU sur interface $interface à $MTU_VALUE..."
  ip link set dev "$interface" mtu "$MTU_VALUE"

  log "Augmentation buffers UDP..."
  sysctl -w net.core.rmem_max=26214400
  sysctl -w net.core.wmem_max=26214400

  setup_iptables "$interface"
  enable_ip_forwarding

  ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
  [ -z "$ssh_port" ] && ssh_port=22

  log "Démarrage SlowDNS sur UDP port $PORT avec NS $NAMESERVER..."
  screen -dmS slowdns_session "$SLOWDNS_BIN" -udp ":$PORT" -privkey-file "$SERVER_KEY" "$NAMESERVER" 0.0.0.0:"$ssh_port"
  sleep 4

  if pgrep -f "sldns-server" >/dev/null; then
    log "SlowDNS démarré avec succès sur UDP port $PORT."
    log "Pour les logs : screen -r slowdns_session"
  else
    echo "ERREUR : SlowDNS n'a pas pu démarrer." >&2
    exit 1
  fi

  create_systemd_service

  if command -v ufw >/dev/null 2>&1; then
    log "Ouverture du port UDP $PORT avec UFW."
    ufw allow "$PORT"/udp
    ufw reload
  else
    log "UFW non installé. Veuillez vérifier manuellement l'ouverture du port UDP $PORT."
  fi

  echo ""
  echo "+--------------------------------------------+"
  echo "|          CONFIG SLOWDNS - PORT 5300        |"
  echo "+--------------------------------------------+"
  echo ""
  echo "Clé publique serveur :"
  echo "$(cat "$SERVER_PUB")"
  echo ""
  echo "NameServer utilisé : $NAMESERVER"
  echo ""
  echo "Commande client Termux recommandée :"
  echo "curl -sO https://github.com/khaledagn/DNS-AGN/raw/main/files/slowdns && chmod +x slowdns && ./slowdns $NAMESERVER $(cat "$SERVER_PUB")"
  echo ""
  log "Installation et configuration SlowDNS terminées."
}

main "$@"
