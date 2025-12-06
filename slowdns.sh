#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=53
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
API_PORT=9999
DOMAIN="kingdom.qzz.io"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Vérification root
if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en root." >&2
    exit 1
fi

# Dépendances système
log "Installation des dépendances système..."
apt update -y
apt install -y iptables iptables-persistent curl tcpdump jq python3 python3-venv python3-pip

# DNSTT
if [ ! -x "$SLOWDNS_BIN" ]; then
    log "Téléchargement du binaire DNSTT..."
    curl -L -o "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
    chmod +x "$SLOWDNS_BIN"
fi

mkdir -p "$SLOWDNS_DIR"

# Création de l'environnement Python isolé pour l'API
VENV_DIR="$SLOWDNS_DIR/venv"
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install flask cloudflare

# Choix du mode
read -rp "Choisissez le mode d'installation [auto/man] : " MODE
MODE=${MODE,,}  # lowercase

if [[ "$MODE" == "auto" ]]; then
    log "Mode AUTO sélectionné : génération automatique du NS"

    # Création du script API
    API_SCRIPT="$SLOWDNS_DIR/api.py"
    cat <<EOF > "$API_SCRIPT"
from flask import Flask, request, jsonify
import random, string
app = Flask(__name__)

DOMAIN = "$DOMAIN"

def random_id(length=6):
    return ''.join(random.choice(string.ascii_lowercase + string.digits) for _ in range(length))

@app.route("/create", methods=["GET"])
def create():
    ip = request.args.get("ip")
    if not ip:
        return jsonify({"error":"Missing IP"}),400
    sub = "tun-" + random_id()
    fqdn = f"{sub}.{DOMAIN}"
    return jsonify({"domain": fqdn})

if __name__=="__main__":
    app.run(host="0.0.0.0", port=$API_PORT)
EOF

    # Lancer l’API en arrière-plan via le venv
    nohup "$VENV_DIR/bin/python" "$API_SCRIPT" >/dev/null 2>&1 &

    sleep 2  # attendre l'API

    # Récupération du NS depuis l'API
    DOMAIN_NS=$(curl -s "http://127.0.0.1:$API_PORT/create?ip=$(curl -s ipv4.icanhazip.com)" | jq -r .domain)
    echo "$DOMAIN_NS" > "$CONFIG_FILE"
    log "NS généré automatiquement : $DOMAIN_NS"

elif [[ "$MODE" == "man" ]]; then
    log "Mode MANUEL sélectionné : saisie manuelle du NS"
    read -rp "Entrez le NameServer (NS) complet (ex: ns.example.com) : " DOMAIN_NS
    echo "$DOMAIN_NS" > "$CONFIG_FILE"
else
    echo "Mode invalide. Utilisez 'auto' ou 'man'." >&2
    exit 1
fi

# Clés fixes
echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
chmod 600 "$SERVER_KEY"
chmod 644 "$SERVER_PUB"

# Wrapper SlowDNS
cat <<'EOF' > /usr/local/bin/slowdns-start.sh
#!/bin/bash
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=53
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
NS=$(cat "$CONFIG_FILE")
ssh_port=22
exec "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" "$NS" 0.0.0.0:$ssh_port
EOF
chmod +x /usr/local/bin/slowdns-start.sh

# Service systemd
cat <<EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS Server Tunnel (DNSTT)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/slowdns-start.sh
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
