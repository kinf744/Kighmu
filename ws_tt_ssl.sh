#!/usr/bin/env bash

# ==============================================
# Kighmu WS Tunnels Installer - ws_tt_ssl.sh
# WS-Dropbear (HTTP) + WS-Stunnel (HTTPS) + Nginx + SSL + IPTables
# Copyright (c) 2025 Kinf744 - Licence MIT
# ==============================================

set -o errexit
set -o nounset
set -o pipefail

# LOGS
LOG_DIR="/var/log/kighmu"
LOG_FILE="$LOG_DIR/ws_tt_ssl_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR" 755
exec > >(tee -a "$LOG_FILE")
exec 2>&1

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
error() { log "❌ ERREUR : $1"; exit 1; }
success() { log "✅ SUCCÈS : $1"; }

# SOURCE DOMAIN
source ~/.kighmu_info 2>/dev/null || error "Fichier ~/.kighmu_info manquant"
DOMAIN=$(grep DOMAIN ~/.kighmu_info | cut -d= -f2) || error "DOMAINE non trouvé"
log "Domaine détecté : $DOMAIN"

clear
echo "🚀 KIGHMU ws_tt_ssl.sh - WS TUNNELS INSTALLER"
echo "============================================="

# ==============================================
# 0. PAQUETS ESSENTIELS
# ==============================================
log "📦 Installation paquets (nginx, certbot, iptables, python3)..."
apt-get update -qq
PAQUETS="nginx python3 iptables iptables-persistent certbot python3-certbot-nginx net-tools curl wget dnsutils"
for pkg in $PAQUETS; do
    if ! dpkg -l | grep -q "^ii.*$pkg "; then
        apt-get install -y "$pkg" || log "⚠️ $pkg échoué, continuation..."
    fi
done
apt-get autoremove -yqq && apt-get autoclean
success "Paquets installés"

# ==============================================
# 1. IPTABLES (80/443/22)
# ==============================================
log "🔥 IPTables : Ouverture ports 80, 443, 22..."
iptables-save > "/root/iptables-backup-ws_tt_ssl_$(date +%Y%m%d).rules"
iptables -F && iptables -X && iptables -P INPUT DROP && iptables -P FORWARD DROP && iptables -P OUTPUT ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp -m multiport --dports 80,443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
netfilter-persistent save
success "IPTables configuré"

# ==============================================
# 2. NETTOYAGE COMPLET
# ==============================================
log "🧹 Nettoyage installations précédentes..."
systemctl stop ws-dropbear ws-stunnel nginx 2>/dev/null || true
rm -f /usr/local/bin/ws-{dropbear,stunnel} /etc/systemd/system/ws-{dropbear,stunnel}.service /etc/nginx/conf.d/kighmu-ws.conf
systemctl daemon-reload && systemctl reset-failed
fuser -k 700/tcp 2095/tcp 2>/dev/null || true
sleep 3
log "Nettoyage terminé"

# ==============================================
# 3. BACKENDS PYTHON (Vos fichiers locaux)
# ==============================================
log "📥 Copie ws-dropbear + ws-stunnel (fichiers locaux Kighmu)..."
[ -f "$HOME/Kighmu/ws-dropbear" ] || error "ws-dropbear manquant dans Kighmu"
[ -f "$HOME/Kighmu/ws-stunnel" ] || error "ws-stunnel manquant dans Kighmu"

cp "$HOME/Kighmu/ws-dropbear" /usr/local/bin/ws-dropbear || error "Copie ws-dropbear échouée"
cp "$HOME/Kighmu/ws-stunnel" /usr/local/bin/ws-stunnel || error "Copie ws-stunnel échouée"

chmod 755 /usr/local/bin/ws-{dropbear,stunnel}
success "Backends copiés et prêts"

# ==============================================
# 4. SERVICES SYSTEMD
# ==============================================
log "⚙️ Services systemd ws-dropbear (2095) + ws-stunnel (700)..."
cat > /etc/systemd/system/ws-dropbear.service << 'EOF'
[Unit]
Description=Websocket-Dropbear (HTTP) - ws_tt_ssl.sh
After=network.target nss-lookup.target
[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/python3 -O /usr/local/bin/ws-dropbear 2095
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/ws-stunnel.service << 'EOF'
[Unit]
Description=SSH Over Websocket (HTTPS) - ws_tt_ssl.sh
After=network.target nss-lookup.target
[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/python3 -O /usr/local/bin/ws-stunnel 700
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload && systemctl enable ws-dropbear ws-stunnel && systemctl start ws-dropbear ws-stunnel
sleep 5
systemctl is-active --quiet ws-dropbear || error "Service ws-dropbear échoué"
systemctl is-active --quiet ws-stunnel || error "Service ws-stunnel échoué"
success "Services systemd actifs"

# ==============================================
# 5. NGINX + SSL
# ==============================================
log "🌐 Nginx configuration + SSL..."
cat > /etc/nginx/conf.d/kighmu-ws.conf << EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://$server_name$request_uri;
}
server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_session_cache shared:SSL:10m;
    
    location /ws-dropbear {
        proxy_pass http://127.0.0.1:2095;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-Real-Host "127.0.0.1:109";
        proxy_set_header Host $http_host;
        proxy_read_timeout 86400;
    }
    
    location /ws-stunnel {
        proxy_pass http://127.0.0.1:700;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-Real-Host "127.0.0.1:69";
        proxy_set_header Host $http_host;
        proxy_read_timeout 86400;
    }
}
EOF

nginx -t || error "Nginx syntaxe invalide"
systemctl reload nginx || error "Nginx reload échoué"

if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    log "🔒 Génération SSL Let's Encrypt..."
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" || log "⚠️ SSL manuel requis"
fi
success "Nginx + SSL configuré"

# ==============================================
# 6. RÉSUMÉ FINAL
# ==============================================
clear
echo "🎉 ws_tt_ssl.sh TERMINÉ !"
echo "========================"
echo "📁 Logs : $LOG_FILE"
echo ""
echo "🌐 URLS DISPONIBLES :"
echo "   🟢 WS-Dropbear  : wss://$DOMAIN/ws-dropbear  (→ Dropbear:109)"
echo "   🟢 WS-Stunnel   : wss://$DOMAIN/ws-stunnel   (→ SSH:69)"
echo ""
echo "🔍 STATUS SERVICES :"
systemctl status ws-dropbear ws-stunnel --no-pager -l | head -15
echo ""
echo "📊 PORTS ACTIFS :"
netstat -tulpn | grep -E "700|2095"
echo ""
echo "🔥 IPTABLES : Ports 80/443/22 OUVERTS"
log "ws_tt_ssl.sh terminé - Système prêt !"
