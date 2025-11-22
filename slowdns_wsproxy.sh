#!/bin/bash
set -euo pipefail

# Chemins et paramètres personnalisables
SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PROXYWS_PATH="/usr/local/bin/slowdns_wsproxy.py"
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
SSH_PORT=22
SLOWDNS_PORT=5300
WS_PORT=9900

read -rp "Entrez le NameServer (NS) (ex: ns.example.com): " NAMESERVER
[ -z "$NAMESERVER" ] && { echo "NS requis"; exit 1; }

apt update
apt install -y python3 wget curl iptables iptables-persistent lsof

mkdir -p "$SLOWDNS_DIR"

# Installation du binaire SlowDNS
if [ ! -x "$SLOWDNS_BIN" ]; then
  wget -qO "$SLOWDNS_BIN" "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server"
  chmod +x "$SLOWDNS_BIN"
fi

# Génération des clés par défaut (personnalise si besoin)
echo "4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa" > "$SERVER_KEY"
echo "2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c" > "$SERVER_PUB"
chmod 600 "$SERVER_KEY"
chmod 644 "$SERVER_PUB"
echo "$NAMESERVER" > "$CONFIG_FILE"

# Dépôt du fichier proxy Python (mets ici ton slowdns_wsproxy.py complet après installation !)
touch "$PROXYWS_PATH" && chmod +x "$PROXYWS_PATH"

# Service systemd pour SlowDNS (avec redémarrage automatique et watchdog)
cat > /etc/systemd/system/slowdns.service <<EOF
[Unit]
Description=SlowDNS Server Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$SLOWDNS_BIN -udp :$SLOWDNS_PORT -privkey-file $SERVER_KEY $NAMESERVER 0.0.0.0:$SSH_PORT
Restart=always
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=5
WatchdogSec=30
NotifyAccess=all

[Install]
WantedBy=multi-user.target
EOF

# Service systemd pour slowdns_wsproxy.py (avec redémarrage automatique et watchdog)
cat > /etc/systemd/system/wsproxy.service <<EOF
[Unit]
Description=WebSocket Proxy pour SlowDNS
After=slowdns.service network-online.target
Wants=slowdns.service network-online.target

[Service]
Type=simple
ExecStart=python3 $PROXYWS_PATH -p $WS_PORT
WorkingDirectory=/root
Restart=always
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=5
WatchdogSec=30
NotifyAccess=all

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

# Messages de fin
echo
echo "+--------------------------------------+"
echo "| SlowDNS + WebSocket Proxy installés !|"
echo "+--------------------------------------+"
echo "SlowDNS UDP : $SLOWDNS_PORT"
echo "WS Proxy TCP: $WS_PORT"
echo "Le proxy est : $PROXYWS_PATH (AJOUTE TON SCRIPT COMPLET DEDANS)"
echo ""
echo "NS utilisé : $NAMESERVER"
cat "$SERVER_PUB" | awk '{print "Clé publique : "$0}'
echo ""
echo "Tunnel SSH WS + SlowDNS prêt côté serveur !"
echo "Connecte-toi côté client en combinant slowdns-client et le proxy Python WS identique."

echo "Astuce SSH : Ajoute dans /etc/ssh/sshd_config"
echo " Ciphers aes128-ctr,aes192-ctr,aes128-gcm@openssh.com"
echo " MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-256"
echo " Compression yes"
echo "Puis lance : systemctl restart sshd"
