#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT_BASE=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
MTU_VALUE=1300

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
  for pkg in iptables screen tcpdump ufw; do
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

install_fixed_keys() {
  mkdir -p "$SLOWDNS_DIR"
  echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
  echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
  chmod 600 "$SERVER_KEY"
  chmod 644 "$SERVER_PUB"
}

stop_old_instance() {
  if pgrep -f "sldns-server" >/dev/null; then
    log "Arrêt des anciennes instances SlowDNS..."
    pkill sldns-server || true
    sleep 2
  fi
  # Nettoyer règles iptables existantes pour ports 5300 et 5301
  for port in 5300 5301; do
    iptables -D INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null || true
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports "$port" 2>/dev/null || true
  done
}

setup_iptables() {
  mkdir -p /etc/iptables

  log "Sauvegarde des règles iptables existantes dans /etc/iptables/rules.v4.bak"
  iptables-save > /etc/iptables/rules.v4.bak || true

  for port in "$@"; do
    log "Ajout règle iptables pour autoriser UDP port $port"
    iptables -I INPUT -p udp --dport "$port" -j ACCEPT
  done

  # Redirection du port 53 vers le premier port SlowDNS (pour la première instance)
  # Vous pouvez adapter la redirection si nécessaire
  local interface
  interface=$(get_active_interface)
  log "Redirection DNS UDP port 53 vers $PORT_BASE sur interface $interface"
  iptables -t nat -I PREROUTING -i "$interface" -p udp --dport 53 -j REDIRECT --to-ports "$PORT_BASE"

  log "Sauvegarde des règles mises à jour dans /etc/iptables/rules.v4"
  iptables-save > /etc/iptables/rules.v4
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

create_systemd_service_multi() {
  SERVICE_PATH="/etc/systemd/system/slowdns_multi.service"
  log "Création du fichier systemd slowdns_multi.service..."

  cat <<EOF > "$SERVICE_PATH"
[Unit]
Description=SlowDNS Multiple Instances Server Tunnel
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=/bin/bash -c '
  $SLOWDNS_BIN -udp :$PORT_BASE -privkey-file $SERVER_KEY $1 0.0.0.0:$2 &
  $SLOWDNS_BIN -udp :$((PORT_BASE+1)) -privkey-file $SERVER_KEY $3 0.0.0.0:$2
'
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=slowdns-server-multi

[Install]
WantedBy=multi-user.target
EOF

  log "Recharge systemd et activation du service slowdns_multi..."
  systemctl daemon-reload
  systemctl enable slowdns_multi.service
  systemctl restart slowdns_multi.service
  log "Service slowdns_multi activé et démarré via systemd."
}

main() {
  check_root
  install_dependencies
  mkdir -p "$SLOWDNS_DIR"
  stop_old_instance

  read -rp "Entrez un NameServer 1 (ex: ns1.example.com) : " NS1
  read -rp "Entrez un NameServer 2 (ex: ns2.example.com) : " NS2
  if [[ -z "$NS1" || -z "$NS2" ]]; then
    echo "Les deux NameServers doivent être fournis." >&2
    exit 1
  fi

  # Validation basique
  for ns in "$NS1" "$NS2"; do
    if ! [[ "$ns" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
      echo "Nom de domaine invalide : $ns" >&2
      exit 1
    fi
  done

  # Sauvegarde pour information
  echo -e "$NS1\n$NS2" > "$CONFIG_FILE"
  log "NameServers enregistrés dans $CONFIG_FILE : $NS1, $NS2"

  if [ ! -x "$SLOWDNS_BIN" ]; then
    mkdir -p /usr/local/bin
    log "Téléchargement du binaire SlowDNS..."
    wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
    chmod +x "$SLOWDNS_BIN"
    if [ ! -x "$SLOWDNS_BIN" ]; then
      echo "ERREUR : Échec du téléchargement ou permissions du binaire SlowDNS." >&2
      exit 1
    fi
  fi

  install_fixed_keys
  PUB_KEY=$(cat "$SERVER_PUB")

  local interface
  interface=$(get_active_interface)
  if [ -z "$interface" ]; then
    echo "Échec détection interface réseau. Veuillez spécifier manuellement." >&2
    exit 1
  fi
  log "Interface réseau détectée : $interface"

  log "Réglage MTU sur interface $interface à $MTU_VALUE..."
  ip link set dev "$interface" mtu "$MTU_VALUE"

  log "Augmentation des buffers UDP..."
  sysctl -w net.core.rmem_max=26214400
  sysctl -w net.core.wmem_max=26214400

  setup_iptables "$PORT_BASE" "$((PORT_BASE+1))"
  enable_ip_forwarding

  ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
  if [ -z "$ssh_port" ]; then
    log "Impossible de détecter le port SSH, utilisation du port 22 par défaut."
    ssh_port=22
  fi

  log "Démarrage de deux instances SlowDNS sur UDP ports $PORT_BASE et $((PORT_BASE+1)) avec NS $NS1 et $NS2..."
  screen -dmS slowdns_session_1 "$SLOWDNS_BIN" -udp ":$PORT_BASE" -privkey-file "$SERVER_KEY" "$NS1" 0.0.0.0:"$ssh_port"
  screen -dmS slowdns_session_2 "$SLOWDNS_BIN" -udp ":$((PORT_BASE+1))" -privkey-file "$SERVER_KEY" "$NS2" 0.0.0.0:"$ssh_port"

  sleep 3

  if pgrep -f "sldns-server" >/dev/null; then
    log "Les deux instances SlowDNS sont démarrées avec succès."
    log "Pour voir les logs : screen -r slowdns_session_1 (ou slowdns_session_2)"
  else
    echo "ERREUR : SlowDNS n'a pas pu démarrer." >&2
    exit 1
  fi

  create_systemd_service_multi "$NS1" "$ssh_port" "$NS2"

  if command -v ufw >/dev/null 2>&1; then
    log "Ouverture des ports UDP $PORT_BASE et $((PORT_BASE+1)) avec UFW."
    ufw allow "$PORT_BASE"/udp
    ufw allow "$((PORT_BASE+1))"/udp
    ufw reload
  else
    log "UFW non installé. Veuillez vérifier manuellement l'ouverture des ports UDP."
  fi

  echo ""
  echo "+--------------------------------------------+"
  echo "|               CONFIG SLOWDNS               |"
  echo "+--------------------------------------------+"
  echo ""
  echo "Clé publique :"
  echo "$PUB_KEY"
  echo ""
  echo "NameServers 1 et 2 : $NS1 , $NS2"
  echo ""
  log "Installation et configuration SlowDNS terminées."
}

main "$@"
