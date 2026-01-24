#!/bin/bash
set -euo pipefail

echo "=== Installation ZIVPN UDP (aligned official / nftables) ==="

# ===================== DEPENDANCES =====================
apt update -y
apt install -y wget curl jq nftables openssl socat

# ===================== STOP SERVICE =====================
systemctl stop zivpn.service >/dev/null 2>&1 || true

# ===================== INSTALL BINARY =====================
echo "[+] Téléchargement ZIVPN"
wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 \
  -O /usr/local/bin/zivpn
chmod +x /usr/local/bin/zivpn

# ===================== PATHS =====================
mkdir -p /etc/zivpn
CONFIG_FILE="/etc/zivpn/config.json"

CERT="/etc/zivpn/zivpn.crt"
KEY="/etc/zivpn/zivpn.key"

# ===================== CERTIFICAT (OBLIGATOIRE POUR ZIVPN) =====================
if [[ ! -f "$CERT" || ! -f "$KEY" ]]; then
  echo "[+] Génération certificat ZIVPN (auto-signé, attendu par le binaire)"
  openssl req -x509 -newkey rsa:2048 \
    -keyout "$KEY" \
    -out "$CERT" \
    -nodes -days 3650 \
    -subj "/CN=zivpn"
fi

chmod 600 "$KEY"
chmod 644 "$CERT"

# ===================== CONFIG.JSON (OFFICIEL) =====================
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

# ===================== SYSTEMD =====================
cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=ZIVPN UDP Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/zivpn server -c $CONFIG_FILE
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

# ===================== SYSCTL (OBLIGATOIRE POUR TUNNEL) =====================
cat <<EOF > /etc/sysctl.d/99-zivpn.conf
net.ipv4.ip_forward=1
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF
sysctl --system >/dev/null

# ===================== NFTABLES (CORRECT ZIVPN) =====================
echo "[+] Configuration nftables (NAT + FORWARD)"

mkdir -p /etc/nftables.d

cat <<EOF > /etc/nftables.d/zivpn.nft
table inet zivpn {

  chain input {
    type filter hook input priority 0;
    udp dport 5667 accept
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

# ===================== START SERVICE =====================
systemctl restart zivpn
sleep 2

# ===================== STATUS =====================
if systemctl is-active --quiet zivpn; then
  echo ""
  echo "✅ ZIVPN OPÉRATIONNEL"
  echo "➡️ UDP Port : 5667"
  echo "➡️ Certificat : $CERT"
  echo "➡️ Firewall : nftables (NAT actif)"
  echo "➡️ Tunnel : IP-over-UDP (TUN)"
else
  echo ""
  echo "❌ ZIVPN ÉCHEC"
  journalctl -u zivpn -n 50 --no-pager
fi
