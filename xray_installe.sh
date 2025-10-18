#!/bin/bash
# Installation complète Xray + UFW, démarrage robuste via systemd
# Synchronisation horaire gérée avec systemd-timesyncd (Ubuntu 24.04)
# Script prêt pour publication GitHub

# Couleurs terminal
RED='\u001B[0;31m'
GREEN='\u001B[0;32m'
NC='\u001B[0m'

set -euo pipefail

log() { echo -e "${1}${2}${NC}"; }

log "${GREEN}" "Début de l'installation Xray avec systemd robuste"

clean_xray_environment() {
  log "${GREEN}" "Nettoyage préalable de l'environnement Xray..."
  systemctl stop xray 2>/dev/null || true
  systemctl disable xray 2>/dev/null || true
  pkill -f "/usr/local/bin/xray" 2>/dev/null || true
  rm -rf /etc/xray /var/log/xray /usr/local/bin/xray /tmp/.xray_domain /etc/systemd/system/xray.service 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
  log "${GREEN}" "Nettoyage pré-installation terminé."
}

clean_xray_environment

read -rp "Entrez votre nom de domaine (ex: monsite.com) : " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  log "${RED}" "Erreur : nom de domaine non valide."
  exit 1
fi

echo "$DOMAIN" > /tmp/.xray_domain
EMAIL="adrienkiaje@gmail.com"

log "${GREEN}" "Mise à jour du système et installation des dépendances..."
apt update

# Suppression d'iptables-persistent et netfilter-persistent pour éviter conflit avec ufw
if dpkg -l | grep -q iptables-persistent; then
  log "${GREEN}" "Suppression de iptables-persistent et netfilter-persistent pour éviter conflit avec ufw..."
  apt purge -y iptables-persistent netfilter-persistent
  apt autoremove -y
fi

apt install -y ufw iptables curl socat xz-utils wget apt-transport-https \
  gnupg gnupg2 gnupg1 dnsutils lsb-release cron bash-completion ntpdate systemd-timesyncd unzip jq systemd

# Configuration UFW uniquement
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 89/tcp
ufw allow 89/udp
ufw allow 8443/tcp
ufw allow 8443/udp
echo "y" | ufw enable
ufw status verbose

# Synchronisation horaire avec systemd-timesyncd
log "${GREEN}" "Activation et démarrage de systemd-timesyncd..."
systemctl enable systemd-timesyncd --now

log "${GREEN}" "Désactivation de chronyd si présent pour éviter conflit..."
systemctl disable chronyd --now 2>/dev/null || true
systemctl stop chronyd 2>/dev/null || true

log "${GREEN}" "Vérification du statut de systemd-timesyncd..."
timedatectl status

log "${GREEN}" "Configuration des serveurs NTP dans /etc/systemd/timesyncd.conf..."
cat << EOF >/etc/systemd/timesyncd.conf
[Time]
NTP=2.ubuntu.pool.ntp.org 3.ubuntu.pool.ntp.org 1.ubuntu.pool.ntp.org
FallbackNTP=ntp.ubuntu.com
EOF

systemctl restart systemd-timesyncd

timedatectl status

date

# Télécharger dernière version Xray
log "${GREEN}" "Récupération de la dernière version Xray..."
latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep tag_name | sed -E 's/.*"v([^"]+)".*/\u0001/' | head -n1)
xraycore_link="https://github.com/XTLS/Xray-core/releases/download/v${latest_version}/Xray-linux-64.zip"
curl -sL "$xraycore_link" -o xray.zip

if [ ! -s xray.zip ]; then
  echo "Erreur : téléchargement du fichier Xray a échoué."
  exit 1
fi

unzip -q xray.zip || { echo "Erreur: extraction du ZIP Xray a échoué." ; exit 1 ; }
mv xray /usr/local/bin/xray
chmod +x /usr/local/bin/xray
setcap 'cap_net_bind_service=+ep' /usr/local/bin/xray

mkdir -p /var/log/xray /etc/xray
touch /var/log/xray/access.log /var/log/xray/error.log
chmod 644 /var/log/xray/access.log /var/log/xray/error.log

if ! command -v ~/.acme.sh/acme.sh &> /dev/null; then
  log "${GREEN}" "Installation d'acme.sh..."
  curl https://get.acme.sh | sh
  source ~/.bashrc
fi

~/.acme.sh/acme.sh --register-account -m "$EMAIL"
~/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN" --force
sleep 5
~/.acme.sh/acme.sh --installcert -d "$DOMAIN" --fullchainpath /etc/xray/xray.crt --keypath /etc/xray/xray.key

if [[ ! -f "/etc/xray/xray.crt" || ! -f "/etc/xray/xray.key" ]]; then
  log "${RED}" "Erreur : certificats TLS non trouvés."
  exit 1
fi

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
  "outbounds": [{"protocol": "freedom","settings": {}}]
}
EOF

log "${GREEN}" "Création du fichier service systemd Xray..."
cat > /etc/systemd/system/xray.service << 'EOF'
[Unit]
Description=Xray Core Service
After=network-online.target
Wants=network-online.target

[Service]
User=root
Group=root
WorkingDirectory=/etc/xray
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5s
RuntimeMaxSec=0
LimitNOFILE=100000
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
StandardOutput=journal
StandardError=journal
SyslogIdentifier=xray

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray

log "${GREEN}" "Démarrage du service Xray..."
systemctl start xray

if systemctl is-active --quiet xray; then
  log "${GREEN}" "Xray démarre correctement via systemd."
else
  log "${RED}" "Erreur: Xray ne démarre pas via systemd. Veuillez vérifier les logs."
  journalctl -u xray -n 100 --no-pager
  exit 1
fi

log "${GREEN}" "Installation complète terminée."
log "${GREEN}" "Domaine : $DOMAIN"
log "${GREEN}" "UUID VMess TLS : $uuid1"
log "${GREEN}" "UUID VMess Non-TLS : $uuid2"
log "${GREEN}" "UUID VLESS TLS : $uuid3"
log "${GREEN}" "UUID VLESS Non-TLS : $uuid4"
log "${GREEN}" "Mot de passe Trojan TLS : $uuid5"
log "${GREEN}" "Mot de passe Trojan Non-TLS : $uuid6"
