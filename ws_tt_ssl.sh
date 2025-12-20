#!/usr/bin/env bash
set -euo pipefail

### ===============================
### VARIABLES
### ===============================
LOG_DIR="/var/log/kighmu"
LOG_FILE="$LOG_DIR/ws_tt_split_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR" && chmod 755 "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

log(){ echo "[$(date '+%F %T')] $1"; }
error(){ log "❌ ERREUR : $1"; exit 1; }
success(){ log "✅ SUCCÈS : $1"; }

### ===============================
### DOMAIN
### ===============================
[ -f "$HOME/.kighmu_info" ] || error "~/.kighmu_info manquant"
source "$HOME/.kighmu_info"
[ -n "${DOMAIN:-}" ] || error "DOMAIN non défini"
log "🌐 Domaine : $DOMAIN"

### ===============================
### INSTALLATION PAQUETS
### ===============================
apt-get update -qq
apt-get install -y nginx python3 iptables iptables-persistent certbot python3-certbot-nginx curl net-tools dnsutils
apt-get autoremove -yqq
success "Paquets installés"

### ===============================
### IPTABLES
### ===============================
iptables-save > /root/iptables-backup-ws.rules
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
success "IPTables configurés"

### ===============================
### NETTOYAGE ANCIEN WS
### ===============================
systemctl stop ws-dropbear ws-stunnel nginx 2>/dev/null || true
rm -f /usr/local/bin/ws-{dropbear,stunnel}
rm -f /etc/systemd/system/ws-{dropbear,stunnel}.service
rm -f /etc/nginx/conf.d/kighmu-ws.conf
systemctl daemon-reexec
systemctl daemon-reload
fuser -k 2095/tcp 700/tcp 2>/dev/null || true
sleep 2

### ===============================
### BACKENDS WS (PYTHON3 SAFE)
### ===============================
install -m 755 "$HOME/Kighmu/ws-dropbear" /usr/local/bin/ws-dropbear
install -m 755 "$HOME/Kighmu/ws-stunnel" /usr/local/bin/ws-stunnel

# Correction Python2 → Python3
sed -i -E \
 -e 's/^[[:space:]]*print[[:space:]]+(.*)$/print(\1)/' \
 -e 's/except ([^,]+), ([^:]+):/except \1 as \2:/' \
 /usr/local/bin/ws-{dropbear,stunnel}

# Vérification compilation
python3 -m py_compile /usr/local/bin/ws-dropbear
python3 -m py_compile /usr/local/bin/ws-stunnel
success "Backends Python3 OK"

### ===============================
### SERVICES SYSTEMD
### ===============================
cat > /etc/systemd/system/ws-dropbear.service <<EOF
[Unit]
Description=WS-Dropbear HTTP (Port 80)
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/ws-dropbear 2095
Restart=always
LimitNOFILE=65536
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/ws-stunnel.service <<EOF
[Unit]
Description=WS-Stunnel WSS HTTPS (Port 443)
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/ws-stunnel 700
Restart=always
LimitNOFILE=65536
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ws-dropbear ws-stunnel
systemctl start ws-dropbear ws-stunnel
success "Services WS actifs"

### ===============================
### NGINX TEMP POUR CERTBOT
### ===============================
cat > /etc/nginx/conf.d/kighmu-ws.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/ {
        root /var/www/html;
    }
}
EOF

nginx -t && systemctl restart nginx

### ===============================
### CERTIFICAT LET'S ENCRYPT
### ===============================
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    certbot --nginx -d "$DOMAIN" --agree-tos --non-interactive -m admin@$DOMAIN
fi

### ===============================
### NGINX FINAL WS/WSS
### ===============================
cat > /etc/nginx/conf.d/kighmu-ws.conf <<EOF
# WS HTTP — DROPBEAR
server {
    listen 80;
    server_name $DOMAIN;

    location /ws-dropbear {
        proxy_pass http://127.0.0.1:2095;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400;
    }

    location / { return 444; }
}

# WSS HTTPS — STUNNEL
server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location /ws-stunnel {
        proxy_pass http://127.0.0.1:700;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400;
    }

    location / { return 444; }
}
EOF

nginx -t && systemctl reload nginx
success "Nginx WS/WSS configuré"

### ===============================
### FIN
### ===============================
echo
echo "DROPBEAR WS : ws://$DOMAIN/ws-dropbear  (HTTP 80)"
echo "STUNNEL WSS : wss://$DOMAIN/ws-stunnel (HTTPS 443)"
echo
log "INSTALLATION TERMINÉE — SYSTÈME STABLE ✅"
