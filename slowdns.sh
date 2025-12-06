#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
WRAPPER_SCRIPT="/usr/local/bin/slowdns-start.sh"
PORT=53
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
API_PORT=9999

# Cloudflare
CF_API_TOKEN="TON_TOKEN_CLOUDFLARE"
CF_ZONE_ID="TON_ZONE_ID_CLOUDFLARE"
DOMAIN="kingdom.qzz.io"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Vérification root
if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en root." >&2
    exit 1
fi

# Dépendances système
log "Installation des dépendances..."
apt update -y
apt install -y iptables iptables-persistent curl tcpdump jq python3 python3-venv python3-pip

# Création du répertoire SlowDNS
mkdir -p "$SLOWDNS_DIR"

# Installation DNSTT
if [ ! -x "$SLOWDNS_BIN" ]; then
    log "Téléchargement du binaire DNSTT..."
    curl -L -o "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
    chmod +x "$SLOWDNS_BIN"
fi

# Création d’un venv Python local pour Flask & Cloudflare
PY_VENV="$SLOWDNS_DIR/venv"
if [ ! -d "$PY_VENV" ]; then
    log "Création du virtualenv Python..."
    python3 -m venv "$PY_VENV"
fi

source "$PY_VENV/bin/activate"
pip install --upgrade pip
pip install flask cloudflare
deactivate

# Choix du mode d’installation
read -rp "Choisissez le mode d'installation [auto/man] : " INSTALL_MODE

if [[ "$INSTALL_MODE" == "auto" ]]; then
    log "Mode AUTO sélectionné : génération automatique du NS et A record"

    # Générer un sous-domaine aléatoire
    SUBDOMAIN="tun-$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)"
    NS="$SUBDOMAIN.$DOMAIN"

    # Récupérer IP publique
    PUBLIC_IP=$(curl -s ipv4.icanhazip.com)

    log "Création de l'enregistrement A sur Cloudflare pour $SUBDOMAIN -> $PUBLIC_IP"
    CREATE_A=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$SUBDOMAIN\",\"content\":\"$PUBLIC_IP\",\"ttl\":120,\"proxied\":false}")

    log "A record créé : $(echo $CREATE_A | jq -r '.success')"

    # Créer un NS pointant vers le même sous-domaine (si nécessaire côté VPN HC)
    # Certains VPN HC utilisent directement le sous-domaine A comme NS
    DOMAIN_NS="$NS"

elif [[ "$INSTALL_MODE" == "man" ]]; then
    log "Mode MANUEL sélectionné : veuillez saisir le NS"
    read -rp "Entrez votre NameServer (NS) : " DOMAIN_NS
else
    echo "Mode invalide ! Choisissez 'auto' ou 'man'."
    exit 1
fi

# Enregistrement du NS
echo "$DOMAIN_NS" > "$CONFIG_FILE"
log "NS sélectionné : $DOMAIN_NS"

# Clés fixes
echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
chmod 600 "$SERVER_KEY"
chmod 644 "$SERVER_PUB"

# Wrapper SlowDNS
cat <<EOF > "$WRAPPER_SCRIPT"
#!/bin/bash
SLOWDNS_DIR="$SLOWDNS_DIR"
SLOWDNS_BIN="$SLOWDNS_BIN"
PORT=$PORT
CONFIG_FILE="$CONFIG_FILE"
SERVER_KEY="$SERVER_KEY"
NS=\$(cat "\$CONFIG_FILE")
ssh_port=22
exec "\$SLOWDNS_BIN" -udp :\$PORT -privkey-file "\$SERVER_KEY" "\$NS" 0.0.0.0:\$ssh_port
EOF
chmod +x "$WRAPPER_SCRIPT"

# Service systemd
cat <<EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS Server Tunnel (DNSTT)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$WRAPPER_SCRIPT
Restart=on-failure
RestartSec=3
StandardOutput=append:/var/log/slowdns.log
StandardError=append:/var/log/slowdns.log
SyslogIdentifier=slowdns
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable slowdns.service
systemctl restart slowdns.service

log "SlowDNS installé et démarré avec NS : $DOMAIN_NS"
