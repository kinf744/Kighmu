#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/dnstt-server"
PORT=53
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
API_PORT=9999
VENV_DIR="$SLOWDNS_DIR/venv"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Vérification root
if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en root." >&2
    exit 1
fi

# Dépendances système
apt update -y
apt install -y iptables iptables-persistent curl tcpdump jq python3 python3-venv

# DNSTT
if [ ! -x "$SLOWDNS_BIN" ]; then
    log "Téléchargement du binaire DNSTT..."
    curl -L -o "$SLOWDNS_BIN" https://dnstt.network/dnstt-server-linux-amd64
    chmod +x "$SLOWDNS_BIN"
fi

mkdir -p "$SLOWDNS_DIR"

# Création du virtualenv Python
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install flask cloudflare

# Création du serveur API interne (auto NS)
API_SCRIPT="$SLOWDNS_DIR/api.py"
cat <<EOF > "$API_SCRIPT"
from flask import Flask, request, jsonify
import random, string
app = Flask(__name__)

DOMAIN = "kingdom.qzz.io"

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

# Lancer l’API en arrière-plan
nohup "$VENV_DIR/bin/python" "$API_SCRIPT" >/dev/null 2>&1 &

# Choix du mode auto/man
read -rp "Choisissez le mode d'installation [auto/man] : " INSTALL_MODE
INSTALL_MODE="${INSTALL_MODE,,}"  # minuscule

if [[ "$INSTALL_MODE" == "man" ]]; then
    read -rp "Entrez le NameServer (NS) à utiliser : " DOMAIN_NS
elif [[ "$INSTALL_MODE" == "auto" ]]; then
    sleep 2  # attendre que l'API soit prête
    DOMAIN_NS=$(curl -s "http://127.0.0.1:$API_PORT/create?ip=$(curl -s ipv4.icanhazip.com)" | jq -r .domain)
else
    echo "Mode invalide. Choisissez 'auto' ou 'man'." >&2
    exit 1
fi

echo "$DOMAIN_NS" > "$CONFIG_FILE"
log "NS sélectionné : $DOMAIN_NS"

# Clés fixes (ou générer dynamiquement si tu veux)
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
