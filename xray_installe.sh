#!/bin/bash
# xray_installe_fixed.sh — Installation complète Xray + Trojan Go + Nginx
# Corrections : email valide pour stats, users.json avec expire, routing API complet
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

read -rp "Entrez votre nom de domaine (ex: monsite.com) : " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo -e "${RED}Erreur : nom de domaine non valide.${NC}"
  exit 1
fi

mkdir -p /etc/xray
echo "$DOMAIN" > /etc/xray/domain

EMAIL="adrienkiaje@gmail.com"

# ============================================================================
# Dépendances
# ============================================================================
apt update
apt install -y iptables nginx iptables-persistent curl socat xz-utils wget \
  apt-transport-https gnupg gnupg2 gnupg1 dnsutils lsb-release cron \
  bash-completion ntpdate chrony unzip jq ca-certificates libcap2-bin

# ============================================================================
# iptables
# ============================================================================
if ! iptables -C INPUT -p tcp --dport 81 -j ACCEPT 2>/dev/null; then
  iptables -I INPUT -p tcp --dport 81 -j ACCEPT
fi
iptables -A INPUT  -p tcp --dport 22   -j ACCEPT
iptables -A INPUT  -p tcp --dport 8880 -j ACCEPT
iptables -A INPUT  -p udp --dport 8880 -j ACCEPT
iptables -A INPUT  -p tcp --dport 8443 -j ACCEPT
iptables -A INPUT  -p udp --dport 8443 -j ACCEPT
iptables -A INPUT  -p tcp --dport 2083 -j ACCEPT
iptables -A INPUT  -p udp --dport 2083 -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
netfilter-persistent save
echo "✅ iptables configuré."

# ============================================================================
# Installation Xray
# ============================================================================
latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest \
  | grep tag_name | cut -d'"' -f4 | sed 's/v//')
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

# ============================================================================
# Certificat TLS (ACME)
# ============================================================================
ACME_CERT="/etc/xray/xray.crt"
ACME_KEY="/etc/xray/xray.key"
GENERATE_TLS=false
SSHWS_STOPPED=false

if [[ -f "$ACME_CERT" && -f "$ACME_KEY" ]]; then
  if openssl x509 -checkend 86400 -noout -in "$ACME_CERT" > /dev/null; then
    echo -e "${GREEN}✅ Certificat TLS valide trouvé. Réutilisation.${NC}"
  else
    echo "🔑 Certificat expiré — régénération..."
    GENERATE_TLS=true
  fi
else
  echo "🔑 Aucun certificat trouvé — génération..."
  GENERATE_TLS=true
fi

if [[ "$GENERATE_TLS" == true ]]; then
  if systemctl list-units --full -all | grep -q sshws; then
    systemctl stop sshws && SSHWS_STOPPED=true
  fi

  if [ ! -f ~/.acme.sh/acme.sh ]; then
    cd /root/
    wget -q https://raw.githubusercontent.com/NevermoreSSH/hop/main/acme.sh
    bash acme.sh --install && rm acme.sh
  fi

  cd ~/.acme.sh
  bash acme.sh --register-account -m "$EMAIL" || true

  if ! bash acme.sh --list | grep -q "$DOMAIN"; then
    bash acme.sh --issue --standalone -d "$DOMAIN"
  fi

  bash acme.sh --installcert -d "$DOMAIN" \
    --fullchainpath "$ACME_CERT" \
    --keypath "$ACME_KEY"

  if [[ ! -f "$ACME_CERT" || ! -f "$ACME_KEY" ]]; then
    echo -e "${RED}❌ Certificats TLS non générés.${NC}"
    [[ "$SSHWS_STOPPED" == true ]] && systemctl start sshws
    exit 1
  fi

  echo -e "${GREEN}✅ Certificat TLS généré.${NC}"
  [[ "$SSHWS_STOPPED" == true ]] && systemctl start sshws
fi

# ============================================================================
# UUID initial (conservé pour Trojan-Go uniquement)
# ============================================================================
uuid=$(cat /proc/sys/kernel/random/uuid)

# ============================================================================
# users.json — listes vides au départ
# ============================================================================
cat > /etc/xray/users.json << EOF
{
  "vmess": [],
  "vless": [],
  "trojan": [],
  "shadowsocks": []
}
EOF

# ============================================================================
# config.json Xray
# ============================================================================
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
      "settings": { "address": "127.0.0.1" },
      "tag": "api"
    },

    {
      "listen": "127.0.0.1",
      "port": 14016,
      "protocol": "vless",
      "settings": {
        "decryption": "none",
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vless" }
      }
    },

    {
      "listen": "127.0.0.1",
      "port": 23456,
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vmess" }
      }
    },

    {
      "listen": "127.0.0.1",
      "port": 25432,
      "protocol": "trojan",
      "settings": {
        "clients": [],
        "udp": true
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/trojan-ws" }
      }
    },

    {
      "listen": "127.0.0.1",
      "port": 30300,
      "protocol": "shadowsocks",
      "settings": {
        "clients": [],
        "network": "tcp,udp"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/ss-ws" }
      }
    },

    {
      "listen": "127.0.0.1",
      "port": 24456,
      "protocol": "vless",
      "settings": {
        "decryption": "none",
        "clients": []
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": { "serviceName": "vless-grpc" }
      }
    },

    {
      "listen": "127.0.0.1",
      "port": 31234,
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": { "serviceName": "vmess-grpc" }
      }
    },

    {
      "listen": "127.0.0.1",
      "port": 33456,
      "protocol": "trojan",
      "settings": {
        "clients": [],
        "udp": true
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": { "serviceName": "trojan-grpc" }
      }
    },

    {
      "listen": "127.0.0.1",
      "port": 30310,
      "protocol": "shadowsocks",
      "settings": {
        "clients": [],
        "network": "tcp,udp"
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": { "serviceName": "ss-grpc" }
      }
    }
  ],

  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "blocked" },
    {
      "protocol": "freedom",
      "tag": "api"
    }
  ],

  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": ["api"],
        "outboundTag": "api"
      },
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

# ============================================================================
# ✅ CORRECTION : Service systemd Xray — Restart robuste + network-online
# ============================================================================
cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray -config /etc/xray/config.json
Restart=always
RestartSec=5s
StartLimitIntervalSec=0

[Install]
WantedBy=multi-user.target
EOF

# Nginx — config
# ============================================================================
DOMAIN=$(cat /etc/xray/domain)

cat > /etc/nginx/sites-enabled/default << EOF
server {
    listen 81 default_server;
    listen [::]:81 default_server;
    server_name $DOMAIN;
    root /var/www/html;
    index index.html;
    location / { try_files \$uri \$uri/ =404; }
}
EOF

cat > /etc/nginx/conf.d/xray.conf << EOF
# ========================================
# WS + gRPC TLS (port 8443)
# ========================================
server {
    listen 8443 ssl http2;
    listen [::]:8443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate     /etc/xray/xray.crt;
    ssl_certificate_key /etc/xray/xray.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers EECDH+CHACHA20:EECDH+AES128:EECDH+AES256:!MD5;

    root /home/vps/public_html;

    location /vless     { proxy_pass http://127.0.0.1:14016; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$http_host; proxy_set_header X-Real-IP \$remote_addr; }
    location /vmess     { proxy_pass http://127.0.0.1:23456; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$http_host; proxy_set_header X-Real-IP \$remote_addr; }
    location /trojan-ws { proxy_pass http://127.0.0.1:25432; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$http_host; proxy_set_header X-Real-IP \$remote_addr; }
    location /ss-ws     { proxy_pass http://127.0.0.1:30300; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$http_host; proxy_set_header X-Real-IP \$remote_addr; }

    location /vless-grpc  { grpc_pass grpc://127.0.0.1:24456; grpc_set_header X-Real-IP \$remote_addr; grpc_set_header Host \$http_host; }
    location /vmess-grpc  { grpc_pass grpc://127.0.0.1:31234; grpc_set_header X-Real-IP \$remote_addr; grpc_set_header Host \$http_host; }
    location /trojan-grpc { grpc_pass grpc://127.0.0.1:33456; grpc_set_header X-Real-IP \$remote_addr; grpc_set_header Host \$http_host; }
}

# WS non-TLS (port 8880)
# ========================================
server {
    listen 8880;
    listen [::]:8880;
    server_name $DOMAIN;
    root /home/vps/public_html;

    location /vless     { proxy_pass http://127.0.0.1:14016; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$http_host; proxy_set_header X-Real-IP \$remote_addr; }
    location /vmess     { proxy_pass http://127.0.0.1:23456; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$http_host; proxy_set_header X-Real-IP \$remote_addr; }
    location /trojan-ws { proxy_pass http://127.0.0.1:25432; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$http_host; proxy_set_header X-Real-IP \$remote_addr; }
    location /ss-ws     { proxy_pass http://127.0.0.1:30300; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$http_host; proxy_set_header X-Real-IP \$remote_addr; }
}
EOF

# ============================================================================
# ✅ CORRECTION : Service systemd Nginx — Restart robuste
# ============================================================================
# Nginx a déjà un bon service par défaut, on force juste le Restart=always
mkdir -p /etc/systemd/system/nginx.service.d
cat > /etc/systemd/system/nginx.service.d/override.conf << EOF
[Service]
Restart=always
RestartSec=5s
StartLimitIntervalSec=0
EOF

# Démarrage Xray + Nginx
# ============================================================================
systemctl daemon-reload
systemctl enable xray nginx
sleep 1

if systemctl restart xray nginx; then
  sleep 2
  if systemctl is-active --quiet xray; then
    echo -e "${GREEN}✅ Xray démarré avec succès.${NC}"
  else
    echo -e "${RED}❌ Xray n'a pas démarré.${NC}"
    journalctl -u xray -n 20 --no-pager
    exit 1
  fi
else
  echo -e "${RED}❌ Échec redémarrage Xray/Nginx.${NC}"
  journalctl -u xray -n 20 --no-pager
  exit 1
fi

# Test rapide de l'API stats
# ============================================================================
sleep 2
echo "🔍 Test API statsquery..."
if /usr/local/bin/xray api statsquery --server=127.0.0.1:10085 2>/dev/null; then
  echo -e "${GREEN}✅ API stats Xray opérationnelle.${NC}"
else
  echo "⚠️  API stats non accessible — vérifiez que le port 10085 est actif."
fi

# Installation Trojan-Go
# ============================================================================
latest_version_trj=$(curl -s https://api.github.com/repos/NevermoreSSH/addons/releases/latest \
  | grep tag_name | cut -d'"' -f4 | sed 's/v//')
trojan_link="https://github.com/NevermoreSSH/addons/releases/download/v${latest_version_trj}/trojan-go-linux-amd64.zip"

mkdir -p /usr/bin/trojan-go /etc/trojan-go
cd $(mktemp -d)
curl -L -o trojan-go.zip "$trojan_link"
unzip -o trojan-go.zip
mv trojan-go /usr/local/bin/trojan-go
chmod +x /usr/local/bin/trojan-go
mkdir -p /var/log/trojan-go
touch /etc/trojan-go/akun.conf /var/log/trojan-go/trojan-go.log

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
  "ssl": {
    "verify": false, "verify_hostname": false,
    "cert": "/etc/xray/xray.crt", "key": "/etc/xray/xray.key",
    "key_password": "", "sni": "$DOMAIN", "alpn": ["http/1.1"]
  },
  "tcp": { "no_delay": true, "keep_alive": true, "prefer_ipv4": true },
  "mux": { "enabled": false, "concurrency": 8, "idle_timeout": 60 },
  "websocket": { "enabled": true, "path": "/trojango", "host": "$DOMAIN" }
}
EOF

# ============================================================================
# ✅ NOUVEAU : Service systemd Trojan-Go (manquait complètement avant)
# ============================================================================
cat > /etc/systemd/system/trojan-go.service << EOF
[Unit]
Description=Trojan-Go Service
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/trojan-go -config /etc/trojan-go/config.json
Restart=always
RestartSec=5s
StartLimitIntervalSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable trojan-go
systemctl start trojan-go

if systemctl is-active --quiet trojan-go; then
  echo -e "${GREEN}✅ Trojan-Go démarré avec succès.${NC}"
else
  echo -e "${RED}❌ Trojan-Go n'a pas démarré.${NC}"
  journalctl -u trojan-go -n 10 --no-pager
fi

# Résumé final
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Installation terminée avec succès          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo "  Domaine   : $DOMAIN"
echo "  UUID      : $uuid"
echo ""
echo "  Ports Nginx : 8443 (TLS) | 8880 (non-TLS) | 81 (panel)"
echo "  API stats   : 127.0.0.1:10085"
echo ""
echo -e "${GREEN}  ✅ Collecte trafic compatible avec auto-clean.sh${NC}"
echo -e "${GREEN}  ✅ Chaque client ajouté via server.js aura un email = username${NC}"
echo -e "${GREEN}  ✅ Tous les services redémarrent automatiquement (reboot/crash)${NC}"
echo ""
echo "  Trojan-Go (port 2087) : trafic NON comptabilisé par Xray stats"
echo "      → Son trafic est géré séparément (processus indépendant)"
