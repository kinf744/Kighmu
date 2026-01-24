#!/bin/bash
set -euo pipefail

echo "=== Installation ZIVPN UDP (clean & nftables) ==="

# ===================== DEPENDANCES =====================
apt update -y
apt install -y wget curl jq nftables openssl

systemctl stop zivpn.service >/dev/null 2>&1 || true

# ===================== INSTALL BINARY =====================
echo "[+] Téléchargement ZIVPN"
wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 \
    -O /usr/local/bin/zivpn
chmod +x /usr/local/bin/zivpn

# ===================== CONFIG =====================
mkdir -p /etc/zivpn

cat <<EOF > /etc/zivpn/config.json
{
  "listen": ":5667",
  "config": []
}
EOF

# ===================== CERTIFICATS =====================
echo "[+] Génération certificats TLS"
openssl req -new -newkey rsa:4096 -nodes -x509 -days 365 \
-subj "/C=US/ST=NA/L=NA/O=ZIVPN/OU=UDP/CN=zivpn" \
-keyout /etc/zivpn/zivpn.key \
-out /etc/zivpn/zivpn.crt

# ===================== SYSCTL (persistant) =====================
cat <<EOF > /etc/sysctl.d/99-zivpn.conf
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF
sysctl --system >/dev/null

# ===================== SYSTEMD =====================
cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=ZIVPN UDP Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
WorkingDirectory=/etc/zivpn
Restart=always
RestartSec=3
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable zivpn
systemctl start zivpn

# ===================== NFTABLES =====================
echo "[+] Configuration nftables"

mkdir -p /etc/nftables.d

cat <<EOF > /etc/nftables.d/zivpn.nft
table inet zivpn {

    chain prerouting {
        type nat hook prerouting priority -100;
        udp dport 6000-19999 dnat to :5667
    }

    chain input {
        type filter hook input priority 0;
        udp dport 5667 accept
        udp dport 6000-19999 accept
    }
}
EOF

# Activer nftables
systemctl enable nftables
systemctl start nftables

# Charger la règle
nft -f /etc/nftables.d/zivpn.nft

# Rendre persistant
if ! grep -q nftables.d /etc/nftables.conf 2>/dev/null; then
    echo 'include "/etc/nftables.d/*.nft"' >> /etc/nftables.conf
fi

systemctl restart nftables

# ===================== FIN =====================
echo ""
echo "✅ ZIVPN installé avec succès"
echo "➡️ Port interne : 5667"
echo "➡️ Ports externes : UDP 6000–19999"
echo "➡️ Authentification : gérée par menu1.sh"
echo "➡️ Firewall : nftables"
echo ""
