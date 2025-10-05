#!/bin/bash

# Variables
EMAIL="adrienkiaje@gmail.com"     # Peut servir pour acme.sh si besoin
DOMAIN_FILE="/root/domain"         # Fichier contenant le domaine préféré

# Couleurs
GREEN='\033[0;32m'
NC='\033[0m'

# Vérification root
if [ "$EUID" -ne 0 ]; then
  echo -e "${GREEN}Erreur: Exécuter ce script en root.${NC}" >&2
  exit 1
fi

# Récupérer le domaine
if [ -f "$DOMAIN_FILE" ]; then
  DOMAIN=$(cat "$DOMAIN_FILE")
else
  read -rp "Entrez votre nom de domaine (ex: monsite.com) : " DOMAIN
  if [ -z "$DOMAIN" ]; then
    echo "Erreur: nom de domaine invalide"
    exit 1
  fi
fi
echo -e "${GREEN}Domaine : $DOMAIN${NC}"

# Synchronisation temps et fuseau horaire
apt update
apt install -y ntpdate chrony socat curl wget unzip bash-completion iptables-persistent
ntpdate -u pool.ntp.org
timedatectl set-ntp true
timedatectl set-timezone Etc/UTC

# Installer nginx
apt install -y nginx

# Installer acme.sh (certificat ECC)
curl https://get.acme.sh | sh
source ~/.bashrc || source ~/.profile
~/.acme.sh/acme.sh --upgrade --auto-upgrade
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --keylength ec-256

# Installer certificat dans /etc/xray
mkdir -p /etc/xray
~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --ecc \
  --fullchain-file /etc/xray/xray.crt \
  --key-file /etc/xray/xray.key
chmod 644 /etc/xray/xray.crt /etc/xray/xray.key
chown -R www-data:www-data /etc/xray

# Génération ports randomisés
vless=$((RANDOM + 10000))
vmess=$((RANDOM + 11000))
trojanws=$((RANDOM + 12000))
vlessgrpc=$((RANDOM + 13000))
vmessgrpc=$((RANDOM + 14000))
trojangrpc=$((RANDOM + 15000))

# Génération UUID
UUID=$(cat /proc/sys/kernel/random/uuid)

# Écrire configuration Xray JSON
cat > /etc/xray/config.json << EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": $vless,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$UUID"}],
        "decryption": "none"
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
      "port": $vmess,
      "protocol": "vmess",
      "settings": {
        "clients": [{"id": "$UUID", "alterId": 0}]
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
      "port": $trojanws,
      "protocol": "trojan",
      "settings": {
        "clients": [{"password": "$UUID"}],
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
      "port": $vlessgrpc,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$UUID"}],
        "decryption": "none"
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
      "port": $vmessgrpc,
      "protocol": "vmess",
      "settings": {
        "clients": [{"id": "$UUID", "alterId": 0}]
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
      "port": $trojangrpc,
      "protocol": "trojan",
      "settings": {
        "clients": [{"password": "$UUID"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
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
    }
  ]
}
EOF

# Configuration Nginx reverse proxy
cat > /etc/nginx/conf.d/xray.conf << EOF
server {
  listen 80;
  listen 443 ssl http2;
  server_name $DOMAIN;

  ssl_certificate /etc/xray/xray.crt;
  ssl_certificate_key /etc/xray/xray.key;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_ciphers EECDH+AESGCM:EDH+AESGCM;
  
  location /vless {
    proxy_redirect off;
    proxy_pass http://127.0.0.1:$vless;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
  }
  location /vmess {
    proxy_redirect off;
    proxy_pass http://127.0.0.1:$vmess;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
  }
  location /trojan-ws {
    proxy_redirect off;
    proxy_pass http://127.0.0.1:$trojanws;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
  }
  location ^~ /vless-grpc {
    grpc_pass grpc://127.0.0.1:$vlessgrpc;
    grpc_set_header X-Real-IP \$remote_addr;
    grpc_set_header Host \$host;
  }
  location ^~ /vmess-grpc {
    grpc_pass grpc://127.0.0.1:$vmessgrpc;
    grpc_set_header X-Real-IP \$remote_addr;
    grpc_set_header Host \$host;
  }
  location ^~ /trojan-grpc {
    grpc_pass grpc://127.0.0.1:$trojangrpc;
    grpc_set_header X-Real-IP \$remote_addr;
    grpc_set_header Host \$host;
  }
}
EOF

# Ajuster permissions
chown -R www-data:www-data /etc/xray
chown -R www-data:www-data /var/log/xray 2>/dev/null || mkdir -p /var/log/xray && chown -R www-data:www-data /var/log/xray

# Création fichier service systemd Xray
cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target

[Service]
User=www-data
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNOFILE=100000
LimitNPROC=10000

[Install]
WantedBy=multi-user.target
EOF

# Rechargement daemon et lancement services
systemctl daemon-reload
systemctl enable xray nginx
systemctl restart xray nginx

if systemctl is-active --quiet xray && systemctl is-active --quiet nginx; then
  echo -e "${GREEN}Xray et Nginx démarrés avec succès.${NC}"
else
  echo "Erreur : échec du démarrage des services Xray ou Nginx."
  journalctl -u xray -n 20 --no-pager
  journalctl -u nginx -n 20 --no-pager
  exit 1
fi

# Script renouvellement automatique certificat & redémarrage services
cat > /usr/local/bin/renew-cert.sh << 'EOF'
#!/bin/bash
~/.acme.sh/acme.sh --cron --home ~/.acme.sh > /root/renew_cert.log 2>&1
systemctl restart nginx
systemctl restart xray
EOF
chmod +x /usr/local/bin/renew-cert.sh

# Cron renewal tous les 3 jours à 3h15
(crontab -l 2>/dev/null; echo "15 3 */3 * * /usr/local/bin/renew-cert.sh") | crontab -

# Affichage infos d’installation
echo -e "${GREEN}----- Xray installé avec TLS ECC & Nginx reverse proxy -----${NC}"
echo -e "Domaine : $DOMAIN"
echo -e "UUID : $UUID"
echo -e "Ports WS:"
echo -e "  VLESS: $vless (ws)"
echo -e "  VMESS: $vmess (ws)"
echo -e "  TROJAN WS: $trojanws (ws)"
echo -e "Ports gRPC:"
echo -e "  VLESS gRPC: $vlessgrpc"
echo -e "  VMESS gRPC: $vmessgrpc"
echo -e "  TROJAN gRPC: $trojangrpc"
echo -e "Certificat TLS: /etc/xray/xray.crt"
echo -e "Clé TLS: /etc/xray/xray.key"
echo -e "N’oublie pas d’ouvrir les ports 80 et 443 dans le firewall."
