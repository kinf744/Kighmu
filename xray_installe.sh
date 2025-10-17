#!/usr/bin/env bash
# Installation complète Xray + UFW, nettoyage avant installation, services systemd robustes
# Version GitHub-ready

set -euo pipefail

# Couleurs terminal
RED='\u001B[0;31m'
GREEN='\u001B[0m'\u001B[0;32m'
NC='\u001B[0m'

restart_xray_service() {
  echo -e "${GREEN}Redémarrage du service Xray...${NC}"
  systemctl restart xray
  sleep 3
  for i in {1..3}; do
    if systemctl is-active --quiet xray; then
      echo -e "${GREEN}Xray redémarré avec succès.${NC}"
      return 0
    else
      echo -e "${RED}Échec du redémarrage, tentative $i...${NC}"
      sleep 2
      systemctl restart xray
    fi
  done
  echo -e "${RED}Erreur persistante lors du redémarrage de Xray.${NC}"
  journalctl -u xray -n 40 --no-pager
  exit 1
}

clean_xray_environment() {
  echo -e "${GREEN}Nettoyage complet de l'environnement Xray...${NC}"

  # Arrêter et désactiver le service Xray
  systemctl stop xray 2>/dev/null || true
  systemctl disable xray 2>/dev/null || true
  systemctl daemon-reload

  # Tuer processus sur ports 89 et 8443 (TCP et UDP)
  for port in 89 8443; do
      lsof -i tcp:$port -t | xargs -r kill -9
      lsof -i udp:$port -t | xargs -r kill -9
  done

  # Pause pour libérer les ports
  sleep 5

  # Supprimer anciens fichiers et dossiers liés à Xray
  rm -rf /etc/xray /var/log/xray /usr/local/bin/xray /tmp/.xray_domain /etc/systemd/system/xray.service
  rm -rf /tmp/xray-temp /var/run/xray

  systemctl daemon-reload

  echo -e "${GREEN}Nettoyage effectué.${NC}"
}

# Début script principal

clean_xray_environment

# Demander domaine
read -rp "Entrez votre nom de domaine (ex: monsite.com) : " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo -e "${RED}Erreur : nom de domaine non valide.${NC}"
  exit 1
fi

echo "$DOMAIN" > /tmp/.xray_domain
EMAIL="votre-adresse@example.com"

# Mise à jour + dépendances
apt update
apt install -y ufw iptables iptables-persistent curl socat xz-utils wget apt-transport-https \
  gnupg dnsutils lsb-release cron bash-completion ntpdate chrony unzip jq

# Configuration UFW (ports 80 et 8443 nécessaires pour ACME + TLS)
ufw allow ssh
ufw allow 89/tcp
ufw allow 89/udp
ufw allow 8443/tcp
ufw allow 8443/udp
# Ouverture temporaire du port 80 pour ACME si nécessaire
ufw allow 80/tcp || true
echo "y" | ufw enable
ufw status verbose
netfilter-persistent save

ntpdate pool.ntp.org
timedatectl set-ntp true
systemctl enable chronyd
systemctl restart chronyd
timedatectl set-timezone Asia/Kuala_Lumpur
chronyc sourcestats -v
chronyc tracking -v
date

# Télécharger dernière version Xray
latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep tag_name | sed -E 's/.*"v(.*)".*/\u0001/' | head -n1)
if [[ -z "$latest_version" ]]; then
  echo -e "${RED}Impossible de récupérer la dernière version de Xray.${NC}"
  exit 1
fi
xraycore_link="https://github.com/XTLS/Xray-core/releases/download/v${latest_version}/xray-linux-64.zip"

systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true
sudo lsof -t -i tcp:89 -s tcp:listen | sudo xargs kill -9 2>/dev/null || true

mkdir -p /usr/local/bin
cd "$(mktemp -d)"
curl -sL "$xraycore_link" -o xray.zip
if [[ ! -f "xray.zip" ]]; then
  echo -e "${RED}Échec du téléchargement de Xray.${NC}"
  exit 1
fi
unzip -q xray.zip && rm -f xray.zip
mv xray /usr/local/bin/xray
chmod +x /usr/local/bin/xray
setcap 'cap_net_bind_service=+ep' /usr/local/bin/xray

mkdir -p /var/log/xray /etc/xray
touch /var/log/xray/access.log /var/log/xray/error.log
chown -R root:root /var/log/xray
chmod 644 /var/log/xray/access.log /var/log/xray/error.log

# Script ACME (assurez-vous que acme.sh est installé et accessible)
ACME_BIN="${HOME}/.acme.sh/acme.sh"
if [[ ! -f "$ACME_BIN" ]]; then
  # Téléchargement + installation d'acme.sh
  curl https://get.acme.sh | sh
  # Charger le shell pour récupérer PATHs
  . "$HOME"/.bashrc 2>/dev/null || true
fi

# Option DNS ou HTTP pour ACME
use_dns_answer=false
read -rp "Utiliser DNS-01 pour ACME ? (o/n) [par défaut n] : " dns_choice
if [[ "${dns_choice,,}" == "o" || "${dns_choice,,}" == "yes" || "${dns_choice,,}" == "y" ]]; then
  use_dns_answer=true
fi

# Si DNS-01, demandez les clés/fournisseur DNS et configurez
if $use_dns_answer; then
  echo "Configurer DNS-01 nécessite un fournisseur pris en charge par acme.sh et les clés API configurées."
fi

# Arrêt éventuel du service Xray si présent
systemctl stop xray 2>/dev/null || true

# Certification TLS
$ACME_BIN --register-account -m "$EMAIL" --log 2>&1 | sed -n '1,200p'
if $use_dns_answer; then
  # Exemple (à adapter selon votre fournisseur DNS et variable d'environnement)
  $ACME_BIN --issue --dns dns_cf -d "$DOMAIN" --force
else
  # Standalone HTTP-01 (ouvert temporairement le port 80)
  ufw allow 80/tcp
  $ACME_BIN --issue --standalone -d "$DOMAIN" --force
  ufw delete allow 80/tcp
fi

# Vérification de l'écriture des règles ACME dans le log
# Attendre un peu pour la propagation
sleep 5

# Installation des certificats
$ACME_BIN --installcert -d "$DOMAIN" --ecc \
  --cert-file /etc/xray/xray.crt \
  --key-file /etc/xray/xray.key \
  --fullchain-file /etc/xray/fullchain.cer

# Vérification des fichiers
if [[ ! -f "/etc/xray/xray.crt" || ! -f "/etc/xray/xray.key" || ! -f "/etc/xray/fullchain.cer" ]]; then
  echo -e "${RED}Erreur : certificats TLS non trouvés après installation (chemins attendus : /etc/xray/).${NC}"
  echo "Détails : "
  ls -l /etc/xray/ 2>/dev/null || true
  cat ~/.acme.sh/acme.sh.log 2>/dev/null || true
  exit 1
fi

# Génération des UUID pour utilisateurs
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
  "trojan_tls": "$uuid5",
  "trojan_ntls": "$uuid6"
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
      "port": 89,
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
      "port": 89,
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
      "port": 89,
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

restart_xray_service

echo -e "${GREEN}Installation complète terminée.${NC}"
echo "Domaine : $DOMAIN"
echo "UUID VMess TLS : $uuid1"
echo "UUID VMess Non-TLS : $uuid2"
echo "UUID VLESS TLS : $uuid3"
echo "UUID VLESS Non-TLS : $uuid4"
echo "Mot de passe Trojan WS TLS : $uuid5"
echo "Mot de passe Trojan WS Non-TLS : $uuid6"
