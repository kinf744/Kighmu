#!/bin/bash
# Installation complète Xray + UFW, avec exécution via screen
# Par NevermoreSSH modifié pour Screen Mode

# Couleurs terminal
RED='\u001B[0;31m'
GREEN='\u001B[0;32m'
NC='\u001B[0m'

clean_xray_environment() {
  echo -e "${GREEN}Nettoyage complet de l'environnement Xray...${NC}"

  # Arrêter service et tuer processus sur ports
  pkill -f "/usr/local/bin/xray" 2>/dev/null || true
  screen -S xray -X quit 2>/dev/null || true

  systemctl stop xray 2>/dev/null || true
  systemctl disable xray 2>/dev/null || true
  systemctl daemon-reload

  for port in 89 8443; do
      lsof -i tcp:$port -t | xargs -r kill -9
      lsof -i udp:$port -t | xargs -r kill -9
  done

  sleep 3

  rm -rf /etc/xray /var/log/xray /usr/local/bin/xray /tmp/.xray_domain /etc/systemd/system/xray.service
  rm -rf /tmp/xray-temp /var/run/xray

  echo -e "${GREEN}Nettoyage effectué.${NC}"
}

# Début script principal

clean_xray_environment

read -rp "Entrez votre nom de domaine (ex: monsite.com) : " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  echo -e "${RED}Erreur : nom de domaine non valide.${NC}"
  exit 1
fi

echo "$DOMAIN" > /tmp/.xray_domain
EMAIL="adrienkiaje@gmail.com"

# Installation dépendances
apt update
apt install -y ufw iptables iptables-persistent curl socat xz-utils wget apt-transport-https \
  gnupg gnupg2 gnupg1 dnsutils lsb-release cron bash-completion ntpdate chrony unzip jq screen

# Configuration UFW
ufw allow ssh
ufw allow 89/tcp
ufw allow 89/udp
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
chronyc sourcestats -v
chronyc tracking -v
date

# Télécharger dernière version de Xray
latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep tag_name | sed -E 's/.*"v(.*)".*/\u0001/' | head -n1)
xraycore_link="https://github.com/XTLS/Xray-core/releases/download/v${latest_version}/xray-linux-64.zip"

systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true
sudo lsof -t -i tcp:89 -s tcp:listen | sudo xargs kill -9 2>/dev/null || true

mkdir -p /usr/local/bin
cd $(mktemp -d)
curl -sL "$xraycore_link" -o xray.zip
unzip -q xray.zip && rm -f xray.zip
mv xray /usr/local/bin/xray
chmod +x /usr/local/bin/xray
setcap 'cap_net_bind_service=+ep' /usr/local/bin/xray

mkdir -p /var/log/xray /etc/xray
touch /var/log/xray/access.log /var/log/xray/error.log
chmod 644 /var/log/xray/access.log /var/log/xray/error.log

# Installation acme.sh et certificats
if ! command -v ~/.acme.sh/acme.sh &> /dev/null; then
  curl https://get.acme.sh | sh
  source ~/.bashrc
fi

~/.acme.sh/acme.sh --register-account -m "$EMAIL"
~/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN" --force
sleep 5
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
        "wsSettings": {"path": "/vmess","headers": {"Host": "$DOMAIN"}}
      }
    },
    {
      "port": 89,
      "protocol": "vmess",
      "settings": {"clients": [{"id": "$uuid2", "alterId": 0}]},
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {"path": "/vmess","headers": {"Host": "$DOMAIN"}}
      }
    },
    {
      "port": 8443,
      "protocol": "vless",
      "settings": {"clients": [{"id": "$uuid3"}], "decryption": "none"},
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {"certificates": [{"certificateFile": "/etc/xray/xray.crt", "keyFile": "/etc/xray/xray.key"}]},
        "wsSettings": {"path": "/vless","headers": {"Host": "$DOMAIN"}}
      }
    },
    {
      "port": 89,
      "protocol": "vless",
      "settings": {"clients": [{"id": "$uuid4"}], "decryption": "none"},
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {"path": "/vless","headers": {"Host": "$DOMAIN"}}
      }
    },
    {
      "port": 8443,
      "protocol": "trojan",
      "settings": {"clients": [{"password": "$uuid5"}]},
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {"certificates": [{"certificateFile": "/etc/xray/xray.crt","keyFile": "/etc/xray/xray.key"}]},
        "wsSettings": {"path": "/trojanws","headers": {"Host": "$DOMAIN"}}
      }
    },
    {
      "port": 89,
      "protocol": "trojan",
      "settings": {"clients": [{"password": "$uuid6"}]},
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {"path": "/trojanws","headers": {"Host": "$DOMAIN"}}
      }
    }
  ],
  "outbounds": [{"protocol": "freedom","settings": {}}]
}
EOF

# Lancer Xray via screen
echo -e "${GREEN}Démarrage de Xray via Screen...${NC}"
pkill -f "/usr/local/bin/xray" 2>/dev/null || true
screen -S xray -X quit 2>/dev/null || true
sleep 2
screen -dmS xray /usr/local/bin/xray -config /etc/xray/config.json

sleep 3
if pgrep -f "/usr/local/bin/xray" >/dev/null; then
  echo -e "${GREEN}Xray est maintenant actif dans la session Screen 'xray'.${NC}"
  echo "Pour voir les logs : screen -r xray"
  echo "Pour détacher : Ctrl+A puis D"
else
  echo -e "${RED}Erreur : le processus Xray ne s'est pas lancé correctement.${NC}"
  exit 1
fi

echo -e "${GREEN}Installation complète terminée.${NC}"
echo "Domaine : $DOMAIN"
echo "UUID VMess TLS : $uuid1"
echo "UUID VMess Non-TLS : $uuid2"
echo "UUID VLESS TLS : $uuid3"
echo "UUID VLESS Non-TLS : $uuid4"
echo "Mot de passe Trojan TLS : $uuid5"
echo "Mot de passe Trojan Non-TLS : $uuid6"
