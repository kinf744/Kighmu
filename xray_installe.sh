#!/bin/bash
# Installation complète Xray + Trojan Go + UFW adaptable Ubuntu 18.04-24.04, Debian 11-12

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Détection de la distribution et version...${NC}"
. /etc/os-release
DISTRO_ID="$ID"
DISTRO_VER="$VERSION_ID"

echo -e "${GREEN}Distribution détectée : $DISTRO_ID $DISTRO_VER${NC}"

# Nettoyage précédent
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

# Demander domaine
read -rp "Entrez votre nom de domaine (ex: monsite.com) : " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo -e "${RED}Erreur : nom de domaine non valide.${NC}"
  exit 1
fi
echo "$DOMAIN" > /tmp/.xray_domain

EMAIL="adrienkiaje@gmail.com"

echo -e "${GREEN}Installation des dépendances selon distribution...${NC}"

COMMON_PKGS=(curl wget unzip jq lsb-release ufw iptables iptables-persistent)

# Gestion paquets temps selon distro & version
if [[ "$DISTRO_ID" == "ubuntu" ]]; then
  if (( $(echo "$DISTRO_VER >= 20.04" | bc -l) )); then
    COMMON_PKGS+=(systemd-timesyncd)
    TIMESYNC_SERVICE="systemd-timesyncd"
  else
    COMMON_PKGS+=(ntp)
    TIMESYNC_SERVICE="ntp"
  fi
elif [[ "$DISTRO_ID" == "debian" ]]; then
  if (( $(echo "$DISTRO_VER >= 11" | bc -l) )); then
    COMMON_PKGS+=(systemd-timesyncd)
    TIMESYNC_SERVICE="systemd-timesyncd"
  else
    COMMON_PKGS+=(ntp)
    TIMESYNC_SERVICE="ntp"
  fi
else
  echo -e "${RED}Distribution non prise en charge.${NC}"
  exit 1
fi

apt update
apt install -y "${COMMON_PKGS[@]}"

echo -e "${GREEN}Configuration et activation du service de synchronisation temporelle...${NC}"
systemctl enable "$TIMESYNC_SERVICE"
systemctl restart "$TIMESYNC_SERVICE"

# Synchronisation initiale directe
if [[ "$TIMESYNC_SERVICE" == "ntp" ]]; then
  ntpdate pool.ntp.org || true
fi

timedatectl set-timezone Asia/Kuala_Lumpur
date

# Configuration UFW
echo -e "${GREEN}Configuration UFW...${NC}"
ufw allow ssh
ufw allow 80/tcp
ufw allow 80/udp
ufw allow 8443/tcp
ufw allow 8443/udp
echo "y" | ufw enable
ufw status verbose
netfilter-persistent save

# Installation Xray
echo -e "${GREEN}Téléchargement et installation Xray (version latest)...${NC}"
latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.tag_name' | sed 's/v//')
xraycore_link="https://github.com/XTLS/Xray-core/releases/download/v${latest_version}/xray-linux-64.zip"

mkdir -p /usr/local/bin
cd $(mktemp -d)
curl -sL "$xraycore_link" -o xray.zip
unzip -q xray.zip && rm -f xray.zip
mv xray /usr/local/bin/xray
chmod +x /usr/local/bin/xray
setcap 'cap_net_bind_service=+ep' /usr/local/bin/xray

mkdir -p /var/log/xray /etc/xray
touch /var/log/xray/access.log /var/log/xray/error.log
chown -R root:root /var/log/xray
chmod 644 /var/log/xray/access.log /var/log/xray/error.log

# Installation acme.sh
if ! command -v ~/.acme.sh/acme.sh &> /dev/null; then
  curl https://get.acme.sh | sh
  source ~/.bashrc
fi

# Libérer port 80 avant génération certificat
systemctl stop xray || true

~/.acme.sh/acme.sh --register-account -m "$EMAIL"
~/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN" --force
~/.acme.sh/acme.sh --installcert -d "$DOMAIN" --fullchainpath /etc/xray/xray.crt --keypath /etc/xray/xray.key

if [[ ! -f "/etc/xray/xray.crt" || ! -f "/etc/xray/xray.key" ]]; then
  echo -e "${RED}Erreur : certificats TLS non trouvés.${NC}"
  exit 1
fi

# Génération UUID
uuid1=$(cat /proc/sys/kernel/random/uuid)
uuid2=$(cat /proc/sys/kernel/random/uuid)
uuid3=$(cat /proc/sys/kernel/random/uuid)
uuid4=$(cat /proc/sys/kernel/random/uuid)
uuid5=$(cat /proc/sys/kernel/random/uuid)
uuid6=$(cat /proc/sys/kernel/random/uuid)

# users.json
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

# Configuration Xray corrigée
cat > /etc/xray/config.json << EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "info"
  },
  "inbounds": [
    {
      "port": 8443,
      "protocol": "vmess",
      "settings": {
        "clients": [{"id": "$uuid1", "alterId": 0}]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/xray/xray.crt",
              "keyFile": "/etc/xray/xray.key"
            }
          ]
        },
        "wsSettings": {
          "path": "/vmess",
          "host": "$DOMAIN"
        }
      }
    },
    {
      "port": 80,
      "protocol": "vmess",
      "settings": {
        "clients": [{"id": "$uuid2", "alterId": 0}]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vmess",
          "host": "$DOMAIN"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    # [... autres inbounds identiques avec host hors headers ...]
    {
      "port": 8443,
      "protocol": "trojan",
      "settings": {
        "clients": [{"password": "$uuid5"}]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/xray/xray.crt",
              "keyFile": "/etc/xray/xray.key"
            }
          ]
        },
        "wsSettings": {
          "path": "/trojanws",
          "host": "$DOMAIN"
        }
      }
    },
    {
      "port": 80,
      "protocol": "trojan",
      "settings": {
        "clients": [{"password": "$uuid6"}]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/trojanws",
          "host": "$DOMAIN"
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": {} },
    { "protocol": "blackhole", "settings": {}, "tag": "blocked" }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8","10.0.0.0/8","100.64.0.0/10","169.254.0.0/16",
          "172.16.0.0/12","192.0.0.0/24","192.0.2.0/24","192.168.0.0/16",
          "198.18.0.0/15","198.51.100.0/24","203.0.113.0/24","::1/128",
          "fc00::/7","fe80::/10"
        ],
        "outboundTag": "blocked"
      }
    ]
  },
  "policy": {
    "levels": {
      "0": {
        "statsUserDownlink": true,
        "statsUserUplink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true
    }
  },
  "stats": {},
  "api": {
    "services": ["StatsService"],
    "tag": "api"
  }
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
RestartSec=5s

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

# Installation Trojan Go - inchangé, mais chemins et service systemd corrects

latest_version="0.10.6"
trojan_link="https://github.com/NevermoreSSH/addons/releases/download/$latest_version/trojan-go-linux-amd64.zip"

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
  "tcp": {
    "no_delay": true,
    "keep_alive": true,
    "prefer_ipv4": true
  },
  "mux": {
    "enabled": false,
    "concurrency": 8,
    "idle_timeout": 60
  },
  "websocket": {
    "enabled": true,
    "path": "/trojanws",
    "host": "$DOMAIN"
  },
  "api": {
    "enabled": false,
    "api_addr": "",
    "api_port": 0,
    "ssl": {
      "enabled": false,
      "key": "",
      "cert": "",
      "verify_client": false,
      "client_cert": []
    }
  }
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

echo -e "${GREEN}Installation complète terminée.${NC}"
echo "Domaine : $DOMAIN"
echo "UUID VMess TLS : $uuid1"
echo "UUID VMess Non-TLS : $uuid2"
echo "UUID VLESS TLS : $uuid3"
echo "UUID VLESS Non-TLS : $uuid4"
echo "Mot de passe Trojan WS TLS : $uuid5"
echo "Mot de passe Trojan WS Non-TLS : $uuid6"
