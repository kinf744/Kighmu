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

# --- Dépendances et pare-feu ---
apt update
apt install -y ufw curl socat xz-utils wget unzip jq bash-completion systemd-timesyncd ntpdate
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 89/tcp
ufw allow 8443/tcp
echo "y" | ufw enable

# --- Synchronisation horaire ---
systemctl enable systemd-timesyncd --now
systemctl restart systemd-timesyncd

# --- Télécharger et installer Xray ---
latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep tag_name | sed -E 's/.*"v(.*)".*/\1/' | head -n1)
curl -sL "https://github.com/XTLS/Xray-core/releases/download/v${latest_version}/xray-linux-64.zip" -o /tmp/xray.zip
unzip -q /tmp/xray.zip -d /tmp && rm -f /tmp/xray.zip
mv /tmp/xray /usr/local/bin/xray
chmod +x /usr/local/bin/xray
setcap 'cap_net_bind_service=+ep' /usr/local/bin/xray

mkdir -p /etc/xray /var/log/xray
touch /var/log/xray/{access.log,error.log}
chmod 644 /var/log/xray/*

# --- Certificats TLS via acme.sh ---
if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
  curl https://get.acme.sh | sh
  source ~/.bashrc
fi
~/.acme.sh/acme.sh --register-account -m "$EMAIL" || true
~/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN" --force
~/.acme.sh/acme.sh --installcert -d "$DOMAIN" --fullchainpath /etc/xray/xray.crt --keypath /etc/xray/xray.key

# --- Génération UUID ---
uuid_vmess_tls=$(uuidgen)
uuid_vmess_ntls=$(uuidgen)
uuid_vless_tls=$(uuidgen)
uuid_vless_ntls=$(uuidgen)
uuid_trojan_tls=$(uuidgen)
uuid_trojan_ntls=$(uuidgen)

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
