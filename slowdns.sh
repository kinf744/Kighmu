#!/bin/bash
set -euo pipefail

# --- Configuration principale ---
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
ENV_FILE="$SLOWDNS_DIR/slowdns.env"

# --- Cloudflare API (tu peux garder les valeurs existantes) ---
CF_API_TOKEN="7mn4LKcZARvdbLlCVFTtaX7LGM2xsnyjHkiTAt37"
CF_ZONE_ID="7debbb8ea4946898a889c4b5745ab7eb"

# DNS publics pour le serveur lui-même (ne pas rediriger ces adresses)
LOCAL_DNS=("8.8.8.8" "1.1.1.1")

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# --- Vérification root ---
if [ "$EUID" -ne 0 ]; then
  echo "Ce script doit être exécuté en root." >&2
  exit 1
fi

# --- Création dossier ---
mkdir -p "$SLOWDNS_DIR"

# --- Dépendances ---
log "Installation des dépendances..."
apt update -y || true
DEBIAN_FRONTEND=noninteractive apt install -y curl jq python3 python3-venv python3-pip nftables tcpdump

# --- Création venv et paquet Cloudflare python ---
if [ ! -d "$SLOWDNS_DIR/venv" ]; then
  python3 -m venv "$SLOWDNS_DIR/venv"
fi
# shellcheck source=/dev/null
source "$SLOWDNS_DIR/venv/bin/activate"
pip install --upgrade pip >/dev/null
pip install cloudflare >/dev/null

# --- DNSTT (binaire) ---
if [ ! -x "$SLOWDNS_BIN" ]; then
  log "Téléchargement du binaire DNSTT..."
  curl -L -o "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
  chmod +x "$SLOWDNS_BIN"
fi

# --- Détection IP publique/VPS principal (utile pour éviter la boucle DNS) ---
VPS_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || echo "127.0.0.1")
log "IP principale du VPS : $VPS_IP"

# --- Choix du mode ---
read -rp "Choisissez le mode d'installation [auto/man] : " MODE
MODE=${MODE,,}

generate_ns_auto() {
  DOMAIN="kingom.ggff.net"
  # Subdomain unique
  SUB_A="vpn-$(date +%s | sha256sum | head -c 6)"
  FQDN_A="$SUB_A.$DOMAIN"
  log "Création du A : $FQDN_A -> $VPS_IP"

  # TTL raisonnable (éviter 1s qui surcharge Cloudflare)
  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"$FQDN_A\",\"content\":\"$VPS_IP\",\"ttl\":300,\"proxied\":false}" \
    | jq .

  SUB_NS="ns-$(date +%s | sha256sum | head -c 6)"
  NS="$SUB_NS.$DOMAIN"
  log "Création du NS : $NS -> $FQDN_A"

  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"NS\",\"name\":\"$NS\",\"content\":\"$FQDN_A\",\"ttl\":300}" \
    | jq .

  echo -e "NS=$NS\nENV_MODE=auto" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  log "NS auto sauvegardé : $NS"
}

# --- Gestion du NS persistant ---
if [[ "$MODE" == "auto" ]]; then
  if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
    if [[ "${ENV_MODE:-}" == "auto" ]]; then
      log "NS auto existant détecté : $NS"
    else
      log "NS manuel existant → génération d'un nouveau NS auto..."
      generate_ns_auto
      source "$ENV_FILE"
    fi
  else
    log "Aucun fichier NS existant → génération NS auto..."
    generate_ns_auto
    source "$ENV_FILE"
  fi

elif [[ "$MODE" == "man" ]]; then
  read -rp "Entrez le NameServer (NS) à utiliser : " NS
  echo -e "NS=$NS\nENV_MODE=man" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  log "NS manuel sauvegardé : $NS"
else
  echo "Mode invalide." >&2
  exit 1
fi

# --- Écriture du NS dans la config ---
echo "$NS" > "$CONFIG_FILE"
chmod 644 "$CONFIG_FILE"
log "NS utilisé : $NS"

# --- Clés fixes (tu peux les remplacer si tu veux) ---
cat > "$SERVER_KEY" <<'KEY'
4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa
KEY
cat > "$SERVER_PUB" <<'PUB'
2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c
PUB
chmod 600 "$SERVER_KEY"
chmod 644 "$SERVER_PUB"

# --- Kernel tuning (plus agressif pour UDP backlog/ buffers) ---
log "Application des optimisations réseau..."
cat > /etc/sysctl.d/99-slowdns.conf <<'EOF'
# SlowDNS tuning
net.core.rmem_max=26214400
net.core.wmem_max=26214400
net.core.rmem_default=4194304
net.core.wmem_default=4194304
net.core.netdev_max_backlog=50000
net.core.somaxconn=4096
net.ipv4.udp_rmem_min=131072
net.ipv4.udp_wmem_min=131072
net.ipv4.ip_forward=1
EOF
sysctl --system

# --- Wrapper startup SlowDNS (détection interface + MTU safer) ---
cat > /usr/local/bin/slowdns-start.sh <<'EOF'
#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Detect outgoing interface used to reach internet
iface=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
if [ -z "$iface" ]; then
  # fallback: pick first non-loop device
  iface=$(ip -o link show up | awk -F': ' '{print $2}' | grep -v '^lo$' | head -n1)
fi

log "Interface détectée : $iface"

# Try MTU 1500, fallback to discovered MTU or 1480
preferred_mtu=1500
if ip link set dev "$iface" mtu "$preferred_mtu" 2>/dev/null; then
  log "MTU réglée à $preferred_mtu"
else
  current_mtu=$(ip -o link show "$iface" | awk '{for(i=1;i<=NF;i++) if($i=="mtu"){print $(i+1); exit}}')
  if [ -n "$current_mtu" ]; then
    ip link set dev "$iface" mtu "$current_mtu" 2>/dev/null || true
    log "MTU fallback conservée : $current_mtu"
  else
    ip link set dev "$iface" mtu 1480 || true
    log "MTU fallback 1480 appliquée"
  fi
fi

NS=\$(cat "$CONFIG_FILE" 2>/dev/null || echo "")
ssh_port=\$(ss -tlnp | awk '/sshd/ {print $4; exit}' | sed -n 's/.*:\([0-9]*\)$/\1/p')
[ -z "\$ssh_port" ] && ssh_port=22

log "Démarrage du serveur SlowDNS (dnstt) sur udp :$PORT -> ssh port \$ssh_port ..."
exec nice -n 0 "\$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" "\$NS" 0.0.0.0:\$ssh_port
EOF
chmod +x /usr/local/bin/slowdns-start.sh

# --- Service systemd SlowDNS (ajout Watchdog) ---
cat > /etc/systemd/system/slowdns.service <<'EOF'
[Unit]
Description=SlowDNS Server Tunnel (DNSTT)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/slowdns-start.sh
Restart=always
RestartSec=3
WatchdogSec=20
TimeoutStartSec=30
LimitNOFILE=1048576
LimitNPROC=65535
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOF

# --- Configuration nftables SlowDNS (corrigée) ---
# Principes :
#  - On redirige 53->5300 seulement pour le trafic INCOMING qui ne provient PAS du VPS lui-même (évite boucle)
#  - On permet explicitement que le système envoie des requêtes DNS vers LOCAL_DNS (8.8.8.8,1.1.1.1)
#  - On évite de toucher les requêtes locales/loopback

log "Création règles nftables SlowDNS..."
mkdir -p /etc/nftables.d
NFT_FILE="/etc/nftables.d/slowdns.nft"

cat > "$NFT_FILE" <<EOF
table ip slowdns {
    chain prerouting {
        type nat hook prerouting priority -100; policy accept;
        # Ne redirige que les requêtes UDP 53 provenant d'IP distantes (pas du VPS lui-même)
        # VPS_IP remplie ci-après
        ip saddr != $VPS_IP udp dport 53 redirect to $PORT
    }

    chain output {
        type nat hook output priority -100; policy accept;
        # Autoriser explicitement le serveur à joindre les résolveurs publics (évite la boucle)
        ip daddr { ${LOCAL_DNS[0]}, ${LOCAL_DNS[1]} } udp dport 53 accept

        # Ne rediriger AUCUNE requête sortante locale (préserver résolution du système)
        oifname "lo" accept

        # Par défaut : laisser sortir les requêtes du système vers l'extérieur (ne pas rediriger)
        # Ceci évite que le système s'envoie ses propres requêtes dans le tunnel.
        ip daddr $VPS_IP udp dport 53 accept

        # Les autres paquets UDP 53 (ex : venant d'autres namespaces) restent sans changement.
    }
}
EOF

# Inclure les fichiers nftables si ce n'est pas déjà fait (on évite dupliquer la ligne)
if ! grep -q '/etc/nftables.d/*.nft' /etc/nftables.conf 2>/dev/null; then
    echo "include \"/etc/nftables.d/*.nft\"" >> /etc/nftables.conf
fi

# Appliquer les règles (nft -f /etc/nftables.conf)
log "Activation des règles nftables..."
nft -f /etc/nftables.conf || {
  log "Erreur application nftables. Affichage de debug..."
  nft list ruleset || true
}

# --- On supprime le service custom duplicatif si présent pour éviter conflit ---
if systemctl list-unit-files | grep -q '^nftables-redirect.service'; then
  systemctl disable --now nftables-redirect.service || true
  rm -f /etc/systemd/system/nftables-redirect.service || true
fi

# --- Activation services ---
systemctl daemon-reload
systemctl enable slowdns.service
systemctl restart slowdns.service

# activer nftables persist si absent
if ! systemctl is-enabled nftables >/dev/null 2>&1; then
  systemctl enable --now nftables || true
fi

# --- Résumé ---
log "Installation terminée. SlowDNS démarré avec règles nftables ciblées."

echo
echo "Résumé :"
echo "- slowdns.service : $(systemctl is-active slowdns.service 2>/dev/null || echo inactive)"
echo "- nftables (table slowdns) :"
nft list table ip slowdns || echo "table slowdns non trouvée"
