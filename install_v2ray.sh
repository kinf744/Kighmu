#!/bin/bash
set -euo pipefail

CYAN="\u001B[1;36m"
GREEN="\u001B[1;32m"
YELLOW="\u001B[1;33m"
RED="\u001B[1;31m"
RESET="\u001B[0m"

echo -e "${CYAN}=== Installation V2Ray TCP BRUT (Port 5401) ===${RESET}"
echo -n "IP/Domaine VPS : "
read domaine

LOGFILE="/var/log/v2ray_install.log"
sudo touch "$LOGFILE"
sudo chmod 640 "$LOGFILE"

echo "📥 Téléchargement V2Ray..."

sudo apt update -y >/dev/null 2>&1 || true
sudo apt install -y jq unzip netfilter-persistent >/dev/null 2>&1 || true

wget -q https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip -O /tmp/v2ray.zip
unzip -o /tmp/v2ray.zip -d /tmp/v2ray >/dev/null 2>&1
sudo mv /tmp/v2ray/v2ray /usr/local/bin/
sudo chmod +x /usr/local/bin/v2ray

sudo mkdir -p /etc/v2ray
echo "$domaine" | sudo tee /.v2ray_domain >/dev/null

# ======================
# CONFIG V2RAY TCP BRUT
# ======================
cat <<EOF | sudo tee /etc/v2ray/config.json >/dev/null
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 5401,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "00000000-0000-0000-0000-000000000001"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "vless-tcp"
    },
    {
      "port": 2222,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1",
        "port": 22,
        "network": "tcp"
      },
      "tag": "ssh-in"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": ["ssh-in"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "inboundTag": ["vless-tcp"],
        "outboundTag": "direct"
      }
    ]
  }
}
EOF

# ======================
# SYSTEMD
# ======================
sudo tee /etc/systemd/system/v2ray.service >/dev/null <<EOF
[Unit]
Description=V2Ray TCP Brut (SlowDNS)
After=network.target

[Service]
ExecStart=/usr/local/bin/v2ray run -config /etc/v2ray/config.json
Restart=always
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

echo -e "${YELLOW}🔓 Ouverture du port 5401...${RESET}"
sudo iptables -I INPUT -p tcp --dport 5401 -j ACCEPT
sudo netfilter-persistent save >/dev/null 2>&1 || true

sudo systemctl daemon-reload
sudo systemctl enable v2ray
sudo systemctl restart v2ray

sleep 2

if systemctl is-active --quiet v2ray && ss -tln | grep -q :5401; then
    echo -e "${GREEN}🎉 V2Ray TCP BRUT ACTIF !${RESET}"
    echo -e "${GREEN}IP:${RESET} $domaine"
    echo -e "${GREEN}PORT:${RESET} 5401"
    echo -e "${GREEN}UUID:${RESET} 00000000-0000-0000-0000-000000000001"
    echo -e "${GREEN}TRANSPORT:${RESET} TCP BRUT"
else
    echo -e "${RED}❌ ÉCHEC V2RAY${RESET}"
    sudo journalctl -u v2ray -n 20 --no-pager
fi
