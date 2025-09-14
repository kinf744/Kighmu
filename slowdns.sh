#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
MTU_VALUE=1400

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
  log "Mise à jour des paquets et installation des dépendances manquantes..."
  apt-get update -q

  missing=()
  for pkg in iptables screen tcpdump; do
    if ! command -v "$pkg" &> /dev/null; then
      missing+=("$pkg")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    log "Installation des paquets: ${missing[*]}"
    apt-get install -y "${missing[@]}"
  else
    log "Toutes les dépendances sont déjà installées."
  fi
}

get_active_interface() {
  ip -o link show up | awk -F': ' '{print $2}' | grep -vE '^(lo|docker|veth|br|virbr|tun|tap|wl|vmnet|vboxnet)$' | head -n1
}

generate_keys() {
  if [ ! -s "$SERVER_KEY" ] || [ ! -s "$SERVER_PUB" ]; then
    log "Génération des clés SlowDNS..."
    "$SLOWDNS_BIN" -gen-key -privkey-file "$SERVER_KEY" -pubkey-file "$SERVER_PUB"
    chmod 600 "$SERVER_KEY" "$SERVER_PUB"
  else
    log "Clés SlowDNS déjà présentes."
  fi
}

stop_old_instance() {
  if pgrep -f "sldns-server" >/dev/null; then
    log "Arrêt de l'ancienne instance SlowDNS..."
    fuser -k "${PORT}/udp" || true
    sleep 2
  fi
  # Nettoyer règles iptables existantes pour le port 5300
  iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null || true
  iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports "$PORT" 2>/dev/null || true
}

setup_iptables() {
  log "Ajout des règles iptables pour UDP port $PORT et redirection du port 53"
  iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
  iptables -t nat -I PREROUTING -i "$1" -p udp --dport 53 -j REDIRECT --to-ports "$PORT"
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
  local service_path="/etc/systemd/system/slowdns.service"
  log "Création du service systemd slowdns.service..."

  cat <<EOF > "$service_path"
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
  log "Service slowdns activé et démarré."
}

main() {
  check_root
  install_dependencies

  mkdir -p "$SLOWDNS_DIR"
  stop_old_instance

  read -rp "Entrez le NameServer (NS) (ex: ns.example.com) : " NAMESERVER
  if [[ -z "$NAMESERVER" ]]; then
    echo "NameServer invalide." >&2
    exit 1
  fi

  echo "$NAMESERVER" > "$CONFIG_FILE"
  log "NameServer enregistré dans $CONFIG_FILE"

  if [ ! -x "$SLOWDNS_BIN" ]; then
    mkdir -p /usr/local/bin
    log "Téléchargement du binaire SlowDNS..."
    wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
    chmod +x "$SLOWDNS_BIN"
  fi

  generate_keys
  PUB_KEY=$(cat "$SERVER_PUB")

  interface=$(get_active_interface)
  if [[ -z "$interface" ]]; then
    echo "Échec de détection de l'interface réseau." >&2
    exit 1
  fi
  log "Interface réseau détectée : $interface"

  # Réglages MTU et buffers UDP en tâche de fond pour accélérer l'installation
  ip link set dev "$interface" mtu "$MTU_VALUE" &
  sysctl -w net.core.rmem_max=26214400 &
  sysctl -w net.core.wmem_max=26214400 &
  wait

  setup_iptables "$interface"
  enable_ip_forwarding

  ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
  ssh_port=${ssh_port:-22}
  log "Détecté port SSH : $ssh_port"

  log "Démarrage SlowDNS sur UDP port $PORT avec NS $NAMESERVER..."
  screen -dmS slowdns_session "$SLOWDNS_BIN" -udp ":$PORT" -privkey-file "$SERVER_KEY" "$NAMESERVER" 0.0.0.0:"$ssh_port"
  
  sleep 3

  if pgrep -f "sldns-server" >/dev/null; then
    log "SlowDNS démarré avec succès sur UDP port $PORT."
    log "Pour suivre les logs : screen -r slowdns_session"
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
  echo "|               CONFIG SLOWDNS               |"
  echo "+--------------------------------------------+"
  echo ""
  echo "Clé publique :"
  echo "$PUB_KEY"
  echo ""
  echo "NameServer  : $NAMESERVER"
  echo ""
  echo "Commande client (termux) :"
  echo "curl -sO https://github.com/khaledagn/DNS-AGN/raw/main/files/slowdns && chmod +x slowdns && ./slowdns $NAMESERVER $PUB_KEY"
  echo ""
  log "Installation et configuration SlowDNS terminées."
}

main "$@"
