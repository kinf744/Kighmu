#!/bin/bash
set -euo pipefail

# Chemins et paramètres personnalisables
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PROXYWS_PATH="/usr/local/bin/ws2_proxy.py"
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
SSH_PORT=22
SLOWDNS_PORT=5300
WS_PORT=9900

# Demande du NS à l'utilisateur
read -rp "Entrez le NameServer (NS) (ex: ns.example.com): " NAMESERVER
[ -z "$NAMESERVER" ] && { echo "NS requis"; exit 1; }

# Installation des dépendances
apt update
apt install -y python3 wget curl iptables iptables-persistent lsof

mkdir -p "$SLOWDNS_DIR"

# Installation du binaire SlowDNS
if [ ! -x "$SLOWDNS_BIN" ]; then
  wget -qO "$SLOWDNS_BIN" "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server"
  chmod +x "$SLOWDNS_BIN"
fi

# Génération des clés (exemple : à remplacer si besoin)
echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
chmod 600 "$SERVER_KEY"
chmod 644 "$SERVER_PUB"
echo "$NAMESERVER" > "$CONFIG_FILE"

# Dépôt du fichier proxy WebSocket Python
# Place ton script ws2_proxy.py ici en le collant ou uploadant à /usr/local/bin/ws2_proxy.py après installation !
touch "$PROXYWS_PATH" && chmod +x "$PROXYWS_PATH"

# Service systemd pour SlowDNS
cat > /etc/systemd/system/slowdns.service <<EOF
[Unit]
Description=SlowDNS Server Tunnel
After=network.target

[Service]
Type=simple
ExecStart=$SLOWDNS_BIN -udp :$SLOWDNS_PORT -privkey-file $SERVER_KEY $NAMESERVER 0.0.0.0:$SSH_PORT
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Service systemd pour ws2_proxy.py
cat > /etc/systemd/system/wsproxy.service <<EOF
[Unit]
Description=WebSocket Proxy pour SlowDNS (Kighmu)
After=slowdns.service

[Service]
Type=simple
ExecStart=python3 $PROXYWS_PATH -p $WS_PORT
WorkingDirectory=/root
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Firewall
iptables -I INPUT -p udp --dport $SLOWDNS_PORT -j ACCEPT || true
iptables -I INPUT -p tcp --dport $WS_PORT -j ACCEPT || true
iptables-save > /etc/iptables/rules.v4

# Activation des services
systemctl daemon-reload
systemctl enable --now slowdns.service wsproxy.service

# Affichage configuration
echo
echo "+--------------------------------------+"
echo "|        SlowDNS + WS Proxy prêts      |"
echo "+--------------------------------------+"
echo "Port SlowDNS UDP  : $SLOWDNS_PORT"
echo "Port Proxy WS TCP : $WS_PORT"
echo "SSH interne       : localhost:$SSH_PORT"
echo "Le proxy WebSocket est ici : $PROXYWS_PATH (mets le code complet dans ce fichier !)"
echo ""
echo "NS utilisé : $NAMESERVER"
cat "$SERVER_PUB" | awk '{print "Clé publique : "$0}'
echo ""
echo "Tu peux maintenant lancer le client SSH combiné WS + SlowDNS."
echo "Proxy côté client : identique, connecte le SSH sur le port WS côté serveur ($WS_PORT)."
echo

echo "Astuce SSH : /etc/ssh/sshd_config ->"
echo "  Ciphers aes128-ctr,aes192-ctr,aes128-gcm@openssh.com"
echo "  MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-256"
echo "  Compression yes"
echo "systemctl restart sshd"
