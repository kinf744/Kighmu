#!/bin/bash
# Installation complète Xray + Trojan Go + UFW, nettoyage avant installation, services systemd robustes

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Arrêt des services utilisant les ports 80 et 8443...${NC}"
for port in 80 8443; do
    lsof -i tcp:$port -t | xargs -r kill -9
    lsof -i udp:$port -t | xargs -r kill -9
done

for srv in xray trojan-go nginx apache2; do
    systemctl stop $srv 2>/dev/null || true
    systemctl disable $srv 2>/dev/null || true
done

echo -e "${GREEN}Nettoyage des fichiers précédents...${NC}"
rm -rf /etc/xray /var/log/xray /usr/local/bin/xray /etc/trojan-go /var/log/trojan-go /usr/local/bin/trojan-go /tmp/.xray_domain \
/etc/systemd/system/xray.service /etc/systemd/system/trojan-go.service
systemctl daemon-reload

read -rp "Entrez votre nom de domaine (ex: monsite.com) : " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo -e "${RED}Erreur : nom de domaine non valide.${NC}"
  exit 1
fi
echo "$DOMAIN" > /tmp/.xray_domain

EMAIL="adrienkiaje@gmail.com"

apt update
apt install -y ufw iptables iptables-persistent curl socat xz-utils wget apt-transport-https \
  gnupg gnupg2 gnupg1 dnsutils lsb-release cron bash-completion ntpdate chrony unzip jq

ufw allow ssh
ufw allow 80/tcp
ufw allow 80/udp
ufw allow 8443/tcp
ufw allow 8443/udp

echo "y" | ufw enable
ufw status verbose
netfilter-persistent save

ntpdate pool.ntp.org
timedatectl set-ntp true
systemctl enable chronyd
systemctl restart chronyd
timedatectl set-timezone Asia/Kuala_Lumpur

echo "Vérification état chrony..."
chronyc sourcestats -v
chronyc tracking -v
date

latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.tag_name' | sed 's/v//')
xraycore_link="https://github.com/XTLS/Xray-core/releases/download/v${latest_version}/xray-linux-64.zip"

systemctl stop nginx apache2 2>/dev/null || true
sudo lsof -t -i tcp:80 -s tcp:listen | sudo xargs kill -9 2>/dev/null || true

echo "Téléchargement Xray depuis $xraycore_link..."
if ! curl -L "$xraycore_link" -o xray.zip; then
  echo -e "${RED}Erreur lors du téléchargement de Xray.${NC}"
  exit 1
fi
echo "Téléchargement terminé."

echo "Espace disque sur /tmp :"
df -h /tmp

space_avail=$(df /tmp --output=avail | tail -n1)
if (( space_avail < 102400 )); then
  echo -e "${RED}Espace disque insuffisant sur /tmp pour extraire Xray (moins de 100Mo).${NC}"
  exit 1
fi

echo "Extraction de l'archive Xray..."
if ! unzip -o xray.zip; then
  echo -e "${RED}Erreur lors de l'extraction de xray.zip.${NC}"
  exit 1
fi
echo "Extraction terminée."

echo "Installation du binaire Xray..."
if ! mv xray /usr/local/bin/xray; then
  echo -e "${RED}Erreur lors du déplacement du binaire Xray.${NC}"
  exit 1
fi
chmod +x /usr/local/bin/xray
setcap 'cap_net_bind_service=+ep' /usr/local/bin/xray
echo "Xray installé."

mkdir -p /var/log/xray /etc/xray
touch /var/log/xray/access.log /var/log/xray/error.log
chown -R root:root /var/log/xray
chmod 644 /var/log/xray/access.log /var/log/xray/error.log

if ! command -v ~/.acme.sh/acme.sh &> /dev/null; then
  echo "Installation de acme.sh pour SSL..."
  curl https://get.acme.sh | sh
  source ~/.bashrc
fi

systemctl stop xray

echo "Génération et installation certificats SSL..."
~/.acme.sh/acme.sh --register-account -m "$EMAIL"
~/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN" --force
~/.acme.sh/acme.sh --installcert -d "$DOMAIN" --fullchainpath /etc/xray/xray.crt --keypath /etc/xray/xray.key

systemctl start xray

if [[ ! -f "/etc/xray/xray.crt" || ! -f "/etc/xray/xray.key" ]]; then
  echo -e "${RED}Erreur certificats TLS introuvables.${NC}"
  exit 1
fi

uuid1=$(cat /proc/sys/kernel/random/uuid)
uuid2=$(cat /proc/sys/kernel/random/uuid)
uuid3=$(cat /proc/sys/kernel/random/uuid)
uuid4=$(cat /proc/sys/kernel/random/uuid)
uuid5=$(cat /proc/sys/kernel/random/uuid)
uuid6=$(cat /proc/sys/kernel/random/uuid)

cat > /etc/xray/users.json << EOF
{
  "vmess_tls": "$uuid1",
  "vmess_ntls": "$uuid2",
  "vless_tls": "$uuid3",
  "vless_ntls": "$uuid4",
  "trojan_pass": "$uuid5",
  "trojan_ntls_pass": "$uuid6"
}
EOF

cat > /etc/xray/config.json << EOF
{
  "log": {"access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log", "loglevel": "info"},
  "inbounds": [
    {
      "port": 8443,
      "protocol": "vmess",
      "settings": {"clients": [{"id": "$uuid1", "alterId": 0}]},
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {"certificates": [{"certificateFile": "/etc/xray/xray.crt", "keyFile": "/etc/xray/xray.key"}]},
        "wsSettings": {"path": "/vmess", "headers": {"Host": "$DOMAIN"}}
      }
    },
    {
      "port": 80,
      "protocol": "vmess",
      "settings": {"clients": [{"id": "$uuid2", "alterId": 0}]},
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {"path": "/vmess", "headers": {"Host": "$DOMAIN"}}
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "port": 8443,
      "protocol": "vless",
      "settings": {"clients": [{"id": "$uuid3"}], "decryption": "none"},
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {"certificates": [{"certificateFile": "/etc/xray/xray.crt", "keyFile": "/etc/xray/xray.key"}]},
        "wsSettings": {"path": "/vless", "headers": {"Host": "$DOMAIN"}}
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "port": 80,
      "protocol": "vless",
      "settings": {"clients": [{"id": "$uuid4"}], "decryption": "none"},
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {"path": "/vless", "headers": {"Host": "$DOMAIN"}}
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "port": 8443,
      "protocol": "trojan",
      "settings": {"clients": [{"password": "$uuid5"}]},
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {"certificates": [{"certificateFile": "/etc/xray/xray.crt","keyFile": "/etc/xray/xray.key"}]},
        "wsSettings": {"path": "/trojanws", "headers": {"Host": "$DOMAIN"}}
      }
    },
    {
      "port": 80,
      "protocol": "trojan",
      "settings": {"clients": [{"password": "$uuid6"}]},
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {"path": "/trojanws", "headers": {"Host": "$DOMAIN"}}
      }
    }
  ],
  "outbounds": [{"protocol": "freedom","settings": {}},{"protocol": "blackhole","settings": {}, "tag": "blocked"}],
  "routing": {
    "rules": [{
      "type": "field",
      "ip": [
        "0.0.0.0/8","10.0.0.0/8","100.64.0.0/10","169.254.0.0/16",
        "172.16.0.0/12","192.0.0.0/24","192.0.2.0/24","192.168.0.0/16",
        "198.18.0.0/15","198.51.100.0/24","203.0.113.0/24",
        "::1/128","fc00::/7","fe80::/10"
      ],
      "outboundTag": "blocked"
    }]
  },
  "policy": {"levels": {"0": {"statsUserDownlink": true,"statsUserUplink": true}}, "system": {"statsInboundUplink": true,"statsInboundDownlink": true}},
  "stats": {},
  "api": {"services": ["StatsService"], "tag": "api"}
}
EOF

cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service Mod By NevermoreSSH
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

if systemctl is-active --quiet xray; then
  echo -e "${GREEN}Xray démarré avec succès.${NC}"
else
  echo -e "${RED}Erreur : Xray ne démarre pas.${NC}"
  journalctl -u xray -n 20 --no-pager
  exit 1
fi

latest_version_trojan="0.10.6"
trojan_link="https://github.com/NevermoreSSH/addons/releases/download/$latest_version_trojan/trojan-go-linux-amd64.zip"

mkdir -p /usr/bin/trojan-go /etc/trojan-go
cd $(mktemp -d)
curl -sL "$trojan_link" -o trojan-go.zip
unzip -q trojan-go.zip && rm -f trojan-go.zip
mv trojan-go /usr/local/bin/trojan-go
chmod +x /usr/local/bin/trojan-go

mkdir -p /var/log/trojan-go
touch /etc/trojan-go/akun.conf
touch /var/log/trojan-go/trojan-go.log

cat > /etc/trojan-go/config.json << EOF
{
  "run_type": "server",
  "local_addr": "0.0.0.0",
  "local_port": 8443,
  "remote_addr": "",
  "remote_port": 0,
  "log_level": 1,
  "log_file": "/var/log/trojan-go/trojan-go.log",
  "password": ["$uuid5"],
  "disable_http_check": true,
  "udp_timeout": 60,
  "ssl": {
    "verify": false,
    "verify_hostname": false,
    "cert": "/etc/xray/xray.crt",
    "key": "/etc/xray/xray.key",
    "key_password": "",
    "cipher": "",
    "curves": "",
    "prefer_server_cipher": false,
    "sni": "$DOMAIN",
    "alpn": ["http/1.1"],
    "session_ticket": true,
    "reuse_session": true,
    "plain_http_response": ""
  },
  "tcp": {"no_delay": true,"keep_alive": true,"prefer_ipv4": true},
  "mux": {"enabled": false,"concurrency": 8,"idle_timeout": 60},
  "websocket": {"enabled": true,"path": "/trojanws","host": "$DOMAIN"},
  "api": {"enabled": false,"api_addr": "","api_port": 0,"ssl": {"enabled": false,"key": "","cert": "","verify_client": false,"client_cert": []}}
}
EOF

cat > /etc/systemd/system/trojan-go.service << EOF
[Unit]
Description=Trojan Go Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/trojan-go -config /etc/trojan-go/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable trojan-go
systemctl restart trojan-go

if systemctl is-active --quiet trojan-go; then
  echo -e "${GREEN}Trojan Go démarré avec succès.${NC}"
else
  echo -e "${RED}Erreur : Trojan Go ne démarre pas.${NC}"
  journalctl -u trojan-go -n 20 --no-pager
  exit 1
fi

(crontab -l 2>/dev/null; echo "@reboot /bin/systemctl start xray") | crontab -
(crontab -l 2>/dev/null; echo "@reboot /bin/systemctl start trojan-go") | crontab -

ufw allow ssh
ufw allow 80/tcp
ufw allow 80/udp
ufw allow 8443/tcp
ufw allow 8443/udp
echo "y" | ufw enable
ufw status verbose

echo -e "${GREEN}Installation complète terminée.${NC}"
echo "Domaine : $DOMAIN"
echo "UUID VMess TLS : $uuid1"
echo "UUID VMess Non-TLS : $uuid2"
echo "UUID VLESS TLS : $uuid3"
echo "UUID VLESS Non-TLS : $uuid4"
echo "Mot de passe Trojan WS TLS : $uuid5"
echo "Mot de passe Trojan WS Non-TLS : $uuid6"
