#!/usr/bin/env bash

set -euo pipefail

LOG_DIR="/var/log/kighmu"
LOG_FILE="$LOG_DIR/ws_tt_ssl_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

log(){ echo "[$(date '+%F %T')] $1"; }
error(){ log "ERREUR : $1"; exit 1; }
success(){ log "SUCCÈS : $1"; }

[ -f "$HOME/.kighmu_info" ] || error "~/.kighmu_info manquant"
source "$HOME/.kighmu_info"
[ -n "${DOMAIN:-}" ] || error "DOMAIN non défini"
log "Domaine : $DOMAIN"

apt-get update -qq
apt-get install -y nginx python3 iptables iptables-persistent certbot python3-certbot-nginx net-tools curl wget dnsutils
apt-get autoremove -yqq
success "Paquets installés"

iptables-save > /root/iptables-backup-ws_tt_ssl.rules
iptables -F
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT
netfilter-persistent save >/dev/null 2>&1 || true
success "IPTables OK"

systemctl stop ws-dropbear ws-stunnel nginx 2>/dev/null || true
rm -f /usr/local/bin/ws-{dropbear,stunnel}
rm -f /etc/systemd/system/ws-{dropbear,stunnel}.service
rm -f /etc/nginx/conf.d/kighmu-ws.conf
systemctl daemon-reexec
systemctl daemon-reload
fuser -k 700/tcp 2095/tcp 2>/dev/null || true
sleep 2

[ -f "$HOME/Kighmu/ws-dropbear" ] || error "ws-dropbear absent"
[ -f "$HOME/Kighmu/ws-stunnel" ] || error "ws-stunnel absent"

install -m 755 "$HOME/Kighmu/ws-dropbear" /usr/local/bin/ws-dropbear
install -m 755 "$HOME/Kighmu/ws-stunnel" /usr/local/bin/ws-stunnel

sed -i \
 -e 's/^print \(.*\)$/print(\1)/' \
 -e 's/except \(.*\), \(.*\):/except \1 as \2:/' \
 /usr/local/bin/ws-{dropbear,stunnel}

success "Backends Python3 OK"

cat > /etc/systemd/system/ws-dropbear.service <<EOF
[Unit]
After=network.target
[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/ws-dropbear 2095
Restart=always
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/ws-stunnel.service <<EOF
[Unit]
After=network.target
[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/ws-stunnel 700
Restart=always
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ws-dropbear ws-stunnel
systemctl start ws-dropbear ws-stunnel
success "Services actifs"

cat > /etc/nginx/conf.d/kighmu-ws.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    location / {
        root /var/www/html;
    }
}
EOF

nginx -t
systemctl restart nginx

if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    certbot --nginx -d "$DOMAIN" --agree-tos --non-interactive -m admin@$DOMAIN
fi

cat > /etc/nginx/conf.d/kighmu-ws.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location /ws-dropbear {
        proxy_pass http://127.0.0.1:2095;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_read_timeout 86400;
    }

    location /ws-stunnel {
        proxy_pass http://127.0.0.1:700;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_read_timeout 86400;
    }
}
EOF

nginx -t
systemctl reload nginx
success "Nginx + SSL OK"

echo
echo "WS-DROPBEAR : wss://$DOMAIN/ws-dropbear"
echo "WS-STUNNEL  : wss://$DOMAIN/ws-stunnel"
echo
log "Installation terminée"
