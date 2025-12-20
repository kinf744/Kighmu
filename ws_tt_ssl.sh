#!/usr/bin/env bash
set -euo pipefail

# ===============================
# Variables
# ===============================
LOG_DIR="/var/log/kighmu"
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"
LOG_FILE="$LOG_DIR/ws_install_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

INSTALL_DIR="$HOME/Kighmu"
mkdir -p "$INSTALL_DIR"

[ -f "$HOME/.kighmu_info" ] || { echo "Fichier ~/.kighmu_info manquant"; exit 1; }
DOMAIN=$(grep DOMAIN ~/.kighmu_info | cut -d= -f2)
[ -n "$DOMAIN" ] || { echo "DOMAIN non défini dans ~/.kighmu_info"; exit 1; }

echo "🌐 Domaine utilisé : $DOMAIN"

# ===============================
# Installer paquets essentiels
# ===============================
echo "🚀 Installation paquets essentiels..."
apt-get update -y
apt-get install -y python3 python3-pip nginx certbot python3-certbot-nginx curl iptables iptables-persistent dropbear stunnel4 net-tools wget
python3 -m pip install --upgrade pip websockets

# ===============================
# Télécharger scripts WS depuis GitHub
# ===============================
FILES=("ws-dropbear" "ws-stunnel")
BASE_URL="https://raw.githubusercontent.com/kinf744/Kighmu/main"

for file in "${FILES[@]}"; do
    echo "📥 Téléchargement de $file ..."
    wget -q --show-progress -O "$INSTALL_DIR/$file" "$BASE_URL/$file"
    chmod +x "$INSTALL_DIR/$file"
done

# ===============================
# Services systemd
# ===============================
echo "🔧 Création services systemd..."

# WS Dropbear
cat > /etc/systemd/system/ws-dropbear.service <<EOF
[Unit]
Description=WS Dropbear HTTP
After=network.target

[Service]
ExecStart=/usr/bin/python2 $INSTALL_DIR/ws-dropbear 2095
Restart=always
LimitNOFILE=65536
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# WS Stunnel
cat > /etc/systemd/system/ws-stunnel.service <<EOF
[Unit]
Description=WS Stunnel HTTPS
After=network.target

[Service]
ExecStart=/usr/bin/python2 $INSTALL_DIR/ws-stunnel 700
Restart=always
LimitNOFILE=65536
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ws-dropbear ws-stunnel
systemctl start ws-dropbear ws-stunnel

# ===============================
# Certificat SSL avec Certbot
# ===============================
echo "🔐 Vérification certificat SSL..."
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    certbot --nginx -d "$DOMAIN" --agree-tos --non-interactive -m admin@$DOMAIN
fi

# ===============================
# Configuration Nginx WS/WSS
# ===============================
echo "🖧 Configuration Nginx proxy WS/WSS..."
cat > /etc/nginx/conf.d/kighmu-ws.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location /ws-dropbear {
        proxy_pass http://127.0.0.1:2095;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    location / { return 444; }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location /ws-stunnel {
        proxy_pass http://127.0.0.1:700;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400;
    }

    location / { return 444; }
}
EOF

nginx -t && systemctl reload nginx

# ===============================
# Résumé
# ===============================
echo
echo "✅ WS DROPBEAR : ws://$DOMAIN/ws-dropbear"
echo "✅ WS STUNNEL : wss://$DOMAIN/ws-stunnel"
echo
echo "[OK] Installation WS terminée et services actifs."
systemctl status ws-dropbear ws-stunnel --no-pager
