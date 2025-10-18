#!/bin/bash
# Mod By NevermoreSSH
# Installation Xray minimaliste style NevermoreSSH
# =====================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

set -euo pipefail

log() { echo -e "${1}${2}${NC}"; }

log "${GREEN}" "Début de l'installation Xray façon NevermoreSSH"

# Nettoyage Xray
systemctl stop xray 2>/dev/null || true
systemctl disable xray 2>/dev/null || true
pkill -f "/usr/local/bin/xray" 2>/dev/null || true
rm -rf /etc/xray /var/log/xray /usr/local/bin/xray /tmp/.xray_domain /etc/systemd/system/xray.service 2>/dev/null || true
systemctl daemon-reload 2>/dev/null || true

# Domaine
read -rp "Entrez votre nom de domaine : " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  log "${RED}" "Nom de domaine non valide."
  exit 1
fi
echo "$DOMAIN" > /tmp/.xray_domain
EMAIL="adrienkiaje@gmail.com"

# Dépendances
apt update
apt install -y curl socat xz-utils wget unzip jq systemd iptables iptables-persistent cron bash-completion ntpdate

# Synchronisation horaire
timedatectl set-ntp true
ntpdate pool.ntp.org
timedatectl set-timezone Asia/Kuala_Lumpur

# Téléchargement Xray
latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep tag_name | sed -E 's/.*"v(.*)".*/\1/' | head -n1)
xraycore_link="https://github.com/XTLS/Xray-core/releases/download/v${latest_version}/xray-linux-64.zip"

mkdir -p /usr/local/bin
cd $(mktemp -d)
curl -sL "$xraycore_link" -o xray.zip
unzip -q xray.zip && rm -f xray.zip
mv xray /usr/local/bin/xray
chmod +x /usr/local/bin/xray
setcap 'cap_net_bind_service=+ep' /usr/local/bin/xray

# Dossiers logs et config
mkdir -p /var/log/xray /etc/xray
touch /var/log/xray/access.log /var/log/xray/error.log
chmod 644 /var/log/xray/*.log

# Certificat TLS via acme.sh
if ! command -v ~/.acme.sh/acme.sh &> /dev/null; then
  curl https://get.acme.sh | sh
  source ~/.bashrc
fi
~/.acme.sh/acme.sh --register-account -m "$EMAIL"
~/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN" --force
~/.acme.sh/acme.sh --installcert -d "$DOMAIN" --fullchainpath /etc/xray/xray.crt --keypath /etc/xray/xray.key

if [[ ! -f "/etc/xray/xray.crt" || ! -f "/etc/xray/xray.key" ]]; then
  log "${RED}" "Certificat TLS introuvable."
  exit 1
fi

# UUID
uuid1=$(cat /proc/sys/kernel/random/uuid)
uuid2=$(cat /proc/sys/kernel/random/uuid)
uuid3=$(cat /proc/sys/kernel/random/uuid)
uuid4=$(cat /proc/sys/kernel/random/uuid)
uuid5=$(cat /proc/sys/kernel/random/uuid)
uuid6=$(cat /proc/sys/kernel/random/uuid)

# Config Xray
cat > /etc/xray/config.json << EOF
{
  "log": {"access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log", "loglevel": "info"},
  "inbounds": [
    {"port":8443,"protocol":"vmess","settings":{"clients":[{"id":"$uuid1","alterId":0}]},"streamSettings":{"network":"ws","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"/etc/xray/xray.crt","keyFile":"/etc/xray/xray.key"}]},"wsSettings":{"path":"/vmess","headers":{"Host":"$DOMAIN"}}}},
    {"port":89,"protocol":"vmess","settings":{"clients":[{"id":"$uuid2","alterId":0}]},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/vmess","headers":{"Host":"$DOMAIN"}}},"sniffing":{"enabled":true,"destOverride":["http","tls"]}},
    {"port":8443,"protocol":"vless","settings":{"clients":[{"id":"$uuid3"}],"decryption":"none"},"streamSettings":{"network":"ws","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"/etc/xray/xray.crt","keyFile":"/etc/xray/xray.key"}]},"wsSettings":{"path":"/vless","headers":{"Host":"$DOMAIN"}}},"sniffing":{"enabled":true,"destOverride":["http","tls"]}},
    {"port":89,"protocol":"vless","settings":{"clients":[{"id":"$uuid4"}],"decryption":"none"},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/vless","headers":{"Host":"$DOMAIN"}}},"sniffing":{"enabled":true,"destOverride":["http","tls"]}},
    {"port":8443,"protocol":"trojan","settings":{"clients":[{"password":"$uuid5"}]},"streamSettings":{"network":"ws","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"/etc/xray/xray.crt","keyFile":"/etc/xray/xray.key"}]},"wsSettings":{"path":"/trojanws","headers":{"Host":"$DOMAIN"}}}},
    {"port":89,"protocol":"trojan","settings":{"clients":[{"password":"$uuid6"}]},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/trojanws","headers":{"Host":"$DOMAIN"}}}}
  ],
  "outbounds":[{"protocol":"freedom","settings":{}},{"protocol":"blackhole","settings":{},"tag":"blocked"}],
  "routing":{"rules":[{"type":"field","ip":["0.0.0.0/8","10.0.0.0/8","100.64.0.0/10","169.254.0.0/16","172.16.0.0/12","192.0.0.0/24","192.0.2.0/24","192.168.0.0/16","198.18.0.0/15","198.51.100.0/24","203.0.113.0/24","::1/128","fc00::/7","fe80::/10"],"outboundTag":"blocked"}]},
  "policy":{"levels":{"0":{"statsUserDownlink":true,"statsUserUplink":true}},"system":{"statsInboundUplink":true,"statsInboundDownlink":true}},
  "stats":{},
  "api":{"services":["StatsService"],"tag":"api"}
}
EOF

# Service systemd
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

# Ports via iptables
iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport 8443 -j ACCEPT
iptables -I INPUT -m state --state NEW -m udp -p udp --dport 8443 -j ACCEPT
iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport 89 -j ACCEPT
iptables -I INPUT -m state --state NEW -m udp -p udp --dport 89 -j ACCEPT
iptables-save > /etc/iptables.up.rules
iptables-restore -t < /etc/iptables.up.rules
netfilter-persistent save
netfilter-persistent reload

# Start Xray
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

if systemctl is-active --quiet xray; then
  echo -e "${GREEN}Xray démarré avec succès.${NC}"
else
  echo -e "${RED}Erreur : Xray ne démarre pas.${NC}"
  journalctl -u xray -n 20 --no-pager
  exit 1
fi

log "${GREEN}" "Installation terminée !"
log "${GREEN}" "Domaine : $DOMAIN"
log "${GREEN}" "UUID VMess TLS : $uuid1"
log "${GREEN}" "UUID VMess Non-TLS : $uuid2"
log "${GREEN}" "UUID VLESS TLS : $uuid3"
log "${GREEN}" "UUID VLESS Non-TLS : $uuid4"
log "${GREEN}" "Mot de passe Trojan TLS : $uuid5"
log "${GREEN}" "Mot de passe Trojan Non-TLS : $uuid6"
