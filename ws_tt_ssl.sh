#!/usr/bin/env bash
set -euo pipefail

### ===============================
### VARIABLES
### ===============================
INSTALL_DIR="/root/Kighmu"
LOG_DIR="/var/log/kighmu"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/ws_install_$(date +%F_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

error(){ echo "[ERREUR] $1"; exit 1; }
ok(){ echo "[OK] $1"; }

### ===============================
### DOMAINE
### ===============================
[ -f "$HOME/.kighmu_info" ] || error "~/.kighmu_info manquant"
source "$HOME/.kighmu_info"
[ -n "${DOMAIN:-}" ] || error "DOMAIN non défini"

ok "Domaine détecté : $DOMAIN"

### ===============================
### PAQUETS
### ===============================
apt-get update -qq
apt-get install -y \
  nginx \
  python3 \
  python3-pip \
  iptables \
  iptables-persistent \
  certbot \
  python3-certbot-nginx \
  net-tools \
  curl

python3 -m pip install --upgrade pip
python3 -m pip install websockets

ok "Paquets installés"

### ===============================
### IPTABLES (SAFE)
### ===============================
iptables -F
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

netfilter-persistent save >/dev/null 2>&1 || true
ok "IPTables OK"

### ===============================
### VÉRIF SCRIPTS PYTHON EXISTANTS
### ===============================
[ -x "$INSTALL_DIR/ws-dropbear" ] || error "ws-dropbear introuvable"
[ -x "$INSTALL_DIR/ws-stunnel" ] || error "ws-stunnel introuvable"

ok "Scripts Python existants détectés"

### ===============================
### SERVICES SYSTEMD
### ===============================
cat > /etc/systemd/system/ws-dropbear.service <<EOF
[Unit]
Description=WS Dropbear HTTP
After=network.target

[Service]
ExecStart=/usr/bin/python3 $INSTALL_DIR/ws-dropbear
Restart=always
RestartSec=2
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/ws-stunnel.service <<EOF
[Unit]
Description=WS Stunnel HTTPS
After=network.target

[Service]
ExecStart=/usr/bin/python3 $INSTALL_DIR/ws-stunnel
Restart=always
RestartSec=2
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ws-dropbear ws-stunnel
systemctl restart ws-dropbear ws-stunnel

ok "Services WS actifs"

### ===============================
### NGINX TEMP CERTBOT
### ===============================
cat > /etc/nginx/conf.d/ws.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/ { root /var/www/html; }
}
EOF

nginx -t
systemctl reload nginx

### ===============================
### CERTIFICAT SSL
### ===============================
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
  certbot --nginx -d "$DOMAIN" --agree-tos --non-interactive -m admin@$DOMAIN
fi

ok "Certificat SSL OK"

### ===============================
### NGINX FINAL WS / WSS
### ===============================
cat > /etc/nginx/conf.d/ws.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location /ws-dropbear {
        proxy_pass http://127.0.0.1:2095;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_set_header Host \$host;
        proxy_read_timeout 86400;
    }

    location / {
        return 444;
    }
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
        proxy_set_header Connection upgrade;
        proxy_set_header Host \$host;
        proxy_read_timeout 86400;
    }

    location / {
        return 444;
    }
}
EOF

nginx -t
systemctl reload nginx

### ===============================
### FIN
### ===============================
echo
echo "WS DROPBEAR : ws://$DOMAIN/ws-dropbear"
echo "WS STUNNEL : wss://$DOMAIN/ws-stunnel"
echo
ok "INSTALLATION TERMINÉE — LOGIQUE AUTOSCRIPT ✔️"
