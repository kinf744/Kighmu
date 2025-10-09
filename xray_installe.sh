#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

read -rp "Entrez votre nom de domaine (ex: monsite.com) : " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo -e "${RED}Nom de domaine requis.${NC}"
  exit 1
fi
EMAIL="adrienkiaje@gmail.com"

apt update && apt install -y curl unzip jq openssl chrony ntpdate ufw

# Firewall config
ufw allow ssh
ufw allow 80/tcp
ufw allow 80/udp
ufw allow 8443/tcp
ufw allow 8443/udp
echo "y" | ufw enable
ufw status verbose

ntpdate pool.ntp.org
timedatectl set-ntp true
systemctl enable chrony
systemctl restart chrony
timedatectl set-timezone Asia/Kuala_Lumpur

echo "Attente synchronisation chrony (max 30s)..."
for i in {1..6}; do
  leap_status=$(chronyc tracking | grep "Leap status" | awk '{print $3}')
  if [ "$leap_status" == "Normal" ]; then
    echo "Chrony synchronisé."
    break
  fi
  echo "Synchronisation non terminée, attente 5 secondes... ($i/6)"
  sleep 5
done

cert_issued=0
leap_status=$(chronyc tracking | grep "Leap status" | awk '{print $3}')
if [ "$leap_status" != "Normal" ]; then
  echo -e "${RED}Chrony non synchronisé, génération certificat auto-signé.${NC}"
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/xray/xray.key -out /etc/xray/xray.crt -subj "/CN=$DOMAIN"
else
  echo -e "${GREEN}Chrony synchronisé, génération certificat ACME.${NC}"
  curl https://get.acme.sh | sh
  source ~/.bashrc
  ~/.acme.sh/acme.sh --register-account -m "$EMAIL"
  ~/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN" --force
  ~/.acme.sh/acme.sh --installcert -d "$DOMAIN" --fullchainpath /etc/xray/xray.crt --keypath /etc/xray/xray.key
  cert_issued=1
fi

latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.tag_name' | sed 's/v//')
xraycore_link="https://github.com/XTLS/Xray-core/releases/download/v${latest_version}/xray-linux-64.zip"

tmpdir=$(mktemp -d)
cd "$tmpdir" || exit

curl -L "$xraycore_link" -o xray.zip
unzip -q xray.zip
mv xray /usr/local/bin/xray
chmod +x /usr/local/bin/xray
setcap 'cap_net_bind_service=+ep' /usr/local/bin/xray

mkdir -p /etc/xray /var/log/xray
chown -R root:root /var/log/xray
touch /var/log/xray/access.log /var/log/xray/error.log

uuid1=$(cat /proc/sys/kernel/random/uuid)
uuid2=$(cat /proc/sys/kernel/random/uuid)
uuid3=$(cat /proc/sys/kernel/random/uuid)
uuid4=$(cat /proc/sys/kernel/random/uuid)
uuid5=$(cat /proc/sys/kernel/random/uuid)
uuid6=$(cat /proc/sys/kernel/random/uuid)

cat > /etc/xray/config.json << EOF
{
  "log": {"access": "/var/log/xray/access.log","error":"/var/log/xray/error.log","loglevel":"info"},
  "inbounds": [
    {
      "port": 8443,
      "protocol": "vmess",
      "settings": {"clients":[{"id":"$uuid1","alterId":0}]},
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {"certificates":[{"certificateFile":"/etc/xray/xray.crt","keyFile":"/etc/xray/xray.key"}]},
        "wsSettings": {"path":"/vmess","headers":{"Host":"$DOMAIN"}}
      }
    },
    {
      "port": 80,
      "protocol": "vmess",
      "settings": {"clients":[{"id":"$uuid2","alterId":0}]},
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {"path":"/vmess","headers":{"Host":"$DOMAIN"}}
      },
      "sniffing": {"enabled":true,"destOverride":["http","tls"]}
    },
    {
      "port": 8443,
      "protocol": "vless",
      "settings": {"clients":[{"id":"$uuid3"}],"decryption":"none"},
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {"certificates":[{"certificateFile":"/etc/xray/xray.crt","keyFile":"/etc/xray/xray.key"}]},
        "wsSettings": {"path":"/vless","headers":{"Host":"$DOMAIN"}}
      },
      "sniffing": {"enabled":true,"destOverride":["http","tls"]}
    },
    {
      "port": 80,
      "protocol": "vless",
      "settings": {"clients":[{"id":"$uuid4"}],"decryption":"none"},
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {"path":"/vless","headers":{"Host":"$DOMAIN"}}
      },
      "sniffing": {"enabled":true,"destOverride":["http","tls"]}
    },
    {
      "port": 2083,
      "protocol": "trojan",
      "settings": {"clients":[{"password":"$uuid5"}]},
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {"certificates":[{"certificateFile":"/etc/xray/xray.crt","keyFile":"/etc/xray/xray.key"}]},
        "wsSettings": {"path":"/trojanws","headers":{"Host":"$DOMAIN"}}
      }
    },
    {
      "port": 80,
      "protocol": "trojan",
      "settings": {"clients":[{"password":"$uuid6"}]},
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {"path":"/trojanws","headers":{"Host":"$DOMAIN"}}
      }
    }
  ],
  "outbounds": [{"protocol":"freedom","settings":{}},{"protocol":"blackhole","settings":{},"tag":"blocked"}],
  "routing": {
    "rules": [{"type":"field","ip":["0.0.0.0/8","10.0.0.0/8","100.64.0.0/10","169.254.0.0/16","172.16.0.0/12","192.0.0.0/24","192.0.2.0/24","192.168.0.0/16","198.18.0.0/15","198.51.100.0/24","203.0.113.0/24","::1/128","fc00::/7","fe80::/10"],"outboundTag":"blocked"}]
  },
  "policy": {"levels":{"0":{"statsUserDownlink":true,"statsUserUplink":true}},"system":{"statsInboundUplink":true,"statsInboundDownlink":true}},
  "stats": {},
  "api": {"services":["StatsService"],"tag":"api"}
}
EOF

cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/xray -config /etc/xray/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

if systemctl is-active --quiet xray; then
  echo -e "${GREEN}Xray démarré avec succès!${NC}"
else
  echo -e "${RED}Erreur au démarrage de Xray.${NC}"
  journalctl -n 20 -u xray --no-pager
fi

echo -e "${GREEN}Installation terminée.${NC}"
echo "Domain: $DOMAIN"
echo "UUID VMess TLS: $uuid1"
echo "UUID VMess Non-TLS: $uuid2"
echo "UUID VLESS TLS: $uuid3"
echo "UUID VLESS Non-TLS: $uuid4"
echo "Trojan WS TLS password: $uuid5"
echo "Trojan WS Non-TLS password: $uuid6"
