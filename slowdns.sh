#!/bin/bash
set -euo pipefail

# SlowDNS - Speed Edition installer
# Usage: sudo ./slowdns-speed-install.sh
# Notes: Testé pour Debian/Ubuntu (22.04, 24.04). Root required.

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dns-server"
PORT=53                # port UDP préféré
FALLBACK_PORT=5300     # si 53 impossible
SYSCTL_FILE="/etc/sysctl.d/99-slowdns.conf"
SERVICE_FILE="/etc/systemd/system/slowdns.service"
ENV_FILE="$SLOWDNS_DIR/slowdns.env"
BIN_URL_DEFAULT="https://raw.githubusercontent.com/khaledagn/DNS-AGN/main/dns-server"
# Si tu as un binaire 'speed patched', set BIN_URL env before running:
BIN_URL="${BIN_URL:-$BIN_URL_DEFAULT}"

log() { echo "[$(date '+%F %T')] $*"; }

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en root." >&2
    exit 1
  fi
}

install_pkgs() {
  log "Mise à jour et installation des paquets requis..."
  apt-get update -q
  apt-get install -y --no-install-recommends wget iptables iproute2 net-tools netfilter-persistent ca-certificates
}

download_bin() {
  if [ -x "$SLOWDNS_BIN" ]; then
    log "Binaire existant trouvé : $SLOWDNS_BIN (pas de re-téléchargement)"
    return
  fi
  log "Téléchargement du binaire SlowDNS depuis : $BIN_URL"
  mkdir -p "$(dirname "$SLOWDNS_BIN")"
  if ! wget -q -O "$SLOWDNS_BIN" "$BIN_URL"; then
    echo "Erreur téléchargement du binaire. Vérifie BIN_URL ou connexion réseau." >&2
    exit 1
  fi
  chmod +x "$SLOWDNS_BIN"
  if [ ! -x "$SLOWDNS_BIN" ]; then
    echo "Le binaire n'est pas exécutable après téléchargement." >&2
    exit 1
  fi
}

generate_keys() {
  mkdir -p "$SLOWDNS_DIR"
  SERVER_KEY="$SLOWDNS_DIR/server.key"
  SERVER_PUB="$SLOWDNS_DIR/server.pub"
  if [ ! -f "$SERVER_KEY" ] || [ ! -f "$SERVER_PUB" ]; then
    log "Génération de clés (random) pour SlowDNS..."
    # simple clé aléatoire hex (compatible avec la plupart des implémentations dns-server)
    head -c 32 /dev/urandom | xxd -p -c 999 > "$SERVER_KEY"
    head -c 32 /dev/urandom | xxd -p -c 999 > "$SERVER_PUB"
    chmod 600 "$SERVER_KEY"
    chmod 644 "$SERVER_PUB"
  else
    log "Clés existantes trouvées."
  fi
}

optimize_sysctl() {
  log "Écriture des optimisations réseau (sysctl) — non intrusif..."
  cat > "$SYSCTL_FILE" <<EOF
# SlowDNS speed tuning
net.core.rmem_max=8388608
net.core.wmem_max=8388608
net.core.rmem_default=262144
net.core.wmem_default=262144
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384
net.ipv4.ip_forward=1
net.ipv4.tcp_mtu_probing=1
EOF
  sysctl --system >/dev/null || true
}

ensure_port_free_or_disable_stub() {
  # Check if UDP 53 is free on all addresses
  if ss -lun4 | awk '{print $5}' | grep -q ':53$'; then
    log "Port UDP 53 semble occupé. Tentative non-destructive: désactiver DNSStubListener de systemd-resolved si présent."
    if [ -f /etc/systemd/resolved.conf ]; then
      # backup
      cp -n /etc/systemd/resolved.conf /etc/systemd/resolved.conf.bak || true
      if ! grep -q '^DNSStubListener=no' /etc/systemd/resolved.conf; then
        sed -i '/^#DNSStubListener=/d' /etc/systemd/resolved.conf || true
        echo "DNSStubListener=no" >> /etc/systemd/resolved.conf
        systemctl restart systemd-resolved || true
        sleep 1
      fi
    fi
  fi

  # re-check
  if ss -lun4 | awk '{print $5}' | grep -q ':53$'; then
    log "Après tentative, UDP 53 est toujours occupé. Le script passe en mode fallback sur le port $FALLBACK_PORT. (Moins optimal)"
    PORT="$FALLBACK_PORT"
  else
    log "Port UDP 53 disponible -> utilisation de 53 (optimal)."
    PORT=53
  fi
}

set_mtu_on_active_interface() {
  # set MTU 1280 on the primary non-loopback interface
  iface=$(ip -o link show up | awk -F': ' '{print $2}' \
        | grep -v '^lo$' \
        | grep -vE '^(docker|veth|br|virbr|tun|tap|wl|vmnet|vboxnet)' \
        | head -n1 || true)
  if [ -n "$iface" ]; then
    log "Réglage MTU à 1280 pour $iface (optimisé SlowDNS)."
    ip link set dev "$iface" mtu 1280 || log "Échec réglage MTU pour $iface — continuer."
  else
    log "Aucune interface réseau non-loopback détectée pour réglage MTU."
  fi
}

configure_iptables_accept() {
  log "Application règles iptables minimales (ACCEPT udp dport $PORT)..."
  if ! iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT &>/dev/null; then
    iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
  fi
  # sauvegarde persistante
  iptables-save > /etc/iptables/rules.v4 || true
  systemctl enable netfilter-persistent >/dev/null 2>&1 || true
  systemctl restart netfilter-persistent >/dev/null 2>&1 || true
}

create_systemd_service() {
  log "Création du service systemd slowdns..."
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=SlowDNS Server (Speed Edition)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$SLOWDNS_BIN -udp :$PORT -privkey-file $SLOWDNS_DIR/server.key \$(cat $SLOWDNS_DIR/ns.conf 2>/dev/null || echo "") 0.0.0.0:22
Restart=on-failure
RestartSec=3
StandardOutput=append:/var/log/slowdns.log
StandardError=append:/var/log/slowdns.log
LimitNOFILE=1048576
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable slowdns.service
}

store_env_and_ns() {
  # ask for NS non interactively? We'll read from stdin if provided; else attempt to preserve existing config
  if [ -z "${NAMESERVER:-}" ]; then
    read -rp "Entrez le NameServer (NS) (ex: ns.example.com) : " NAMESERVER_INPUT || true
    NAMESERVER="${NAMESERVER_INPUT:-}"
  fi
  if [ -z "$NAMESERVER" ]; then
    echo "NameServer invalide. Abandon." >&2
    exit 1
  fi
  echo "$NAMESERVER" > "$SLOWDNS_DIR/ns.conf"
  cat > "$ENV_FILE" <<EOF
NS=$NAMESERVER
PUB_KEY=$(cat $SLOWDNS_DIR/server.pub)
PRIV_KEY=$(cat $SLOWDNS_DIR/server.key)
EOF
  chmod 600 "$ENV_FILE"
  log "NS enregistré dans $SLOWDNS_DIR/ns.conf et variables dans $ENV_FILE"
}

show_summary() {
  echo
  echo "+--------------------------------------------+"
  echo "|        SLOWDNS — SPEED EDITION READY       |"
  echo "+--------------------------------------------+"
  echo "Port UDP utilisé : $PORT"
  echo "Binaire        : $SLOWDNS_BIN"
  echo "Dossier config : $SLOWDNS_DIR"
  echo "Clé publique   : $(cat $SLOWDNS_DIR/server.pub)"
  echo
  echo "Pour obtenir de meilleur débit (si le port 53 a été fallback -> $FALLBACK_PORT) :"
  echo " - libérer UDP/53 (arrêter service qui écoute) pour permettre l'écoute directe sur 53."
  echo " - utiliser une version 'speed-patched' du binaire si tu en disposes (mettre BIN_URL avant exécution)."
  echo
  echo "Démarrage service : systemctl start slowdns"
  echo "Logs : tail -f /var/log/slowdns.log"
  echo
}

main() {
  check_root
  install_pkgs
  download_bin
  generate_keys
  optimize_sysctl
  ensure_port_free_or_disable_stub
  set_mtu_on_active_interface
  configure_iptables_accept
  store_env_and_ns
  create_systemd_service

  log "Démarrage du service slowdns..."
  systemctl restart slowdns.service || ( journalctl -u slowdns.service --no-pager -n 200; exit 1 )

  show_summary
}

main "$@"
