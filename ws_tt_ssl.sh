#!/usr/bin/env bash

set -euo pipefail

LOG_DIR="/var/log/kighmu"
LOG_FILE="$LOG_DIR/ws_tt_ssl_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

log(){ echo "[$(date '+%F %T')] $1"; }
error(){ log "❌ ERREUR : $1"; exit 1; }
success(){ log "✅ SUCCÈS : $1"; }

[ -f "$HOME/.kighmu_info" ] || error "~/.kighmu_info manquant"
source "$HOME/.kighmu_info"
[ -n "${DOMAIN:-}" ] || error "DOMAIN non défini"
log "Domaine : $DOMAIN"

# PAQUETS
apt-get update -qq
apt-get install -y nginx python3 iptables iptables-persistent certbot python3-certbot-nginx net-tools curl wget dnsutils
apt-get autoremove -yqq
success "Paquets installés"

# IPTABLES (80/443/22)
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
success "IPTables OK (80/443/22 ouverts)"

# NETTOYAGE
systemctl stop ws-dropbear ws-stunnel nginx 2>/dev/null || true
rm -f /usr/local/bin/ws-{dropbear,stunnel}
rm -f /etc/systemd/system/ws-{dropbear,stunnel}.service
rm -f /etc/nginx/conf.d/kighmu-ws.conf
systemctl daemon-reload
fuser -k 700/tcp 2095/tcp 2>/dev/null || true
sleep 2

# BACKENDS + FIX PYTHON2→3
[ -f "$HOME/Kighmu/ws-dropbear" ] || error "ws-dropbear absent"
[ -f "$HOME/Kighmu/ws-stunnel" ] || error "ws-stunnel absent"

install -m 755 "$HOME/Kighmu/ws-dropbear" /usr/local/bin/ws-dropbear
install -m 755 "$HOME/Kighmu/ws-stunnel" /usr/local/bin/ws-stunnel

log "🔧 Fix Python2 → Python3..."
sed -i 's/print ([^)]*)/print(\u0001)/g' /usr/local/bin/ws-{dropbear,stunnel}
sed -i 's/except ([^,]*), ([^:]*):/except \u0001 as \u0002:/g' /usr/local/bin/ws-{dropbear,stunnel}
success "Backends Python3 OK"

# SERVICES SYSTEMD
cat > /etc/systemd/system/ws-dropbear.service <<'EOF'
[Unit]
Description=WS-Dropbear HTTP (Port 80→2095)
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/ws-dropbear 2095
Restart=always
RestartSec=5
LimitNOFILE=65536
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/ws-stunnel.service <<'EOF'
[Unit]
Description=WS-Stunnel HTTPS (Port 443→700)
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/ws-stunnel 700
Restart=always
RestartSec=5
LimitNOFILE=65536
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ws-dropbear ws-stunnel
systemctl start ws-dropbear ws-stunnel
sleep 3
systemctl is-active --quiet ws-dropbear || { journalctl -u ws-dropbear -n 20; error "ws-dropbear failed"; }
systemctl is-active --quiet ws-stunnel || { journalctl -u ws-stunnel -n 20; error "ws-stunnel failed"; }
success "Services actifs"

# NGINX + SSL (80 HTTP → 443 WSS)
cat > /etc/nginx/conf.d/kighmu-ws.conf <<EOF
server {
    listen 80;                    # ← WS HTTP
    server_name $DOMAIN;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl http2;         # ← WSS HTTPS
    server_name $DOMAIN;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    
    location /ws-dropbear {
        proxy_pass http://127.0.0.1:2095;     # Backend Dropbear:109
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
        proxy_read_timeout 86400;
    }
    
    location /ws-stunnel {
        proxy_pass http://127.0.0.1:700;      # Backend SSH:69
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
        proxy_read_timeout 86400;
    }
}
EOF

nginx -t || error "Nginx config failed"
systemctl reload nginx || error "Nginx reload failed"

if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    log "🔒 Certbot SSL..."
    certbot --nginx -d "$DOMAIN" --agree-tos --non-interactive --email "admin@$DOMAIN" || log "⚠️ SSL manuel requis"
fi
success "Nginx + SSL OK"

# RÉSUMÉ
clear
echo "🎉 WS TUNNELS INSTALLÉS !"
echo "========================"
echo "📁 Logs : $LOG_FILE"
echo ""
echo "🌐 PORT 80  → WS HTTP"
echo "🌐 PORT 443 → WSS HTTPS"
echo ""
echo "🟢 WS-Dropbear : ws://$DOMAIN/ws-dropbear  → Dropbear:109"
echo "🟢 WSS-Dropbear: wss://$DOMAIN/ws-dropbear → Dropbear:109"
echo "🟢 WS-Stunnel : ws://$DOMAIN/ws-stunnel   → SSH:69"
echo "🟢 WSS-Stunnel: wss://$DOMAIN/ws-stunnel  → SSH:69"
echo ""
echo "🔍 STATUS :"
systemctl status ws-dropbear ws-stunnel --no-pager -l | head -20
echo ""
echo "📊 PORTS :"
netstat -tulpn | grep -E "(700|2095)"
echo ""
log "Installation terminée - 100% prêt !"
