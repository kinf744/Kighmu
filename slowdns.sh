#!/bin/bash
# slowdns-setup.sh
# Script d'installation complet SlowDNS + wrapper robuste + service systemd
# Pré-requis: Ubuntu/Debian, accès root

set -euo pipefail

# Variables globales
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=5300
NS_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
SLOWDNS_ENV="$SLOWDNS_DIR/slowdns.env"
LOCAL_CONFIG="$SLOWDNS_DIR/config.ini"
SLOWDNS_WRAP="/usr/local/bin/slowdns-start.sh"
SLOWDNS_SERVICE="/etc/systemd/system/slowdns.service"
LOG_DIR="/var/log/slowdns"
LOG_RUN="$LOG_DIR/slowdns-run.log"
LOG_SERVICE="$LOG_DIR/slowdns.log"
SSH_PORT="${SSH_PORT:-22}"
NS="${NS:-}"
CLEANUP_RULES="no"  # mettre yes pour réinitialiser les règles NAT au démarrage

# Fonctions utilitaires
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

die() { log "ERREUR: $*"; exit 1; }

check_root() {
  if [ "$EUID" -ne 0 ]; then
    die "Ce script doit être exécuté en root."
  fi
}

install_dependencies() {
  log "Installation des dépendances..."
  apt-get update -qq
  apt-get install -y -qq iptables iptables-persistent wget tcpdump curl socat
}

download_slowdns_bin() {
  if [ ! -x "$SLOWDNS_BIN" ]; then
    log "Téléchargement du binaire SlowDNS..."
    mkdir -p "$(dirname "$SLOWDNS_BIN")"
    wget -q -O "$SLOWDNS_BIN" "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server" \
      || wget -q -O "$SLOWDNS_BIN" "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server.bak"
    chmod +x "$SLOWDNS_BIN"
  fi
  [ -x "$SLOWDNS_BIN" ] || die "Échec du téléchargement/exécution du binaire SlowDNS."
}

install_fixed_keys() {
  mkdir -p "$SLOWDNS_DIR"
  echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
  echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
  chmod 600 "$SERVER_KEY"
  chmod 644 "$SERVER_PUB"
}

disable_systemd_resolved() {
  log "Désactivation de systemd-resolved si actif..."
  if systemctl is-active --quiet systemd-resolved; then
    systemctl stop systemd-resolved
  fi
  if systemctl is-enabled --quiet systemd-resolved; then
    systemctl disable systemd-resolved
  fi
  rm -f /etc/resolv.conf
  echo "nameserver 8.8.8.8" > /etc/resolv.conf
}

configure_sysctl() {
  log "Optimisations sysctl..."
  SYSCTL_FILE="/etc/sysctl.conf"
  sed -i '/# Optimisations SlowDNS/,+10d' "$SYSCTL_FILE" 2>/dev/null || true
  cat <<EOF >> "$SYSCTL_FILE"

# Optimisations SlowDNS
net.core.rmem_max=8388608
net.core.wmem_max=8388608
net.core.rmem_default=262144
net.core.wmem_default=262144
net.core.optmem_max=25165824
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_fin_timeout=10
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_mtu_probing=1
net.ipv4.ip_forward=1
EOF
  sysctl -p
}

setup_iptables() {
  log "Configuration du pare-feu via iptables..."
  # Rule UDP 53 redirection et port SlowDNS
  if ! iptables -C INPUT -p udp --dport 53 -j ACCEPT &>/dev/null; then
    iptables -I INPUT -p udp --dport 53 -j ACCEPT
  fi
  if ! iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT &>/dev/null; then
    iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
  fi
  iptables-save > /etc/iptables/rules.v4
  systemctl enable netfilter-persistent
  systemctl restart netfilter-persistent
  log "Règles iptables persistantisées."
}

# Wrapper SlowDNS: démarrage robuste et logging
write_wrapper() {
  cat > "$SLOWDNS_WRAP" <<'EOF'
#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SSH_PORT="${SSH_PORT:-22}"
LOG_RUN="/var/log/slowdns-run.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_RUN"; }

wait_for_interface() {
  local iface
  iface=""
  while [ -z "$iface" ]; do
    iface=$(ip -o link show up 2>/dev/null | awk -F': ' '{print $2}' | \
            grep -vE '^(lo|docker|veth|br|virbr|tun|tap|wl|vmnet|vboxnet)$' | head -n1)
    [ -z "$iface" ] && sleep 2
  done
  echo "$iface"
}

setup_iptables() {
  local interface="$1"
  if ! iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT &>/dev/null; then
    iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
  fi
  if ! iptables -t nat -C PREROUTING -i "$interface" -p udp --dport 53 -j REDIRECT --to-ports "$PORT" &>/dev/null; then
    iptables -t nat -I PREROUTING -i "$interface" -p udp --dport 53 -j REDIRECT --to-ports "$PORT"
  fi
  iptables-save > /etc/iptables/rules.v4
  log "Règles NAT et port SlowDNS appliquées."
}

start_slowdns() {
  "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SLOWDNS_DIR/server.key" "$CONFIG_FILE" 0.0.0.0:$SSH_PORT
}

main() {
  log "Debut slowdns-start.sh"
  interface=$(wait_for_interface)
  log "Interface détectée: $interface"
  setup_iptables "$interface"

  local max_attempts=3
  local delays=(2 4 8)
  for i in "${!delays[@]}"; do
    attempt=$((i+1))
    log "Tentative de démarrage SlowDNS (n°$attempt)…"
    if start_slowdns; then
      log "SlowDNS démarré avec succès."
      exit 0
    else
      log "Échec du démarrage. Attente ${delays[$i]}s avant nouvelle tentative."
      sleep "${delays[$i]}"
    fi
  done

  log "ÉCHEC CRITIQUE: SlowDNS ne démarre pas après $max_attempts tentatives."
  exit 1
}

main "$@"
EOF
  chmod +x "$SLOWDNS_WRAP"
}

create_systemd_service() {
  cat > "$SLOWDNS_SERVICE" <<'EOF'
[Unit]
Description=SlowDNS Server Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/slowdns-start.sh
Restart=on-failure
RestartSec=5
StandardOutput=append:/var/log/slowdns.log
StandardError=append:/var/log/slowdns.log
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable slowdns
  systemctl restart slowdns
  log "Service slowdns déployé et démarré."
}

generate_ns_conf() {
  mkdir -p "$SLOWDNS_DIR"
  if [ -z "${NS:-}" ]; then
    read -rp "Entrez le NameServer (ex: ns.example.com) : " NS
  else
    NS="$NS"
  fi
  echo "$NS" > "$NS_FILE"
  log " ns.conf généré avec NS=$NS"
}

write_env_and_keys() {
  cat > "$SLOWDNS_ENV" <<EOF
NS=$(cat "$NS_FILE")
PUB_KEY=$(cat "$SERVER_PUB")
PRIV_KEY=$(cat "$SERVER_KEY")
EOF
  chmod 600 "$SLOWDNS_ENV"
}

final_echo() {
  PUB_KEY=$(cat "$SERVER_PUB")
  echo ""
  echo "+--------------------------------------------+"
  echo "|          CONFIGURATION SLOWDNS             |"
  echo "+--------------------------------------------+"
  echo ""
  echo "Clé publique : $PUB_KEY"
  echo "NameServer  : $(cat "$NS_FILE")"
  echo ""
  log "Configuration SlowDNS terminée."
}

# Déploiement principal
main() {
  check_root
  install_dependencies
  download_slowdns_bin
  install_fixed_keys
  disable_systemd_resolved
  mkdir -p "$LOG_DIR"
  chmod 700 "$LOG_DIR"

  # NS entrée utilisateur
  if [ -z "${NS:-}" ]; then
    generate_ns_conf
  else
    echo "$NS" > "$NS_FILE"
  fi

  configure_sysctl
  setup_iptables
  write_wrapper
  create_systemd_service

  write_env_and_keys

  final_echo

  log "Installation et configuration SlowDNS terminées. Démarrage du service..."
  systemctl daemon-reload
  systemctl enable slowdns
  systemctl start slowdns
  echo "Le service slowdns est démarré et actif."
}

# Exécution
main "$@"
