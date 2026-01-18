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
netfilter-persistent flush
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 8880 -j ACCEPT
iptables -A INPUT -p udp --dport 8880 -j ACCEPT
iptables -A INPUT -p tcp --dport 8443 -j ACCEPT
iptables -A INPUT -p udp --dport 8443 -j ACCEPT
iptables -A INPUT -p tcp --dport 2083 -j ACCEPT
iptables -A INPUT -p udp --dport 2083 -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
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
    {
      "id": "$uuid",
      "alterId": 0,
      "limit": 5
    }
  ],
  "vless": [
    {
      "id": "$uuid",
      "limit": 5
    }
  ],
  "trojan": [
    {
      "password": "$uuid",
      "limit": 5
    }
  ],
  "shadowsocks": [
    {
      "method": "aes-128-gcm",
      "password": "$uuid",
      "limit": 5
    }
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
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "tag": "api"
    },

    {
      "listen": "127.0.0.1",
      "port": 14016,
      "protocol": "vless",
      "settings": {
        "decryption": "none",
        "clients": [
          { "id": "$uuid" }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vless"
        }
      }
    },

    {
      "listen": "127.0.0.1",
      "port": 23456,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess"
        }
      }
    },

    {
      "listen": "127.0.0.1",
      "port": 25432,
      "protocol": "trojan",
      "settings": {
        "clients": [
          { "password": "$uuid" }
        ],
        "udp": true
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/trojan-ws"
        }
      }
    },

    {
      "listen": "127.0.0.1",
      "port": 30300,
      "protocol": "shadowsocks",
      "settings": {
        "clients": [
          {
            "method": "aes-128-gcm",
            "password": "$uuid"
          }
        ],
        "network": "tcp,udp"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/ss-ws"
        }
      }
    },

    {
      "listen": "127.0.0.1",
      "port": 24456,
      "protocol": "vless",
      "settings": {
        "decryption": "none",
        "clients": [
          { "id": "$uuid" }
        ]
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "vless-grpc"
        }
      }
    },

    {
      "listen": "127.0.0.1",
      "port": 31234,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "vmess-grpc"
        }
      }
    },

    {
      "listen": "127.0.0.1",
      "port": 33456,
      "protocol": "trojan",
      "settings": {
        "clients": [
          { "password": "$uuid" }
        ]
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "trojan-grpc"
        }
      }
    },

    {
      "listen": "127.0.0.1",
      "port": 30310,
      "protocol": "shadowsocks",
      "settings": {
        "clients": [
          {
            "method": "aes-128-gcm",
            "password": "$uuid"
          }
        ],
        "network": "tcp,udp"
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "ss-grpc"
        }
      }
    }
  ],

  "outbounds": [
    { "protocol": "freedom" },
    { "protocol": "blackhole", "tag": "blocked" }
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
          "192.168.0.0/16",
          "::1/128",
          "fc00::/7",
          "fe80::/10"
        ],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "inboundTag": ["api"],
        "outboundTag": "api"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "blocked"
      }
    ]
  },

  "stats": {},

  "api": {
    "services": ["StatsService"],
    "tag": "api"
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
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
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

cat > /etc/nginx/conf.d/xray.conf << EOF
server {
    listen 81;
    listen [::]:81;
    server_name $DOMAIN *.$DOMAIN;

    # Redirige tout vers HTTPS
    return 301 https://$host$request_uri;
}

# ----------------------------
# TLS WS / gRPC (port 8443)
# ----------------------------
server {
    listen 8443 ssl http2;
    listen [::]:8443 ssl http2;
    server_name $DOMAIN *.$DOMAIN;

    root /home/vps/public_html;

    ssl_certificate /etc/xray/xray.crt;
    ssl_certificate_key /etc/xray/xray.key;
    ssl_ciphers EECDH+CHACHA20:EECDH+AES128:EECDH+AES256:!MD5;
    ssl_protocols TLSv1.2 TLSv1.3;

    # ----------------------------
    # WebSocket TLS
    # ----------------------------
    location = /vless {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:14016;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }

    location = /vmess {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:23456;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }

    location = /trojan-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:25432;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }

    location = /ss-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:30300;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }

    # ----------------------------
    # gRPC TLS
    # ----------------------------
    location ^~ /vless-grpc {
        grpc_pass grpc://127.0.0.1:24456;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        grpc_set_header Host $http_host;
    }

    location ^~ /vmess-grpc {
        grpc_pass grpc://127.0.0.1:31234;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        grpc_set_header Host $http_host;
    }

    location ^~ /trojan-grpc {
        grpc_pass grpc://127.0.0.1:33456;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        grpc_set_header Host $http_host;
    }

    location ^~ /ss-grpc {
        grpc_pass grpc://127.0.0.1:30310;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        grpc_set_header Host $http_host;
    }

    # ----------------------------
    # Fallback site
    # ----------------------------
    location / {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:700; # backend web
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }
}

# ----------------------------
# WS NTLS (port 8880) – non TLS
# ----------------------------
server {
    listen 8880;
    listen [::]:8880;
    server_name $DOMAIN *.$DOMAIN;

    root /home/vps/public_html;

    # ----------------------------
    # WebSocket NTLS
    # ----------------------------
    location = /vless-ntls {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:14016;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }

    location = /vmess-ntls {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:23456;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }

    location = /trojan-ntls {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:25432;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }

    location = /ss-ntls {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:30300;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }

    # ----------------------------
    # Fallback site NTLS
    # ----------------------------
    location / {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:700; # backend web
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    }
}
EOF

systemctl daemon-reload
systemctl enable xray nginx

# Redémarrage du service
if systemctl restart xray nginx; then
    # Vérification immédiate
    sleep 2
    if systemctl is-active --quiet xray; then
        echo -e "${GREEN}✅ Xray démarré avec succès.${NC}"
    else
        echo -e "${RED}❌ Xray n'a pas démarré.${NC}"
        echo "Derniers logs :"
        journalctl -u xray -n 20 --no-pager
        exit 1
    fi
else
    echo -e "${RED}❌ Échec du redémarrage du service Xray.${NC}"
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
# systemctl restart trojan-go

echo -e "${GREEN}✅ Installation complète terminée : Xray, Trojan-Go et sur 8443 avec TLS ACME.${NC}"
echo "Domaine : $DOMAIN"
echo "UUID : $uuid"
