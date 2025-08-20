#!/bin/bash

# Variable email fixe pour Let’s Encrypt (à modifier ici)
EMAIL="votre-email@example.com"

# Demander uniquement le nom de domaine
read -rp "Entrez votre nom de domaine (ex: monsite.com) : " DOMAIN

# UUID fixe
UUID="b8a5dc8a-f4b7-4bc6-9848-5c80a310b6ae"
TROJAN_PASS=$(openssl rand -base64 16)

# Mise à jour & prérequis
apt update && apt install -y curl unzip sudo socat

# Installer snapd (pour certbot)
apt install -y snapd
snap install core; snap refresh core
snap install --classic certbot
ln -sf /snap/bin/certbot /usr/bin/certbot

# Stop services pouvant utiliser le port 80
systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true

# Obtenir certificat Let's Encrypt via certbot (standalone)
certbot certonly --standalone --non-interactive --agree-tos --email "$EMAIL" -d "$DOMAIN"

# Chemins des certificats générés par certbot
CRT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

if [[ ! -f "$CRT_PATH" ]] || [[ ! -f "$KEY_PATH" ]]; then
  echo "Erreur : certificats TLS non trouvés, certificat Let’s Encrypt a échoué."
  exit 1
fi

# Installer XRAY
bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh)

# Créer configuration XRAY
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

# Redémarrer XRAY pour appliquer la config
systemctl restart xray

# Créer script de renouvellement automatique
cat > /usr/local/bin/renew-cert-xray.sh << 'EOS'
#!/bin/bash
certbot renew --quiet --post-hook "systemctl restart xray"
EOS

chmod +x /usr/local/bin/renew-cert-xray.sh

# Ajouter tâche cron pour renouvellement (3h du matin tous les jours)
(crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/renew-cert-xray.sh") | crontab -

# Affichage final
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
