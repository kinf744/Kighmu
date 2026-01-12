#!/bin/bash
# xray_installe.sh  Installation complète Xray + Trojan Go + X-UI + iptables, avec users.json

RED='\u001B[0;31m'
GREEN='\u001B[0;32m'
NC='\u001B[0m'

read -rp "Entrez votre nom de domaine (ex: monsite.com) : " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo -e "${RED}Erreur : nom de domaine non valide.${NC}"
  exit 1
fi

mkdir -p /etc/xray
if [[ ! -f /etc/xray/domain ]]; then
  echo "$DOMAIN" > /etc/xray/domain
fi

EMAIL="adrienkiaje@gmail.com"

apt update
apt install -y iptables iptables-persistent curl socat xz-utils wget apt-transport-https \
  gnupg gnupg2 gnupg1 dnsutils lsb-release cron bash-completion ntpdate chrony unzip jq ca-certificates libcap2-bin

# Configuration iptables initiale
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 8880 -j ACCEPT
iptables -A INPUT -p udp --dport 8880 -j ACCEPT
iptables -A INPUT -p tcp --dport 8443 -j ACCEPT
iptables -A INPUT -p tcp --dport 8444 -j ACCEPT
iptables -A INPUT -p udp --dport 8443 -j ACCEPT
iptables -A INPUT -p tcp --dport 2083 -j ACCEPT
iptables -A INPUT -p udp --dport 2083 -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
netfilter-persistent flush
netfilter-persistent save
echo "netfilter-persistent a appliqué les règles initiales."
iptables -S

# Installation Xray
latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep tag_name | cut -d '"' -f4 | sed 's/v//')
xraycore_link="https://github.com/XTLS/Xray-core/releases/download/v${latest_version}/xray-linux-64.zip"

mkdir -p /tmp/xray_install && cd /tmp/xray_install
curl -L -o xray.zip "$xraycore_link"
unzip -o xray.zip
mv -f xray /usr/local/bin/xray
chmod +x /usr/local/bin/xray
setcap 'cap_net_bind_service=+ep' /usr/local/bin/xray || true

mkdir -p /var/log/xray /etc/xray
touch /var/log/xray/access.log /var/log/xray/error.log
chown -R root:root /var/log/xray
chmod 644 /var/log/xray/access.log /var/log/xray/error.log

# Installation ACME et certificat
cd /root/
wget -q https://raw.githubusercontent.com/NevermoreSSH/hop/main/acme.sh
bash acme.sh --install
rm acme.sh
cd ~/.acme.sh || exit
bash acme.sh --register-account -m "$EMAIL"
bash acme.sh --issue --standalone -d "$DOMAIN" --force
bash acme.sh --installcert -d "$DOMAIN" --fullchainpath /etc/xray/xray.crt --keypath /etc/xray/xray.key

if [[ ! -f "/etc/xray/xray.crt" || ! -f "/etc/xray/xray.key" ]]; then
  echo -e "${RED}Erreur : certificats TLS non trouvés.${NC}"
  exit 1
fi

uuid=$(cat /proc/sys/kernel/random/uuid)

# users.json
cat > /etc/xray/users.json << EOF
{
  "vmess": [
    { "uuid": "$uuid", "limit": 5 }
  ],
  "vless": [
    { "uuid": "$uuid", "limit": 5 }
  ],
  "trojan": [
    { "uuid": "$uuid", "limit": 5 }
  ]
}
EOF

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
        "clients": [{"id": "$uuid", "alterId": 0}]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [{
            "certificateFile": "/etc/xray/xray.crt",
            "keyFile": "/etc/xray/xray.key"
          }],
          "minVersion": "1.2",
          "maxVersion": "1.3",
          "cipherSuites": "TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256"
        },
        "wsSettings": {
          "path": "/vmess-tls",
          "host": "$DOMAIN"
        }
      }
    },
    {
      "port": 8880,
      "protocol": "vmess",
      "settings": {
        "clients": [{"id": "$uuid", "alterId": 0}]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vmess-ntls",
          "host": "$DOMAIN"
        }
      }
    },
    {
      "port": 8443,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$uuid"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [{
            "certificateFile": "/etc/xray/xray.crt",
            "keyFile": "/etc/xray/xray.key"
          }],
          "minVersion": "1.2",
          "maxVersion": "1.3",
          "cipherSuites": "TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256"
        },
        "wsSettings": {
          "path": "/vless-tls",
          "host": "$DOMAIN"
        }
      }
    },
    {
      "port": 8880,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$uuid"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vless-ntls",
          "host": "$DOMAIN"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "port": 8443,
      "protocol": "trojan",
      "settings": {
        "clients": [{"password": "$uuid"}],
        "fallbacks": [{"dest": 8880}]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [{
            "certificateFile": "/etc/xray/xray.crt",
            "keyFile": "/etc/xray/xray.key"
          }],
          "alpn": ["http/1.1"],
          "minVersion": "1.2",
          "maxVersion": "1.3",
          "cipherSuites": "TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256"
        },
        "wsSettings": {
          "path": "/trojan-tls",
          "host": "$DOMAIN"
        }
      }
    },
    {
      "port": 8880,
      "protocol": "trojan",
      "settings": {
        "clients": [{"password": "$uuid"}]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/trojan-ntls",
          "host": "$DOMAIN"
        }
      }
    }
  ],
  "outbounds": [
    {"protocol": "freedom", "settings": {}},
    {"protocol": "blackhole", "settings": {}, "tag": "blocked"}
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8",
          "10.0.0.0/8",
          "100.64.0.0/10",
          "169.254.0.0/16",
          "172.16.0.0/12",
          "192.0.0.0/24",
          "192.0.2.0/24",
          "192.168.0.0/16",
          "198.18.0.0/15",
          "198.51.100.0/24",
          "203.0.113.0/24",
          "::1/128",
          "fc00::/7",
          "fe80::/10"
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

# systemd service Xray
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

# Installation Trojan-Go
latest_version_trj=$(curl -s https://api.github.com/repos/NevermoreSSH/addons/releases/latest | grep tag_name | cut -d '"' -f4 | sed 's/v//')
trojan_link="https://github.com/NevermoreSSH/addons/releases/download/v${latest_version_trj}/trojan-go-linux-amd64.zip"

mkdir -p /usr/bin/trojan-go /etc/trojan-go
cd $(mktemp -d)
curl -L -o trojan-go.zip "$trojan_link"
unzip -o trojan-go.zip
mv trojan-go /usr/local/bin/trojan-go
chmod +x /usr/local/bin/trojan-go
mkdir -p /var/log/trojan-go
touch /etc/trojan-go/akun.conf
touch /var/log/trojan-go/trojan-go.log

# config.json Trojan-Go
cat > /etc/trojan-go/config.json << EOF
{
  "run_type": "server",
  "local_addr": "0.0.0.0",
  "local_port": 2087,
  "remote_addr": "127.0.0.1",
  "remote_port": 89,
  "log_level": 1,
  "log_file": "/var/log/trojan-go/trojan-go.log",
  "password": ["$uuid"],
  "disable_http_check": true,
  "udp_timeout": 60,
  "ssl": {"verify": false,"verify_hostname": false,"cert": "/etc/xray/xray.crt","key": "/etc/xray/xray.key","key_password": "","sni": "$DOMAIN","alpn": ["http/1.1"]},
  "tcp": {"no_delay": true,"keep_alive": true,"prefer_ipv4": true},
  "mux": {"enabled": false,"concurrency": 8,"idle_timeout": 60},
  "websocket": {"enabled": true,"path": "/trojango","host": "$DOMAIN"}
}
EOF

# Redémarrage Trojan-Go
systemctl restart trojan-go

# ===============================
# Installation et configuration X-UI
# ===============================

echo -e "\n${GREEN}📥 Installation de X-UI via le script officiel...${NC}"

# Télécharger et installer la dernière version stable via le script officiel
bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)

# Copier les certificats TLS existants de Xray pour X-UI
mkdir -p /etc/x-ui/cert
cp /etc/xray/xray.crt /etc/x-ui/cert/x-ui.crt
cp /etc/xray/xray.key /etc/x-ui/cert/x-ui.key

# Configurer le panneau X-UI sur le port 8444 avec TLS (port libre)
echo -e "${GREEN}⚙️ Configuration du panneau X-UI sur le port 8444 avec TLS...${NC}"
x-ui setting -port 8444 -tls true -cert /etc/x-ui/cert/x-ui.crt -key /etc/x-ui/cert/x-ui.key

# Créer un service systemd robuste pour X-UI
cat > /etc/systemd/system/x-ui.service << 'EOF'
[Unit]
Description=X-UI Web Panel Service
After=network.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/x-ui
Restart=always
RestartSec=5
StartLimitIntervalSec=0
StartLimitBurst=0
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=x-ui
User=root

[Install]
WantedBy=multi-user.target
EOF

# Activer et démarrer le service
systemctl daemon-reload
systemctl enable x-ui --now

# Vérification du statut
systemctl status x-ui --no-pager
echo -e "${GREEN}✅ X-UI installé et démarré sur le port 8444 avec TLS.${NC}"

echo -e "${GREEN}✅ Installation complète terminée : Xray, Trojan-Go et X-UI sur 8443 avec TLS ACME.${NC}"
echo "Domaine : $DOMAIN"
echo "UUID : $uuid"
