#!/bin/bash

EMAIL="adrienkiaje@gmail.com"

read -rp "Entrez votre nom de domaine (ex: monsite.com) : " DOMAIN
if [ -z "$DOMAIN" ]; then
  echo "Erreur : nom de domaine non valide."
  exit 1
fi

echo "$DOMAIN" > /tmp/.xray_domain

UUID="b8a5dc8a-f4b7-4bc6-9848-5c80a310b6ae"
TROJAN_PASS=$(openssl rand -base64 16)

echo "Mise à jour et installation dépendances..."
apt update && apt install -y curl unzip sudo socat snapd || { echo "Erreur installation dépendances"; exit 1; }

echo "Installation et configuration de snap..."
snap install core || { echo "Erreur installation snap core"; exit 1; }
snap refresh core || true
snap install --classic certbot || { echo "Erreur installation certbot"; exit 1; }
ln -sf /snap/bin/certbot /usr/bin/certbot

echo "Arrêt des services nginx/apache2 pour libérer le port 80..."
systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true

echo "Obtention du certificat TLS Let's Encrypt..."
certbot certonly --standalone --non-interactive --agree-tos --email "$EMAIL" -d "$DOMAIN"
if [ $? -ne 0 ]; then
  echo "❌ Erreur lors de la génération du certificat TLS."
  exit 1
fi

CRT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
if [[ ! -f "$CRT_PATH" ]] || [[ ! -f "$KEY_PATH" ]]; then
  echo "Erreur : certificats TLS non trouvés."
  exit 1
fi

echo "Gestion des permissions pour l'utilisateur nobody..."
groupadd -f xray
usermod -aG xray nobody
chgrp -R xray /etc/letsencrypt/live /etc/letsencrypt/archive /etc/letsencrypt/renewal
chmod 750 /etc/letsencrypt/live/"$DOMAIN" /etc/letsencrypt/archive/"$DOMAIN"
chmod 640 /etc/letsencrypt/live/"$DOMAIN"/* /etc/letsencrypt/archive/"$DOMAIN"/*
chmod 755 /etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/archive

echo "Téléchargement et installation de Xray 1.8.0..."
wget -q https://github.com/XTLS/Xray-core/releases/download/v1.8.0/Xray-linux-64.zip -O /tmp/xray.zip || { echo "Erreur téléchargement Xray"; exit 1; }
unzip -o /tmp/xray.zip -d /tmp/xray || { echo "Erreur extraction Xray"; exit 1; }
mv /tmp/xray/xray /usr/local/bin/xray
chmod +x /usr/local/bin/xray
rm -rf /tmp/xray /tmp/xray.zip

echo "Création du dossier de configuration Xray..."
mkdir -p /usr/local/etc/xray

echo "Création du fichier de configuration..."
cat > /usr/local/etc/xray/config.json << EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "debug"
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "$UUID", "flow": "xtls-rprx-vision" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": { "certificates": [ { "certificateFile": "$CRT_PATH", "keyFile": "$KEY_PATH" } ] },
        "wsSettings": { "path": "/vlessws" }
      }
    },
    {
      "port": 80,
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "$UUID" } ],
        "decryption": "none"
      },
      "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "/vlessws" } }
    },
    {
      "port": 443,
      "protocol": "vmess",
      "settings": { "clients": [ { "id": "$UUID", "alterId": 0 } ] },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": { "certificates": [ { "certificateFile": "$CRT_PATH", "keyFile": "$KEY_PATH" } ] },
        "wsSettings": { "path": "/vmessws" }
      }
    },
    {
      "port": 80,
      "protocol": "vmess",
      "settings": { "clients": [ { "id": "$UUID", "alterId": 0 } ] },
      "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "/vmessws" } }
    },
    {
      "port": 443,
      "protocol": "trojan",
      "settings": { "clients": [ { "password": "$TROJAN_PASS" } ] },
      "streamSettings": {
        "network": "grpc",
        "security": "tls",
        "tlsSettings": { "certificates": [ { "certificateFile": "$CRT_PATH", "keyFile": "$KEY_PATH" } ] },
        "grpcSettings": { "serviceName": "trojan-grpc" }
      }
    },
    {
      "port": 443,
      "protocol": "vless",
      "settings": { "clients": [ { "id": "$UUID" } ], "decryption": "none" },
      "streamSettings": {
        "network": "grpc",
        "security": "tls",
        "tlsSettings": { "certificates": [ { "certificateFile": "$CRT_PATH", "keyFile": "$KEY_PATH" } ] },
        "grpcSettings": { "serviceName": "vless-grpc" }
      }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "settings": {} } ]
}
EOF

# Création fichier de service systemd pour Xray
cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/xray -config /usr/local/etc/xray/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "Recharge systemd et active le service Xray..."
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

if systemctl is-active --quiet xray; then
  echo "Xray service démarré avec succès."
else
  echo "Erreur : le service Xray ne démarre pas."
  journalctl -u xray -n 20 --no-pager
  exit 1
fi

# Script renouvellement automatique Certbot + Restart Xray
cat > /usr/local/bin/renew-cert-xray.sh << 'EOS'
#!/bin/bash
certbot renew --quiet --post-hook "systemctl restart xray"
EOS
chmod +x /usr/local/bin/renew-cert-xray.sh
(crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/renew-cert-xray.sh") | crontab -

echo "----- XRAY v1.8.0 installé avec TLS Let’s Encrypt et renouvellement automatique -----"
echo "Domaine : $DOMAIN"
echo "UUID : $UUID"
echo "Mot de passe Trojan (gRPC) : $TROJAN_PASS"
echo "Certificats TLS :"
echo "  Certificat : $CRT_PATH"
echo "  Clé privée : $KEY_PATH"
echo "Ports : 80 (ws sans TLS), 443 (ws TLS, grpc TLS)"
echo ""
echo "Assure-toi d'ouvrir les ports 80 et 443 dans le firewall."
