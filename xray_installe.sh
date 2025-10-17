#!/bin/bash
# Installation complète Xray + UFW, nettoyage avant installation, services systemd robustes
# Version prête pour GitHub avec commentaires en français et sans changement des ports
# A utiliser sur Ubuntu 20.04/24.04

set -euo pipefail

# Couleurs terminal
RED='\u001B[0;31m'
GREEN='\u001B[0;32m'
NC='\u001B[0m'

log() {
  local level="$1"
  shift
  echo -e "${GREEN}[${level}]${NC} $*"
}

err() {
  log "ERREUR" "$@"
  exit 1
}

warn() {
  log "WARN" "$@"
}

info() {
  log "INFO" "$@"
}

# Nettoyage précédent avant installation
info "Arrêt des services utilisant les ports 80 et 8443..."
for port in 80 8443; do
  if command -v lsof >/dev/null 2>&1; then
    lsof -i tcp:$port -t 2>/dev/null | xargs -r kill -9
    lsof -i udp:$port -t 2>/dev/null | xargs -r kill -9
  else
    # fallback: tenter de tuer via netstat/ss si lsof absent
    if command -v ss >/dev/null 2>&1; then
      ss -ltnp | grep ":$port" | awk '{print $1}' >/dev/null 2>&1 || true
    fi
  fi
done

# Arrêter et désactiver les services potentiellement en conflit
for srv in xray nginx apache2; do
  if systemctl is-active --quiet "$srv"; then
    systemctl stop "$srv" || true
  fi
  if systemctl is-enabled --quiet "$srv"; then
    systemctl disable "$srv" || true
  fi
done

info "Nettoyage des fichiers précédents..."
rm -rf /etc/xray /var/log/xray /usr/local/bin/xray /tmp/.xray_domain /etc/systemd/system/xray.service

systemctl daemon-reload

# Demander domaine
read -rp "Entrez votre nom de domaine (ex: monsite.com) : " DOMAIN
if [[ -z "${DOMAIN:-}" ]]; then
  err "Erreur : nom de domaine non valide."
fi

# Écriture domaine pour menu
echo "$DOMAIN" > /tmp/.xray_domain

EMAIL="adrienkiaje@gmail.com"

# Mise à jour et dépendances
info "Mise à jour du système et installation des dépendances..."
apt-get update
APT_PKGS=(
  ufw iptables iptables-persistent curl socat xz-utils wget \
  apt-transport-https gnupg dnsutils lsb-release cron bash-completion \
  ntpdate chrony unzip jq
)
apt-get install -y "${APT_PKGS[@]}" || err "Échec lors de l'installation des dépendances"

# Configuration UFW - ouvrir uniquement SSH, 80, 8443
info "Configuration du pare-feu (UFW)..."
ufw --force disable 2>/dev/null || true
ufw --force enable 2>/dev/null || true
ufw allow ssh
ufw allow 80/tcp
ufw allow 80/udp
ufw allow 8443/tcp
ufw allow 8443/udp
ufw --force reload

# Vérifier que netfilter-persistent et ntpdate existent et installer fallback si nécessaire
if ! command -v netfilter-persistent >/dev/null 2>&1; then
  apt-get install -y netfilter-persistent || warn "netfilter-persistent non installable; persistance du pare-feu pourrait être limitée"
fi
if ! command -v ntpdate >/dev/null 2>&1; then
  apt-get install -y ntpdate || warn "ntpdate non installable; synchronisation horaire manuelle possible"
fi

# Sauvegarder règles UFW pour persistance
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save || warn "Échec de la sauvegarde netfilter-persistent"
fi

# Synchronisation temps
if command -v ntpdate >/dev/null 2>&1; then
  ntpdate pool.ntp.org
fi
timedatectl set-ntp true || true
systemctl enable chronyd || true
systemctl restart chronyd || true
timedatectl set-timezone Asia/Kuala_Lumpur || true

# Info chrony
if command -v chronyc >/dev/null 2>&1; then
  chronyc tracking -v || true
  date
fi

# Dernière version Xray
latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep -Po '"tag_name": "K.*?(?=")' | head -n1)
if [[ -z "$latest_version" ]]; then
  err "Impossible de récupérer la version Xray."
fi
xraycore_link="https://github.com/XTLS/Xray-core/releases/download/v${latest_version}/xray-linux-64.zip"

# Arrêt services sur port 80 existants (sécuritaire)
systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true
lsof -t -i tcp:80 -s tcp:listen 2>/dev/null | xargs -r kill -9 || true

# Installation Xray
info "Installation Xray..."
mkdir -p /usr/local/bin
cd "$(mktemp -d)"
curl -sL "$xraycore_link" -o xray.zip
unzip -q xray.zip -d xray_extracted
if [[ ! -f "xray_extracted/xray" && ! -f "xray_extracted/*/xray" ]]; then
  err "Échec during unzip; Xray binary missing"
fi
# Trouver le binaire dans le répertoire extrait
XrayBin=$(find xray_extracted -name "xray" -type f | head -n1)
if [[ -z "$XrayBin" ]]; then
  err "Impossible de localiser le binaire Xray après extraction"
fi
mv "$XrayBin" /usr/local/bin/xray
chmod +x /usr/local/bin/xray
setcap 'cap_net_bind_service=+ep' /usr/local/bin/xray || true
# Déplacer le reste des fichiers sous /etc/xray
mkdir -p /etc/xray /var/log/xray
# Journaux et permissions
touch /var/log/xray/access.log /var/log/xray/error.log
chown -R root:root /var/log/xray /etc/xray || true
chmod 644 /var/log/xray/access.log /var/log/xray/error.log || true
rm -rf xray.zip xray_extracted

# Installer acme.sh si pas présent
if ! command -v ~/.acme.sh/acme.sh &> /dev/null; then
  info "Installation d'acme.sh..."
  curl https://get.acme.sh | sh
  source ~/.bashrc
fi

# Arrêter Xray avant génération certificat pour libérer port (safe)
systemctl stop xray 2>/dev/null || true

# Générer et installer certificat TLS
~/.acme.sh/acme.sh --register-account -m "$EMAIL" || true
~/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN" --force || true
~/.acme.sh/acme.sh --installcert -d "$DOMAIN" --fullchainpath /etc/xray/xray.crt --keypath /etc/xray/xray.key || true

# Vérifier certificats TLS
if [[ ! -f "/etc/xray/xray.crt" || ! -f "/etc/xray/xray.key" ]]; then
  warn "Certificats TLS non trouvés ou non installés; configuration TLS pourrait échouer."
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
  "trojan_pass": "$uuid5",
  "trojan_ntls_pass": "$uuid6"
}
EOF

# Configuration Xray complète
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

# Reload systemd et activer/démarrer le service
systemctl daemon-reload
systemctl enable xray
systemctl restart xray || true

# Vérification du démarrage
if systemctl is-active --quiet xray; then
  info "Xray démarré avec succès."
else
  err "Erreur : Xray ne démarre pas."
  journalctl -u xray -n 50 --no-pager
  exit 1
fi

info "Installation complète terminée."
echo "Domaine : $DOMAIN"
echo "UUID VMess TLS : $uuid1"
echo "UUID VMess Non-TLS : $uuid2"
echo "UUID VLESS TLS : $uuid3"
echo "UUID VLESS Non-TLS : $uuid4"
