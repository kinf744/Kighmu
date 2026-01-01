#!/bin/bash
# xray_installe_caddy.sh — Installation Xray + Caddy (TLS + reverse-proxy)

RED='\u001B[0;31m'
GREEN='\u001B[0;32m'
NC='\u001B[0m'

# -----------------------------
# DEMANDE DU DOMAINE
# -----------------------------
read -rp "Entrez votre nom de domaine (ex: monsite.com) : " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo -e "${RED}Erreur : nom de domaine non valide.${NC}"
  exit 1
fi
echo "$DOMAIN" > /tmp/.xray_domain

# -----------------------------
# INSTALLATION DES DÉPENDANCES
# -----------------------------
apt update
apt install -y iptables iptables-persistent curl socat xz-utils wget apt-transport-https \
gnupg gnupg2 gnupg1 dnsutils lsb-release cron bash-completion ntpdate chrony unzip jq ca-certificates libcap2-bin

# Autoriser ports essentiels
iptables -A INPUT -p tcp --dport 22 -j ACCEPT  # SSH
iptables -A INPUT -p tcp --dport 8880 -j ACCEPT  # Non-TLS
iptables -A INPUT -p udp --dport 8880 -j ACCEPT
iptables -A INPUT -p tcp --dport 8443 -j ACCEPT  # WS TLS
iptables -A INPUT -p udp --dport 8443 -j ACCEPT
iptables -A INPUT -p tcp --dport 10011:10013 -j ACCEPT  # TCP TLS Xray
iptables -A INPUT -p tcp --dport 10021:10022 -j ACCEPT  # gRPC TLS Xray

netfilter-persistent flush
netfilter-persistent save

# -----------------------------
# INSTALLATION XRAY
# -----------------------------
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

# -----------------------------
# GÉNÉRATION DES UUID
# -----------------------------
uuid1=$(cat /proc/sys/kernel/random/uuid)  # VMess TLS
uuid2=$(cat /proc/sys/kernel/random/uuid)  # VMess Non-TLS
uuid3=$(cat /proc/sys/kernel/random/uuid)  # VLESS TLS
uuid4=$(cat /proc/sys/kernel/random/uuid)  # VLESS Non-TLS
uuid5=$(cat /proc/sys/kernel/random/uuid)  # Trojan TLS
uuid6=$(cat /proc/sys/kernel/random/uuid)  # Trojan Non-TLS

# -----------------------------
# USERS.JSON
# -----------------------------
cat > /etc/xray/users.json << EOF
{
  "vmess_tls": [{"uuid": "$uuid1", "limit":5}],
  "vmess_ntls": [{"uuid": "$uuid2", "limit":5}],
  "vless_tls": [{"uuid": "$uuid3", "limit":5}],
  "vless_ntls": [{"uuid": "$uuid4", "limit":5}],
  "trojan_tls": [{"uuid": "$uuid5", "limit":5}],
  "trojan_ntls": [{"uuid": "$uuid6", "limit":5}]
}
EOF

# -----------------------------
# CONFIG XRAY
# -----------------------------
cat > /etc/xray/config.json << EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "info"
  },
  "inbounds": [
    {
      "port": 10001,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {"id": "$uuid1", "alterId": 0}
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vmess-tls"
        }
      }
    },
    {
      "port": 10002,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {"id": "$uuid2", "alterId": 0}
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vmess-ntls"
        }
      }
    },
    {
      "port": 10003,
      "protocol": "vless",
      "settings": {
        "clients": [
          {"id": "$uuid3"}
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vless-tls"
        }
      }
    },
    {
      "port": 10004,
      "protocol": "vless",
      "settings": {
        "clients": [
          {"id": "$uuid4"}
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vless-ntls"
        }
      }
    },
    {
      "port": 10005,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {"password": "$uuid5"}
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/trojan-tls"
        }
      }
    },
    {
      "port": 10006,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {"password": "$uuid6"}
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/trojan-ntls"
        }
      }
    },
    {
      "port": 10011,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {"id": "$uuid1", "alterId": 0}
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificateFile": "/etc/xray/xray.crt",
          "keyFile": "/etc/xray/xray.key"
        }
      }
    },
    {
      "port": 10012,
      "protocol": "vless",
      "settings": {
        "clients": [
          {"id": "$uuid3"}
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificateFile": "/etc/xray/xray.crt",
          "keyFile": "/etc/xray/xray.key"
        }
      }
    },
    {
      "port": 10013,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {"password": "$uuid5"}
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificateFile": "/etc/xray/xray.crt",
          "keyFile": "/etc/xray/xray.key"
        }
      }
    },
    {
      "port": 10021,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {"id": "$uuid1", "alterId": 0}
        ]
      },
      "streamSettings": {
        "network": "grpc",
        "security": "tls",
        "tlsSettings": {
          "certificateFile": "/etc/xray/xray.crt",
          "keyFile": "/etc/xray/xray.key"
        },
        "grpcSettings": {
          "serviceName": "vmess-grpc"
        }
      }
    },
    {
      "port": 10022,
      "protocol": "vless",
      "settings": {
        "clients": [
          {"id": "$uuid3"}
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "security": "tls",
        "tlsSettings": {
          "certificateFile": "/etc/xray/xray.crt",
          "keyFile": "/etc/xray/xray.key"
        },
        "grpcSettings": {
          "serviceName": "vless-grpc"
        }
      }
    },
    {
      "port": 10023,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {"password": "$uuid5"}
        ]
      },
      "streamSettings": {
        "network": "grpc",
        "security": "tls",
        "tlsSettings": {
          "certificateFile": "/etc/xray/xray.crt",
          "keyFile": "/etc/xray/xray.key"
        },
        "grpcSettings": {
          "serviceName": "trojan-grpc"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
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
  }
}
EOF

# -----------------------------
# SYSTEMD XRAY
# -----------------------------
cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray -config /etc/xray/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# -----------------------------
# INSTALLATION CADDY
# -----------------------------
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | apt-key add -
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install -y caddy

# -----------------------------
# CONFIGURATION CADDYFILE (WS TLS)
# -----------------------------
cat > /etc/caddy/Caddyfile << EOF
$DOMAIN {
    encode gzip
    reverse_proxy /vmess-tls  localhost:10001
    reverse_proxy /vmess-ntls localhost:10002
    reverse_proxy /vless-tls  localhost:10003
    reverse_proxy /vless-ntls localhost:10004
    reverse_proxy /trojan-tls localhost:10005
    reverse_proxy /trojan-ntls localhost:10006
}
EOF

systemctl enable caddy
systemctl restart caddy

# -----------------------------
# RÉSULTATS
# -----------------------------
echo -e "${GREEN}Installation terminée avec succès.${NC}"
echo "Domaine : $DOMAIN"
echo "UUID VMess TLS : $uuid1"
echo "UUID VMess Non-TLS : $uuid2"
echo "UUID VLESS TLS : $uuid3"
echo "UUID VLESS Non-TLS : $uuid4"
echo "Mot de passe Trojan TLS : $uuid5"
echo "Mot de passe Trojan Non-TLS : $uuid6"
