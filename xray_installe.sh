#!/bin/bash
# xray_installe.sh — Installation complète Xray + Nginx
# Protocoles : WS-TLS, WS-NTLS, gRPC-TLS (via Nginx 8443/8880)
# Architecture :
#   Nginx port 8443 TLS  → WS  /vmess-tls /vless-tls
#                        → gRPC vmess-grpc vless-grpc
#   Nginx port 8880 NTLS → WS  /vmess-ntls /vless-ntls
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

# ==========
# Dépendances
# ==========
apt update
apt install -y iptables nginx iptables-persistent curl socat xz-utils wget \
  apt-transport-https gnupg gnupg2 gnupg1 dnsutils lsb-release cron \
  bash-completion ntpdate chrony unzip jq ca-certificates libcap2-bin

# =========
# iptables
# ==========
if ! iptables -C INPUT -p tcp --dport 81 -j ACCEPT 2>/dev/null; then
  iptables -I INPUT -p tcp --dport 81 -j ACCEPT
fi
iptables -A INPUT  -p tcp --dport 22   -j ACCEPT
iptables -A INPUT  -p tcp --dport 8880 -j ACCEPT
iptables -A INPUT  -p udp --dport 8880 -j ACCEPT
iptables -A INPUT  -p tcp --dport 8443 -j ACCEPT
iptables -A INPUT  -p udp --dport 8443 -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
netfilter-persistent save
echo "✅ iptables configuré."

# ============
# Installation Xray
# ============
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

# ==============
# Certificat TLS (ACME)
# ==============
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

  # ── Mode webroot via Nginx (évite le conflit sur le port 80) ──────────
  # Nginx est déjà actif sur le port 80. On utilise webroot plutôt que
  # standalone afin qu'acme.sh dépose son challenge dans /var/www/html
  # et que Nginx le serve, sans avoir à libérer le port 80.
  WEBROOT="/var/www/html"
  mkdir -p "${WEBROOT}/.well-known/acme-challenge"

  # Configurer Nginx pour servir le challenge ACME sur ce domaine
  cat > /etc/nginx/conf.d/acme-challenge.conf << ACMEOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    root ${WEBROOT};
    location /.well-known/acme-challenge/ {
        allow all;
    }
}
ACMEOF
  # Démarrer Nginx s'il n'est pas encore actif (nécessaire pour le webroot challenge)
  if ! systemctl is-active --quiet nginx; then
    systemctl start nginx || true
  else
    nginx -t && systemctl reload nginx || true
  fi

  # Supprimer tout ancien cert ECC/RSA incomplet pour ce domaine
  # (évite l'erreur "seems to have ECC cert" avec fichier .key manquant)
  for cert_dir in \
      "${HOME}/.acme.sh/${DOMAIN}" \
      "${HOME}/.acme.sh/${DOMAIN}_ecc"; do
    if [[ -d "$cert_dir" ]] && [[ ! -f "$cert_dir/${DOMAIN}.key" ]]; then
      echo "WARNING: Cert incomplet détecté dans $cert_dir — suppression."
      rm -rf "$cert_dir"
    fi
  done

  if ! bash acme.sh --list | grep -q "$DOMAIN"; then
    bash acme.sh --issue --webroot "$WEBROOT" -d "$DOMAIN" --keylength ec-256
  fi

  # ── Créer le service systemd Xray AVANT le --reloadcmd ──────────────────
  # acme.sh exécute le reloadcmd immédiatement après l'installation du cert.
  # Si xray.service n'existe pas encore, systemctl échoue avec "Unit not found".
  cat > /etc/systemd/system/xray.service << 'SVCEOF'
[Unit]
Description=Xray Service
After=network-online.target nss-lookup.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray -config /etc/xray/config.json
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
SVCEOF
  systemctl daemon-reload
  systemctl enable xray || true
  # ────────────────────────────────────────────────────────────────────────

  bash acme.sh --installcert -d "$DOMAIN" \
    --fullchainpath "$ACME_CERT" \
    --keypath "$ACME_KEY" \
    --ecc \
    --reloadcmd "systemctl restart xray nginx"

  # Supprimer la conf ACME temporaire — elle n'est plus nécessaire
  rm -f /etc/nginx/conf.d/acme-challenge.conf
  nginx -t && systemctl reload nginx || true

  if [[ ! -f "$ACME_CERT" || ! -f "$ACME_KEY" ]]; then
    echo -e "${RED}❌ Certificats TLS non générés.${NC}"
    [[ "$SSHWS_STOPPED" == true ]] && systemctl start sshws
    exit 1
  fi

  echo -e "${GREEN}✅ Certificat TLS généré.${NC}"
  [[ "$SSHWS_STOPPED" == true ]] && systemctl start sshws
fi

# ============
# users.json — format compatible menu_6.sh
# ============
cat > /etc/xray/users.json << 'USERSEOF'
{
  "vmess": [],
  "vless": [],
  "trojan": []
}
USERSEOF

# ============
# config.json Xray
#
# Architecture des inbounds :
#
# Via Nginx (127.0.0.1) — port public 8443 TLS :
#   VMess  WS  TLS  → 127.0.0.1:23456  path /vmess-tls
#   VLESS  WS  TLS  → 127.0.0.1:14016  path /vless-tls
#   Trojan WS  TLS  → 127.0.0.1:13001  path /trojan-tls
#   VMess  gRPC TLS → 127.0.0.1:31234  serviceName vmess-grpc
#   VLESS  gRPC TLS → 127.0.0.1:24456  serviceName vless-grpc
#   Trojan gRPC TLS → 127.0.0.1:13002  serviceName trojan-grpc
#
# Via Nginx (127.0.0.1) — port public 8880 NTLS :
#   VMess  WS  NTLS → 127.0.0.1:23457  path /vmess-ntls
#   VLESS  WS  NTLS → 127.0.0.1:14017  path /vless-ntls
#   Trojan WS  NTLS → 127.0.0.1:13003  path /trojan-ntls
# ============
DOMAIN=$(cat /etc/xray/domain)

cat > /etc/xray/config.json << CONFIGEOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
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
      "tag": "vmess-ws-tls",
      "listen": "127.0.0.1",
      "port": 23456,
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vmess-tls", "host": "$DOMAIN" }
      }
    },

    {
      "tag": "vless-ws-tls",
      "listen": "127.0.0.1",
      "port": 14016,
      "protocol": "vless",
      "settings": { "decryption": "none", "clients": [] },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vless-tls", "host": "$DOMAIN" }
      }
    },

    {
      "tag": "vmess-grpc-tls",
      "listen": "127.0.0.1",
      "port": 31234,
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": { "serviceName": "vmess-grpc" }
      }
    },

    {
      "tag": "vless-grpc-tls",
      "listen": "127.0.0.1",
      "port": 24456,
      "protocol": "vless",
      "settings": { "decryption": "none", "clients": [] },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": { "serviceName": "vless-grpc" }
      }
    },

    {
      "tag": "vmess-ws-ntls",
      "listen": "127.0.0.1",
      "port": 23457,
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vmess-ntls", "host": "$DOMAIN" }
      }
    },

    {
      "tag": "vless-ws-ntls",
      "listen": "127.0.0.1",
      "port": 14017,
      "protocol": "vless",
      "settings": { "decryption": "none", "clients": [] },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vless-ntls", "host": "$DOMAIN" }
      }
    },

    {
      "tag": "trojan-ws-tls",
      "listen": "127.0.0.1",
      "port": 13001,
      "protocol": "trojan",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/trojan-tls", "host": "$DOMAIN" }
      }
    },

    {
      "tag": "trojan-grpc-tls",
      "listen": "127.0.0.1",
      "port": 13002,
      "protocol": "trojan",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": { "serviceName": "trojan-grpc" }
      }
    },

    {
      "tag": "trojan-ws-ntls",
      "listen": "127.0.0.1",
      "port": 13003,
      "protocol": "trojan",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/trojan-ntls", "host": "$DOMAIN" }
      }
    }

  ],

  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "blocked" },
    { "protocol": "freedom", "tag": "api" }
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
          "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10",
          "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16",
          "::1/128", "fc00::/7", "fe80::/10"
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
CONFIGEOF

# ============
# Service systemd Xray — déjà créé avant acme.sh si TLS généré,
# on s'assure qu'il existe aussi dans le cas réutilisation du cert
# ============
if [[ ! -f /etc/systemd/system/xray.service ]]; then
cat > /etc/systemd/system/xray.service << 'SVCEOF'
[Unit]
Description=Xray Service
After=network-online.target nss-lookup.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray -config /etc/xray/config.json
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
SVCEOF
fi

# ============
# Nginx — config (WS TLS, WS NTLS, gRPC TLS)
# ============
DOMAIN=$(cat /etc/xray/domain)

cat > /etc/nginx/sites-enabled/default << NGINXDEFEOF
server {
    listen 81 default_server;
    listen [::]:81 default_server;
    server_name $DOMAIN;
    root /var/www/html;
    index index.html;
    location / { try_files \$uri \$uri/ =404; }
}
NGINXDEFEOF

cat > /etc/nginx/conf.d/xray.conf << NGINXEOF
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

    root /var/www/html;

    location /vmess-tls { proxy_pass http://127.0.0.1:23456; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$http_host; proxy_set_header X-Real-IP \$remote_addr; }
    location /vless-tls { proxy_pass http://127.0.0.1:14016; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$http_host; proxy_set_header X-Real-IP \$remote_addr; }
    location /trojan-tls { proxy_pass http://127.0.0.1:13001; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$http_host; proxy_set_header X-Real-IP \$remote_addr; }

    location /vless-grpc { grpc_pass grpc://127.0.0.1:24456; grpc_set_header X-Real-IP \$remote_addr; grpc_set_header Host \$http_host; }
    location /vmess-grpc { grpc_pass grpc://127.0.0.1:31234; grpc_set_header X-Real-IP \$remote_addr; grpc_set_header Host \$http_host; }
    location /trojan-grpc { grpc_pass grpc://127.0.0.1:13002; grpc_set_header X-Real-IP \$remote_addr; grpc_set_header Host \$http_host; }
}

# ========================================
# WS non-TLS (port 8880)
# ========================================
server {
    listen 8880;
    listen [::]:8880;
    server_name $DOMAIN;
    root /var/www/html;

    location /vmess-ntls { proxy_pass http://127.0.0.1:23457; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$http_host; proxy_set_header X-Real-IP \$remote_addr; }
    location /vless-ntls { proxy_pass http://127.0.0.1:14017; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$http_host; proxy_set_header X-Real-IP \$remote_addr; }
    location /trojan-ntls { proxy_pass http://127.0.0.1:13003; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$http_host; proxy_set_header X-Real-IP \$remote_addr; }
}
NGINXEOF

# ============
# Nginx — Restart robuste
# ============
mkdir -p /etc/systemd/system/nginx.service.d
cat > /etc/systemd/system/nginx.service.d/override.conf << 'NGINXOVREOF'
[Service]
Restart=always
RestartSec=5s
StartLimitIntervalSec=0
NGINXOVREOF

# ============
# logrotate — rotation des logs Xray
# ============
cat > /etc/logrotate.d/xray << 'LOGEOF'
/var/log/xray/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    sharedscripts
    postrotate
        systemctl restart xray > /dev/null 2>&1 || true
    endscript
}
LOGEOF

# ========
# Démarrage Xray + Nginx
# =========
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
sleep 2
echo "🔍 Test API statsquery..."
if /usr/local/bin/xray api statsquery --server=127.0.0.1:10085 2>/dev/null; then
  echo -e "${GREEN}✅ API stats Xray opérationnelle.${NC}"
else
  echo "⚠️  API stats non accessible — vérifiez que le port 10085 est actif."
fi

# ============
# Résumé final
# ============
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        Installation terminée avec succès                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Domaine    : $DOMAIN"
echo ""
echo "  ┌─ Nginx TLS  8443 : WS (/vmess-tls /vless-tls /trojan-tls)"
echo "  │                    gRPC (/vmess-grpc /vless-grpc /trojan-grpc)"
echo "  └─ Nginx NTLS 8880 : WS (/vmess-ntls /vless-ntls /trojan-ntls)"
echo ""
echo "  API stats   : 127.0.0.1:10085"
echo ""
echo -e "${GREEN}  ✅ Renouvellement certificat TLS automatique (acme.sh --reloadcmd)${NC}"
echo -e "${GREEN}  ✅ Rotation logs Xray configurée (logrotate)${NC}"
echo -e "${GREEN}  ✅ Collecte trafic compatible avec auto-clean.sh${NC}"
echo -e "${GREEN}  ✅ Tous les services redémarrent automatiquement (reboot/crash)${NC}"
