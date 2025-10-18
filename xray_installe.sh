#!/bin/bash
# Installation complète Xray - 2 ports (TLS + Non-TLS)
# Auteur : Adrien Kiaje / Optimisé par GPT-5
# Version : 2025.10
# Compatible : Ubuntu 22.04 / 24.04

RED='\u001B[0;31m'
GREEN='\u001B[0;32m'
NC='\u001B[0m'

set -euo pipefail
log() { echo -e "${1}${2}${NC}"; }

log "${GREEN}" "🚀 Début de l'installation complète de Xray"

# --- Nettoyage préalable ---
log "${GREEN}" "Nettoyage de tout ancien environnement Xray..."
systemctl stop xray 2>/dev/null || true
systemctl disable xray 2>/dev/null || true
pkill -f "/usr/local/bin/xray" 2>/dev/null || true
rm -rf /etc/xray /usr/local/bin/xray /var/log/xray /etc/systemd/system/xray.service 2>/dev/null || true
systemctl daemon-reload

# --- Domaine et email ---
read -rp "Entrez votre nom de domaine (ex: monsite.com) : " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  log "${RED}" "Erreur : nom de domaine non valide."
  exit 1
fi
EMAIL="adrienkiaje@gmail.com"

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
latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep tag_name | sed -E 's/.*"v(.*)".*/\1/' | head -n1)
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

# Installation acme.sh et certificats TLS
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

# Génération UUID
uuid1=$(cat /proc/sys/kernel/random/uuid)
uuid2=$(cat /proc/sys/kernel/random/uuid)
uuid3=$(cat /proc/sys/kernel/random/uuid)
uuid4=$(cat /proc/sys/kernel/random/uuid)
uuid5=$(cat /proc/sys/kernel/random/uuid)
uuid6=$(cat /proc/sys/kernel/random/uuid)

# --- Configuration Xray (2 ports + fallbacks) ---
cat > /etc/xray/config.json << EOF
{
  "log": {"access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log", "loglevel": "info"},
  "inbounds": [
    {
      "port": 8443,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$uuid_vless_tls"}],
        "decryption": "none",
        "fallbacks": [
          {"path": "/vmess", "dest": 1443, "xver": 1},
          {"path": "/trojanws", "dest": 2443, "xver": 1}
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {"certificates": [{"certificateFile": "/etc/xray/xray.crt", "keyFile": "/etc/xray/xray.key"}]}
      }
    },
    {
      "port": 89,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$uuid_vless_ntls"}],
        "decryption": "none",
        "fallbacks": [
          {"path": "/vmess", "dest": 1889, "xver": 1},
          {"path": "/trojanws", "dest": 2889, "xver": 1}
        ]
      },
      "streamSettings": {"network": "tcp", "security": "none"}
    },
    {
      "listen": "127.0.0.1",
      "port": 1443,
      "protocol": "vmess",
      "settings": {"clients": [{"id": "$uuid_vmess_tls"}]},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "/vmess"}}
    },
    {
      "listen": "127.0.0.1",
      "port": 2443,
      "protocol": "trojan",
      "settings": {"clients": [{"password": "$uuid_trojan_tls"}]},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "/trojanws"}}
    },
    {
      "listen": "127.0.0.1",
      "port": 1889,
      "protocol": "vmess",
      "settings": {"clients": [{"id": "$uuid_vmess_ntls"}]},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "/vmess"}}
    },
    {
      "listen": "127.0.0.1",
      "port": 2889,
      "protocol": "trojan",
      "settings": {"clients": [{"password": "$uuid_trojan_ntls"}]},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "/trojanws"}}
    }
  ],
  "outbounds": [{"protocol": "freedom","settings": {}},{"protocol": "blackhole","settings": {}, "tag": "blocked"}]
}
EOF

# --- Service systemd ---
cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Proxy Service
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=/usr/local/bin/xray -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF

# --- Démarrage ---
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

if systemctl is-active --quiet xray; then
  log "${GREEN}" "✅ Xray démarré avec succès."
else
  log "${RED}" "❌ Xray n'a pas démarré. Vérifiez : journalctl -u xray -e"
  exit 1
fi

# --- Résumé ---
log "${GREEN}" "🌐 Domaine : $DOMAIN"
log "${GREEN}" "🔹 VMess TLS UUID : $uuid_vmess_tls"
log "${GREEN}" "🔹 VMess Non-TLS UUID : $uuid_vmess_ntls"
log "${GREEN}" "🔹 VLESS TLS UUID : $uuid_vless_tls"
log "${GREEN}" "🔹 VLESS Non-TLS UUID : $uuid_vless_ntls"
log "${GREEN}" "🔹 Trojan TLS Pass : $uuid_trojan_tls"
log "${GREEN}" "🔹 Trojan Non-TLS Pass : $uuid_trojan_ntls"
log "${GREEN}" "🔸 Ports : TLS (8443) / Non-TLS (89)"
