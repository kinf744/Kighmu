#!/bin/bash
set -euo pipefail

echo "=== Installation ZIVPN UDP (aligned official / nftables + logging) ==="

apt update -y
apt install -y wget curl jq nftables openssl socat

systemctl stop zivpn.service >/dev/null 2>&1 || true

echo "[+] Téléchargement ZIVPN"
wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 \
-O /usr/local/bin/zivpn
chmod +x /usr/local/bin/zivpn

mkdir -p /etc/zivpn
CONFIG_FILE="/etc/zivpn/config.json"

DOMAIN_FILE="/etc/zivpn/domain.txt"
CERT="/etc/zivpn/zivpn.crt"
KEY="/etc/zivpn/zivpn.key"
LOG_FILE="/var/log/zivpn.log"

# -------------------- Domaine --------------------
if [[ -f "$DOMAIN_FILE" ]]; then
    DOMAIN=$(cat "$DOMAIN_FILE")
else
    read -rp "Entrez votre nom de domaine pour ZIVPN : " DOMAIN
    if [[ -z "$DOMAIN" ]]; then
        echo "❌ Domaine non valide."
        exit 1
    fi
    echo "$DOMAIN" > "$DOMAIN_FILE"
fi

# -------------------- Certificat --------------------
if [[ -f "$CERT" && -f "$KEY" ]]; then
    echo "[+] Certificat existant trouvé → réutilisation"
else
    echo "[+] Génération certificat ZIVPN auto-signé pour $DOMAIN"
    openssl req -x509 -newkey rsa:2048 \
    -keyout "$KEY" \
    -out "$CERT" \
    -nodes -days 3650 \
    -subj "/CN=$DOMAIN"
fi

chmod 600 "$KEY"
chmod 644 "$CERT"

# -------------------- Config JSON --------------------
cat <<EOF > "$CONFIG_FILE"
{
  "listen": ":5667",
  "cert": "$CERT",
  "key": "$KEY",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": ["zi"]
  }
}
EOF

# -------------------- Systemd avec log --------------------
cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=ZIVPN UDP Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/zivpn server -c $CONFIG_FILE 2>> $LOG_FILE
WorkingDirectory=/etc/zivpn
Restart=always
RestartSec=3
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable zivpn

# -------------------- SYSCTL --------------------
cat <<EOF > /etc/sysctl.d/99-zivpn.conf
net.ipv4.ip_forward=1
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF
sysctl --system >/dev/null

# -------------------- NFTABLES --------------------
mkdir -p /etc/nftables.d
cat <<EOF > /etc/nftables.d/zivpn.nft
table ip zivpn {
  chain prerouting {
    type nat hook prerouting priority -100;
    udp dport 6000-19999 dnat to 0.0.0.0:5667
  }

  chain input {
    type filter hook input priority 0;
    udp dport 5667 accept
    udp dport 6000-19999 accept
    ct state established,related accept
  }

  chain forward {
    type filter hook forward priority 0;
    accept
  }

  chain postrouting {
    type nat hook postrouting priority 100;
    oifname != "tun0" masquerade
  }
}
EOF

systemctl enable nftables
systemctl restart nftables
nft -f /etc/nftables.d/zivpn.nft

if ! grep -q nftables.d /etc/nftables.conf 2>/dev/null; then
  echo 'include "/etc/nftables.d/*.nft"' >> /etc/nftables.conf
fi

# -------------------- Start service --------------------
systemctl restart zivpn
sleep 2

if systemctl is-active --quiet zivpn; then
  echo ""
  echo "✅ ZIVPN OPÉRATIONNEL"
  echo "➡️ UDP Port : 5667"
  echo "➡️ Domaine : $DOMAIN"
  echo "➡️ Certificat : $CERT"
  echo "➡️ Firewall : nftables (NAT actif)"
  echo "➡️ Tunnel : IP-over-UDP (TUN)"
  echo "➡️ Logs côté serveur : $LOG_FILE"
else
  echo ""
  echo "❌ ZIVPN ÉCHEC"
  journalctl -u zivpn -n 50 --no-pager
fi
