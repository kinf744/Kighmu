#!/bin/bash
# Installation complète Xray - 2 ports optimisés (TLS + Non-TLS)
# Auteur : Adrien Kiaje (Optimisé par GPT-5)
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

# --- Domaine ---
read -rp "Entrez votre nom de domaine (ex: monsite.com) : " DOMAIN
if [[ -z "$DOMAIN" ]]; then
  log "${RED}" "Erreur : nom de domaine non valide."
  exit 1
fi
EMAIL="adrienkiaje@gmail.com"

# --- Installation dépendances ---
log "${GREEN}" "Mise à jour du système et installation des dépendances..."
apt update && apt install -y ufw curl socat xz-utils wget unzip jq bash-completion systemd-timesyncd ntpdate

# --- Pare-feu ---
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 89/tcp
ufw allow 8443/tcp
echo "y" | ufw enable
ufw status verbose

# --- Synchronisation horaire ---
systemctl enable systemd-timesyncd --now
systemctl restart systemd-timesyncd
timedatectl set-ntp true

# --- Téléchargement Xray ---
latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep tag_name | sed -E 's/.*"v(.*)".*/\1/' | head -n1)
log "${GREEN}" "Téléchargement de Xray-core v${latest_version}..."
cd /tmp && curl -sL "https://github.com/XTLS/Xray-core/releases/download/v${latest_version}/xray-linux-64.zip" -o xray.zip
unzip -q xray.zip && rm -f xray.zip
mv xray /usr/local/bin/xray && chmod +x /usr/local/bin/xray
setcap 'cap_net_bind_service=+ep' /usr/local/bin/xray

mkdir -p /etc/xray /var/log/xray
touch /var/log/xray/{access.log,error.log}
chmod 644 /var/log/xray/*

# --- Installation acme.sh et certificats ---
if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
  log "${GREEN}" "Installation d'acme.sh..."
  curl https://get.acme.sh | sh
  source ~/.bashrc
fi

~/.acme.sh/acme.sh --register-account -m "$EMAIL" || true
~/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN" --force
sleep 3
~/.acme.sh/acme.sh --installcert -d "$DOMAIN" \
  --fullchainpath /etc/xray/xray.crt \
  --keypath /etc/xray/xray.key

# --- Génération UUID ---
uuid_vmess_tls=$(uuidgen)
uuid_vmess_ntls=$(uuidgen)
uuid_vless_tls=$(uuidgen)
uuid_vless_ntls=$(uuidgen)
uuid_trojan_tls=$(uuidgen)
uuid_trojan_ntls=$(uuidgen)

# --- Configuration Xray (2 ports : 8443 TLS / 89 Non-TLS) ---
cat > /etc/xray/config.json << EOF
{
  "log": { "access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log", "loglevel": "info" },
  "inbounds": [
    {
      "port": 8443,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "$uuid_vless_tls", "email": "vless_tls@$DOMAIN" }],
        "decryption": "none",
        "fallbacks": [
          { "name": "vmess", "path": "/vmess", "dest": 14443, "xver": 1 },
          { "name": "trojan", "path": "/trojan", "dest": 24443, "xver": 1 }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [{ "certificateFile": "/etc/xray/xray.crt", "keyFile": "/etc/xray/xray.key" }]
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 14443,
      "protocol": "vmess",
      "settings": { "clients": [{ "id": "$uuid_vmess_tls", "alterId": 0, "email": "vmess_tls@$DOMAIN" }] },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "/vmess", "headers": { "Host": "$DOMAIN" } }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 24443,
      "protocol": "trojan",
      "settings": { "clients": [{ "password": "$uuid_trojan_tls", "email": "trojan_tls@$DOMAIN" }] },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "/trojan", "headers": { "Host": "$DOMAIN" } }
      }
    },
    {
      "port": 89,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "$uuid_vless_ntls", "email": "vless_ntls@$DOMAIN" }],
        "decryption": "none",
        "fallbacks": [
          { "name": "vmess", "path": "/vmess", "dest": 1889, "xver": 1 },
          { "name": "trojan", "path": "/trojan", "dest": 2889, "xver": 1 }
        ]
      },
      "streamSettings": { "network": "tcp", "security": "none" }
    },
    {
      "listen": "127.0.0.1",
      "port": 1889,
      "protocol": "vmess",
      "settings": { "clients": [{ "id": "$uuid_vmess_ntls", "alterId": 0, "email": "vmess_ntls@$DOMAIN" }] },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "/vmess", "headers": { "Host": "$DOMAIN" } }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 2889,
      "protocol": "trojan",
      "settings": { "clients": [{ "password": "$uuid_trojan_ntls", "email": "trojan_ntls@$DOMAIN" }] },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "/trojan", "headers": { "Host": "$DOMAIN" } }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": {} },
    { "protocol": "blackhole", "settings": {}, "tag": "blocked" }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10",
          "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16",
          "::1/128", "fc00::/7", "fe80::/10"
        ],
        "outboundTag": "blocked"
      }
    ]
  }
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
  log "${RED}" "❌ Erreur : Xray ne démarre pas. Consultez : journalctl -u xray -e"
  exit 1
fi

# --- Résumé ---
log "${GREEN}" "🎉 Installation complète terminée."
log "${GREEN}" "🌐 Domaine : $DOMAIN"
log "${GREEN}" "🔹 VMess TLS UUID : $uuid_vmess_tls"
log "${GREEN}" "🔹 VMess Non-TLS UUID : $uuid_vmess_ntls"
log "${GREEN}" "🔹 VLESS TLS UUID : $uuid_vless_tls"
log "${GREEN}" "🔹 VLESS Non-TLS UUID : $uuid_vless_ntls"
log "${GREEN}" "🔹 Trojan TLS Pass : $uuid_trojan_tls"
log "${GREEN}" "🔹 Trojan Non-TLS Pass : $uuid_trojan_ntls"
log "${GREEN}" "🔸 Ports : TLS (8443) / Non-TLS (89)"
EOF
