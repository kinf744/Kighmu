#!/usr/bin/env bash

# ==============================================
# Kighmu WS Tunnels Installer COMPLET: ws_tt_ssl.sh
# Logs + Nettoyage + Paquets + IPTables + SSL
# Copyright (c) 2025 Kinf744
# ==============================================

set -o errexit
set -o nounset
set -o pipefail

# LOGS
LOG_DIR="/var/log/kighmu"
LOG_FILE="$LOG_DIR/ws-tunnels_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR" {755}
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
echo "🚀 KIGHMU WS TUNNELS INSTALLER COMPLET"
echo "====================================="

# ==============================================
# 0. INSTALLATION PAQUETS ESSENTIELS
# ==============================================
log "📦 Installation paquets essentiels..."

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
# 1. IPTABLES - OUVERTURE PORTS 80/443 + SSH
# ==============================================
log "🔥 Configuration IPTables (ports 80, 443, 22)..."

# Sauvegarde actuelle
iptables-save > /root/iptables-backup-$(date +%Y%m%d).rules

# Flush + politique par défaut
iptables -F
iptables -X
iptables -P INPUT DROP
iptables -P FORWARD DROP  
iptables -P OUTPUT ACCEPT

# Connexions établies/relacionnées
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# LOOPBACK
iptables -A INPUT -i lo -j ACCEPT

# SSH (22)
iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT

# HTTP/HTTPS (80, 443) - WebSocket
iptables -A INPUT -p tcp -m multiport --dports 80,443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT

# Sauvegarde permanente
netfilter-persistent save > /dev/null || echo "#!/bin/sh" > /etc/iptables/rules.v4
iptables-save > /etc/iptables/rules.v4

success "IPTables configuré (80, 443, 22 ouverts)"

# ==============================================
# 2. NETTOYAGE PUISSANT
# ==============================================
log "🧹 Nettoyage installations précédentes..."

systemctl stop ws-dropbear ws-stunnel nginx 2>/dev/null || true
systemctl disable ws-dropbear ws-stunnel 2>/dev/null || true

rm -f /usr/local/bin/ws-{dropbear,stunnel}
rm -f /etc/systemd/system/ws-{dropbear,stunnel}.service
rm -f /etc/nginx/conf.d/kighmu-ws.conf

systemctl daemon-reload
systemctl reset-failed
fuser -k 700/tcp 2095/tcp 2>/dev/null || true
sleep 3

log "Nettoyage terminé"

# ==============================================
# 3. VÉRIFICATIONS PRÉALABLES
# ==============================================
log "🔍 Vérifications système..."

command -v python3 >/dev/null || error "Python3 manquant"
command -v nginx >/dev/null || error "Nginx manquant"

systemctl start nginx
sleep 2
systemctl is-active --quiet nginx || error "Nginx ne démarre pas"

# ==============================================
# 4. INSTALLATION BACKENDS PYTHON
# ==============================================
log "📥 Installation backends WebSocket..."

wget -q --show-progress -O /usr/local/bin/ws-dropbear "$HOME/Kighmu/ws-dropbear" || error "ws-dropbear téléchargement échoué"
wget -q --show-progress -O /usr/local/bin/ws-stunnel "$HOME/Kighmu/ws-stunnel" || error "ws-stunnel téléchargement échoué"

chmod 755 /usr/local/bin/ws-{dropbear,stunnel}

success "Backends Python installés"

# ==============================================
# 5. SERVICES SYSTEMD
# ==============================================
log "⚙️ Création services systemd..."

cat > /etc/systemd/system/ws-dropbear.service << 'EOF'
[Unit]
Description=Websocket-Dropbear (HTTP)
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
Description=SSH Over Websocket (HTTPS)
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

systemctl daemon-reload
systemctl enable ws-dropbear ws-stunnel
systemctl start ws-dropbear ws-stunnel

sleep 5
systemctl is-active --quiet ws-dropbear || error "Service ws-dropbear échoué"
systemctl is-active --quiet ws-stunnel || error "Service ws-stunnel échoué"

success "Services systemd actifs"

# ==============================================
# 6. CONFIG NGINX + SSL
# ==============================================
log "🌐 Configuration Nginx WebSocket + SSL..."

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

nginx -t || error "Syntaxe Nginx invalide"
systemctl reload nginx || error "Reload Nginx échoué"

# SSL automatique
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    log "🔒 Génération certificat Let's Encrypt..."
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" || \
    log "⚠️ Certbot échoué - config manuelle SSL requise"
fi

success "Nginx + SSL configuré"

# ==============================================
# 7. TESTS FINAUX + RÉSUMÉ
# ==============================================
log "🧪 Tests finaux..."

# Ports backend
netstat -tulpn | grep -E "700|2095" || error "Backends non démarrés"
# IPTables
iptables -L INPUT -n -v | grep -E "80|443" || log "⚠️ Vérifiez IPTables"
# Nginx
curl -k -I "https://$DOMAIN" >/dev/null 2>&1 && success "Nginx accessible" || log "⚠️ Nginx (test HTTPS)"

clear
echo "🎉 INSTALLATION 100% TERMINÉE !"
echo "================================"
echo "📁 Logs complets  : $LOG_FILE"
echo "🔥 IPTables       : Ports 80/443/22 OUVERTS"
echo "📦 Paquets        : nginx, certbot, iptables, python3"
echo ""
echo "🌐 URLS DISPONIBLES :"
echo "   🟢 WS-Dropbear  : wss://$DOMAIN/ws-dropbear"
echo "   🟢 WS-Stunnel  : wss://$DOMAIN/ws-stunnel"
echo ""
echo "🔍 STATUS RAPIDE :"
systemctl status ws-dropbear ws-stunnel nginx --no-pager -l | head -20
echo ""
echo "📊 IPTABLES ACTIFS :"
iptables -L INPUT -n | grep -E "80|443|22" | head -5
log "Installation terminée - Système prêt !"
