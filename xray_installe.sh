#!/bin/bash

# Adresse email valide pour Let’s Encrypt
EMAIL="adrienkiaje@gmail.com"

# Demander uniquement le nom de domaine
read -rp "Entrez votre nom de domaine (ex: monsite.com) : " DOMAIN
if [ -z "$DOMAIN" ]; then
  echo "Erreur : nom de domaine non valide."
  exit 1
fi

# Sauvegarder le domaine pour usage dans menu ou autre script
echo "$DOMAIN" > /tmp/.xray_domain

# UUID fixe (à modifier si besoin)
UUID="b8a5dc8a-f4b7-4bc6-9848-5c80a310b6ae"
TROJAN_PASS=$(openssl rand -base64 16)

# Mise à jour & installation des dépendances
apt update && apt install -y curl unzip sudo socat snapd

snap install core; snap refresh core
snap install --classic certbot
ln -sf /snap/bin/certbot /usr/bin/certbot

# Stop services pouvant utiliser le port 80
systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true

# Obtention du certificat Let's Encrypt
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

# Gestion des permissions pour que Xray (user nobody) puisse lire les certificats
groupadd -f xray
usermod -aG xray nobody

chgrp -R xray /etc/letsencrypt/live /etc/letsencrypt/archive /etc/letsencrypt/renewal
chmod 750 /etc/letsencrypt/live/"$DOMAIN"
chmod 750 /etc/letsencrypt/archive/"$DOMAIN"
chmod 640 /etc/letsencrypt/live/"$DOMAIN"/* /etc/letsencrypt/archive/"$DOMAIN"/*
chmod 755 /etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/archive

# Installer Xray version 1.8.0 explicitement
echo "Téléchargement et installation de Xray version 1.8.0 (2023)..."
wget -q https://github.com/XTLS/Xray-core/releases/download/v1.8.0/Xray-linux-64.zip -O /tmp/xray.zip
unzip -o /tmp/xray.zip -d /tmp/xray
mv /tmp/xray/xray /usr/local/bin/xray
chmod +x /usr/local/bin/xray
rm -rf /tmp/xray /tmp/xray.zip

# Configuration XRAY
mkdir -p /usr/local/etc/xray
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
        "clients": [ { "id": "$UUID", "flow": "xtls-rprx-vision" } ],
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

systemctl restart xray

# Installation et planification du renouvellement automatique
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
echo "Assure-toi d'ouvrir les ports 80 et 443."
