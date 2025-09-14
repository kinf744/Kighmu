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
  log "Mise à jour des paquets et installation des dépendances..."
  apt-get update -q
  for pkg in iptables screen tcpdump; do
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

# Clé publique unique partagée (remplacez cette clé par la vôtre si nécessaire)
UNIQUE_PUBLIC_KEY="7fbd1f8aa0abfe15a7903e837f78aba39cf61d36f183bd604daa2fe4ef3b7b59"

generate_keys() {
  log "Utilisation de la clé publique unique partagée pour SlowDNS..."
  mkdir -p "$SLOWDNS_DIR"
  echo "$UNIQUE_PUBLIC_KEY" > "$SERVER_PUB"
  chmod 644 "$SERVER_PUB"
  # Clé privée non utilisée mais fichier créé vide par sécurité
  echo "Private key not shared for security reasons" > "$SERVER_KEY"
  chmod 600 "$SERVER_KEY"
}

stop_old_instance() {
  if pgrep -f "sldns-server" >/dev/null; then
    log "Arrêt de l'ancienne instance SlowDNS..."
    fuser -k "${PORT}/udp" || true
    sleep 2
  fi
  # Nettoyer règles iptables existantes pour port 5300
  iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null || true
  iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports "$PORT" 2>/dev/null || true
}

setup_iptables() {
  mkdir -p /etc/iptables

  log "Sauvegarde des règles iptables existantes dans /etc/iptables/rules.v4.bak"
  iptables-save > /etc/iptables/rules.v4.bak || true

  log "Ajout règle iptables pour autoriser UDP port $PORT"
  iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT

  log "Redirection DNS UDP port 53 vers $PORT sur interface $1"
  iptables -t nat -I PREROUTING -i "$1" -p udp --dport 53 -j REDIRECT --to-ports "$PORT"

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

create_systemd_service() {
  SERVICE_PATH="/etc/systemd/system/slowdns.service"

  log "Création du fichier systemd slowdns.service..."

  cat <<EOF > "$SERVICE_PATH"
[Unit]
Description=SlowDNS Server Tunnel
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=$SLOWDNS_BIN -udp :$PORT -pubkey-file $SERVER_PUB \$(cat $CONFIG_FILE) 0.0.0.0:\$(ss -tlnp | grep sshd | head -1 | awk '{print \$4}' | cut -d: -f2)
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=slowdns-server

[Install]
WantedBy=multi-user.target
EOF

  log "Recharge systemd et activation du service slowdns..."
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
    if [ ! -x "$SLOWDNS_BIN" ]; then
      echo "ERREUR : Échec du téléchargement ou permissions du binaire SlowDNS." >&2
      exit 1
    fi
  fi

  generate_keys
  PUB_KEY=$(cat "$SERVER_PUB")

  local interface=$(get_active_interface)
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

  setup_iptables "$interface"
  enable_ip_forwarding

  log "Démarrage SlowDNS sur UDP port $PORT avec NS $NAMESERVER..."
  screen -dmS slowdns_session "$SLOWDNS_BIN" -udp ":$PORT" -pubkey-file "$SERVER_PUB" "$NAMESERVER" 0.0.0.0:$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)

  sleep 3

  if pgrep -f "sldns-server" >/dev/null; then
    log "SlowDNS démarré avec succès sur UDP port $PORT."
    log "Pour les logs : screen -r slowdns_session"
  else
    echo "ERREUR : SlowDNS n'a pas pu démarrer." >&2
    exit 1
  fi

  # Création et activation du service systemd à partir du script
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
