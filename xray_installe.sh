#!/bin/bash

# Adresse email valide pour Let’s Encrypt
EMAIL="adrienkiaje@gmail.com"

# Demander uniquement le nom de domaine
read -rp "Entrez votre nom de domaine (ex: monsite.com) : " DOMAIN
if [ -z "$DOMAIN" ]; then
  echo "Erreur : nom de domaine non valide."
  exit 1
fi

# Sauvegarder le domaine dans un fichier temporaire pour menu_6.sh
echo "$DOMAIN" > /tmp/.xray_domain

# UUID fixe (à modifier si besoin pour générer dynamiquement)
UUID="b8a5dc8a-f4b7-4bc6-9848-5c80a310b6ae"
TROJAN_PASS=$(openssl rand -base64 16)

# Mise à jour & prérequis
apt update && apt install -y curl unzip sudo socat snapd

# Installer snapd et certbot
snap install core; snap refresh core
snap install --classic certbot
ln -sf /snap/bin/certbot /usr/bin/certbot

# Stop services pouvant utiliser le port 80
systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true

# Obtenir certificat Let's Encrypt via certbot (standalone)
certbot certonly --standalone --non-interactive --agree-tos --email "$EMAIL" -d "$DOMAIN"
if [ $? -ne 0 ]; then
  echo "❌ Erreur lors de la génération du certificat TLS. Vérifie ton email et ta configuration de domaine."
  exit 1
fi

CRT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

if [[ ! -f "$CRT_PATH" ]] || [[ ! -f "$KEY_PATH" ]]; then
  echo "Erreur : certificats TLS non trouvés."
  exit 1
fi

# Installer Xray
bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh)

mkdir -p /usr/local/etc/xray
cat > /usr/local/etc/xray/config.json << EOF
{
  "log": { "loglevel": "info" },
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
      "settings": {
        "clients": [ { "id": "$UUID", "alterId": 0 } ]
      },
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
      "settings": {
        "clients": [ { "id": "$UUID", "alterId": 0 } ]
      },
      "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "/vmessws" } }
    },
    {
      "port": 443,
      "protocol": "trojan",
      "settings": {
        "clients": [ { "password": "$TROJAN_PASS" } ]
      },
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
      "settings": {
        "clients": [ { "id": "$UUID" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "security": "tls",
        "tlsSettings": { "certificates": [ { "certificateFile": "$CRT_PATH", "keyFile": "$KEY_PATH" } ] },
        "grpcSettings": { "serviceName": "vless-grpc" }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom", "settings": {} }]
}
EOF

systemctl restart xray

cat > /usr/local/bin/renew-cert-xray.sh << 'EOS'
#!/bin/bash
certbot renew --quiet --post-hook "systemctl restart xray"
EOS

chmod +x /usr/local/bin/renew-cert-xray.sh

(crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/renew-cert-xray.sh") | crontab -

echo "----- XRAY installé avec TLS Let’s Encrypt et renouvellement automatique -----"
echo "Domaine : $DOMAIN"
echo "UUID utilisé partout : $UUID"
echo "Mot de passe Trojan (gRPC) : $TROJAN_PASS"
echo "Certificats TLS :"
echo "  Certificat : $CRT_PATH"
echo "  Clé privée : $KEY_PATH"
echo "Ports : 80 (ws sans TLS), 443 (ws TLS, grpc TLS)"
echo ""
echo "Assure-toi d'ouvrir les ports 80 et 443 dans ton firewall."
echo "Le script renew-cert-xray.sh sera exécuté quotidiennement pour renouveler automatiquement le certificat et redémarrer XRAY."
