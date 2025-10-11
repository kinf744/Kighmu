#!/bin/bash
# Installation complète Xray + UFW, nettoyage avant installation, services systemd robustes

# Couleurs terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

restart_xray_service() {
  echo -e "${GREEN}Redémarrage du service Xray...${NC}"
  systemctl restart xray
  sleep 2
  if systemctl is-active --quiet xray; then
    echo -e "${GREEN}Xray redémarré avec succès.${NC}"
  else
    echo -e "${RED}Erreur lors du redémarrage de Xray.${NC}"
    journalctl -u xray -n 20 --no-pager
    exit 1
  fi
}

# Nettoyage précédent avant installation
echo -e "${GREEN}Arrêt des services utilisant les ports 80 et 8443...${NC}"

# Trouver et tuer tous processus écoutant sur les ports 80 et 8443 (TCP et UDP)
for port in 80 8443; do
    lsof -i tcp:$port -t | xargs -r kill -9
    lsof -i udp:$port -t | xargs -r kill -9
done

# Arrêter et désactiver les services systemd potentiellement en conflit
for srv in xray nginx apache2; do
    systemctl stop $srv 2>/dev/null || true
    systemctl disable $srv 2>/dev/null || true
done

echo -e "${GREEN}Nettoyage des fichiers précédents...${NC}"

# Supprimer toutes les anciennes configurations et fichiers
rm -rf /etc/xray /var/log/xray /usr/local/bin/xray /tmp/.xray_domain /etc/systemd/system/xray.service

# Recharger systemd pour appliquer les suppressions
systemctl daemon-reload

# Demander domaine
read -rp "Entrez votre nom de domaine (ex: monsite.com) : " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo -e "${RED}Erreur : nom de domaine non valide.${NC}"
  exit 1
fi

# Écriture domaine pour menu
echo "$DOMAIN" > /tmp/.xray_domain

EMAIL="adrienkiaje@gmail.com"

# Mise à jour et dépendances
apt update
apt install -y ufw iptables iptables-persistent curl socat xz-utils wget apt-transport-https \
  gnupg gnupg2 gnupg1 dnsutils lsb-release cron bash-completion ntpdate chrony unzip jq

# Configuration UFW - ouvrir uniquement SSH, 80, 8443
ufw allow ssh
ufw allow 80/tcp
ufw allow 80/udp
ufw allow 8443/tcp
ufw allow 8443/udp

# Activer UFW automatiquement (valider par 'y')
echo "y" | ufw enable
ufw status verbose

# Sauvegarder règles UFW pour persistance
netfilter-persistent save

# Synchronisation temps
ntpdate pool.ntp.org
timedatectl set-ntp true
systemctl enable chronyd
systemctl restart chronyd
timedatectl set-timezone Asia/Kuala_Lumpur

# Info chrony
chronyc sourcestats -v
chronyc tracking -v
date

# Dernière version Xray
latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep tag_name | sed -E 's/.*"v(.*)".*/\1/' | head -n1)
xraycore_link="https://github.com/XTLS/Xray-core/releases/download/v${latest_version}/xray-linux-64.zip"

# Arrêt services sur port 80 si existants (redondant mais sécuritaire)
systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true
sudo lsof -t -i tcp:80 -s tcp:listen | sudo xargs kill -9 2>/dev/null || true

# Installation Xray
mkdir -p /usr/local/bin
cd $(mktemp -d)
curl -sL "$xraycore_link" -o xray.zip
unzip -q xray.zip && rm -f xray.zip
mv xray /usr/local/bin/xray
chmod +x /usr/local/bin/xray
setcap 'cap_net_bind_service=+ep' /usr/local/bin/xray

# Préparation dossier et logs avec bonnes permissions
mkdir -p /var/log/xray /etc/xray
touch /var/log/xray/access.log /var/log/xray/error.log
chown -R root:root /var/log/xray
chmod 644 /var/log/xray/access.log /var/log/xray/error.log

# Installer acme.sh si pas présent
if ! command -v ~/.acme.sh/acme.sh &> /dev/null; then
  curl https://get.acme.sh | sh
  source ~/.bashrc
fi

# Arrêter Xray avant génération certificat pour libérer port 80
systemctl stop xray

# Générer et installer certificat TLS
~/.acme.sh/acme.sh --register-account -m "$EMAIL"
~/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN" --force
~/.acme.sh/acme.sh --installcert -d "$DOMAIN" --fullchainpath /etc/xray/xray.crt --keypath /etc/xray/xray.key

# Vérifier certificats TLS
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

# users.json pour menu
cat > /etc/xray/users.json << EOF
{
  "vmess_tls": "$uuid1",
  "vmess_ntls": "$uuid2",
  "vless_tls": "$uuid3",
  "vless_ntls": "$uuid4",
  "trojan_tls": "$uuid5",
  "trojan_ntls": "$uuid6"
}
EOF

# Configuration Xray complète (inclut Trojan WS TLS et non-TLS)
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
        "tlsSettings": {"certificates": [{"certificateFile": "/etc/xray/xray.crt", "keyFile": "/etc/xray/xray.key"}]},
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
  "routing": {"rules": [{"type": "field", "ip": ["0.0.0.0/8","10.0.0.0/8","100.64.0.0/10","169.254.0.0/16","172.16.0.0/12","192.0.0.0/24","192.0.2.0/24","192.168.0.0/16","198.18.0.0/15","198.51.100.0/24","203.0.113.0/24","::1/128","fc00::/7","fe80::/10"], "outboundTag": "blocked"}]},
  "policy": {"levels": {"0": {"statsUserDownlink":true,"statsUserUplink":true}}, "system": {"statsInboundUplink":true,"statsInboundDownlink":true}},
  "stats": {},
  "api": {"services": ["StatsService"], "tag": "api"}
}
EOF

# Service systemd Xray
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

# Reload systemd and enable/start service
systemctl daemon-reload
systemctl enable xray

restart_xray_service

echo -e "${GREEN}Installation complète terminée.${NC}"
echo "Domaine : $DOMAIN"
echo "UUID VMess TLS : $uuid1"
echo "UUID VMess Non-TLS : $uuid2"
echo "UUID VLESS TLS : $uuid3"
echo "UUID VLESS Non-TLS : $uuid4"
echo "Mot de passe Trojan WS TLS : $uuid5"
echo "Mot de passe Trojan WS Non-TLS : $uuid6"
