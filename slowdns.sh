#!/bin/bash
set -euo pipefail

RED='\u001B[0;31m'
GREEN='\u001B[0;32m'
YELLOW='\u001B[0;33m'
BLUE='\u001B[0;34m'
CYAN='\u001B[0;36m'
BOLD='\u001B[1m'
NC='\u001B[0m'

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=53
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"

CF_API_TOKEN="7mn4LKcZARvdbLlCVFTtaX7LGM2xsnyjHkiTAt37"
CF_ZONE_ID="7debbb8ea4946898a889c4b5745ab7eb"
DOMAIN="kingom.ggff.net"
DEBUG=true

log() { echo -e "[${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC}] $*"; }
log_debug() {
    if [ "$DEBUG" = true ]; then
        echo -e "[${YELLOW}DEBUG${NC}] $*"
    fi
}

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Ce script doit être exécuté en root.${NC}" >&2
    exit 1
fi

verify_cloudflare_token() {
    log "Vérification du token Cloudflare..."
    RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" || true)

    if ! echo "$RESPONSE" | grep -q '"status":"active"'; then
        echo -e "${RED}❌ Token Cloudflare invalide ou permissions insuffisantes.${NC}"
        echo "$RESPONSE"
        exit 1
    fi

    log_debug "Token vérifié : $RESPONSE"
    log "✔️ Token Cloudflare valide."
}

verify_cloudflare_zone() {
    log "Vérification de la zone Cloudflare..."
    ZONE_INFO=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" || true)

    if ! echo "$ZONE_INFO" | grep -q '"success":true'; then
        echo -e "${RED}❌ Zone ID Cloudflare invalide : $CF_ZONE_ID${NC}"
        exit 1
    fi

    ZONE_NAME=$(echo "$ZONE_INFO" | jq -r .result.name)
    log_debug "Zone trouvée : $ZONE_NAME"

    if [[ "$DOMAIN" != *"$ZONE_NAME" ]]; then
        echo -e "${RED}❌ Domaine '$DOMAIN' n'appartient pas à la zone Cloudflare '$ZONE_NAME'${NC}"
        exit 1
    fi

    log "✔️ Zone Cloudflare valide : $ZONE_NAME"
}

log "Installation des dépendances..."
if ! apt update -y; then
    log "${YELLOW}⚠️ apt update a échoué, vérifie ta connexion mais on continue.${NC}"
fi
if ! apt install -y iptables iptables-persistent curl jq python3 python3-venv python3-pip; then
    log "${YELLOW}⚠️ apt install a échoué pour certains paquets, vérifie manuellement.${NC}"
fi

mkdir -p "$SLOWDNS_DIR"
python3 -m venv "$SLOWDNS_DIR/venv"
source "$SLOWDNS_DIR/venv/bin/activate"
pip install --upgrade pip
pip install cloudflare flask

verify_cloudflare_token
verify_cloudflare_zone

if [ ! -x "$SLOWDNS_BIN" ]; then
    log "Téléchargement du binaire DNSTT..."
    if ! curl -L -o "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64; then
        echo -e "${RED}❌ Échec du téléchargement du binaire DNSTT.${NC}"
        exit 1
    fi
    chmod +x "$SLOWDNS_BIN"
fi

read -rp "Choisissez le mode d'installation [auto/man] : " MODE
MODE=${MODE,,}

if [[ "$MODE" == "auto" ]]; then
    log "Mode AUTO sélectionné."
    VPS_IP=$(curl -s ipv4.icanhazip.com || echo "0.0.0.0")
    SUB_A="vpn-$(date +%s | sha256sum | head -c 6)"
    FQDN_A="$SUB_A.$DOMAIN"
    log "Création de l'enregistrement A : $FQDN_A -> $VPS_IP"
    ADD_A=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{"type":"A","name":"$FQDN_A","content":"$VPS_IP","ttl":1,"proxied":false}" || true)
    log_debug "Réponse Cloudflare A : $ADD_A"

    SUB_NS="ns-$(date +%s | sha256sum | head -c 6)"
    DOMAIN_NS="$SUB_NS.$DOMAIN"
    log "Création de l'enregistrement NS : $DOMAIN_NS → $FQDN_A"
    ADD_NS=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{"type":"NS","name":"$DOMAIN_NS","content":"$FQDN_A","ttl":1}" || true)
    log_debug "Réponse Cloudflare NS : $ADD_NS"

elif [[ "$MODE" == "man" ]]; then
    read -rp "Entrez le NS : " DOMAIN_NS
else
    echo -e "${RED}❌ Mode invalide.${NC}"
    exit 1
fi

echo "$DOMAIN_NS" > "$CONFIG_FILE"

echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
chmod 600 "$SERVER_KEY"
chmod 644 "$SERVER_PUB"

cat <<'EOF' > /usr/local/bin/slowdns-start.sh
#!/bin/bash
SLOWDNS_DIR="/etc/slowdns"
PORT=53
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"

NS=$(cat "$CONFIG_FILE")
ssh_port=22

exec "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" "$NS" 0.0.0.0:$ssh_port
EOF
chmod +x /usr/local/bin/slowdns-start.sh

cat <<EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS Tunnel (DNSTT)
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/slowdns-start.sh
Restart=always
RestartSec=2
StartLimitBurst=10
StartLimitIntervalSec=60
LimitNOFILE=1048576
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
StandardOutput=append:/var/log/slowdns.log
StandardError=append:/var/log/slowdns.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable slowdns.service
systemctl restart slowdns.service

PUB_KEY=$(cat "$SERVER_PUB")
log "✔️ SlowDNS installé avec succès !"

echo -e ""
echo -e "${GREEN}${BOLD}============================================${NC}"
echo -e "${GREEN}${BOLD}   SlowDNS installé avec succès !${NC}"
echo -e "${GREEN}${BOLD}============================================${NC}"
echo -e "${CYAN}Port DNS utilisé   :${NC} ${YELLOW}$PORT${NC}"
echo -e "${CYAN}Domaine NS utilisé :${NC} ${YELLOW}$DOMAIN_NS${NC}"
echo -e "${CYAN}Clé publique       :${NC} ${YELLOW}$PUB_KEY${NC}"
echo -e "${GREEN}${BOLD}============================================${NC}"
echo -e ""
