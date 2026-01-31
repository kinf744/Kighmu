#!/bin/bash
#
# Panneau Hysteria SlowUDP - Config JSON Evozi + Users - Port 3666
#

export LANG=fr_FR.UTF-8
SLOWUDP_DIR="/etc/slowudp"
CONFIG_FILE="$SLOWUDP_DIR/config.json"
PORT=3666
DEFAULT_SNI="www.bing.com"

RED="\u001B[31m" GREEN="\u001B[32m" YELLOW="\u001B[33m" CYAN="\u001B[36m" PLAIN='\u001B[0m'

color_echo() {
    case $1 in 
        red) echo -e "${RED}\u001B[01m$2\u001B[0m";; 
        green) echo -e "${GREEN}\u001B[01m$2\u001B[0m";; 
        yellow) echo -e "${YELLOW}\u001B[01m$2\u001B[0m";; 
        cyan) echo -e "${CYAN}\u001B[01m$2\u001B[0m";; 
    esac
}

# STATUT TUNNEL FONCTIONNEL
check_status() {
    local STATUS=""
    if systemctl is-active --quiet slowudp 2>/dev/null; then
        STATUS="🟢 ACTIF"
    elif systemctl list-unit-files slowudp.service >/dev/null 2>/dev/null; then
        STATUS="🟡 STOPPÉ"
    else
        STATUS="🔴 ABSENT"
    fi
    
    [[ ! -f /usr/local/bin/slowudp ]] && STATUS="🔴 NON INSTALLÉ"
    [[ ! -f $CONFIG_FILE || ! -s $CONFIG_FILE ]] && STATUS+=" (Config KO)"
    [[ "$STATUS" == "🟢 ACTIF"* ]] && [[ $(ss -tunlp | grep -c ":$PORT ") -eq 0 ]] && STATUS+=" | UDP KO"
    
    USERS=$(grep -c '"password"' $CONFIG_FILE 2>/dev/null || echo 0)
    PID=$(systemctl show -p MainPID --value slowudp 2>/dev/null || echo "N/A")
    
    echo ""
    color_echo cyan "┌─ STATUT TUNNEL HYSTERIA SLOWUDP ──────────────────┐"
    color_echo "$( [[ $STATUS == 🟢* ]] && echo green || [[ $STATUS == 🟡* ]] && echo yellow || echo red )" "│ $STATUS | Port $PORT | Users: $USERS"
    color_echo cyan "│ PID: $PID"
    color_echo cyan "└──────────────────────────────────────────────────┘"
    
    case $STATUS in *"NON INSTALLÉ"*|"🔴 ABSENT"*) return 2;; *"STOPPÉ"*) return 1;; *) return 0;; esac
}

# 1. INSTALLER avec config JSON EVOZI
install_hysteria() {
    check_status
    [[ $? -eq 0 ]] && { color_echo yellow "Tunnel déjà actif"; return; }
    
    apt update -qq && apt install -y curl wget jq qrencode openssl iptables-persistent
    
    # SlowUDP evozi
    wget -N --no-check-certificate https://raw.githubusercontent.com/evozi/hysteria-install/main/slowudp/install_server.sh
    bash install_server.sh && rm install_server.sh
    
    mkdir -p $SLOWUDP_DIR
    
    # CERTIFICATS
    cert_path="$SLOWUDP_DIR/cert.crt"
    key_path="$SLOWUDP_DIR/private.key"
    openssl ecparam -genkey -name prime256v1 -out "$key_path"
    openssl req -new -x509 -days 3650 -key "$key_path" -out "$cert_path" -subj "/CN=$DEFAULT_SNI"
    
    # CONFIG JSON EXACTE EVOZI (mode password unique)
    cat > $CONFIG_FILE << EOF
{
    "protocol": "udp",
    "listen": ":$PORT",
    "exclude_port": [53,5300,5667,4466,36712],
    "resolve_preference": "46",
    "cert": "$cert_path",
    "key": "$key_path",
    "alpn": "h3",
    "auth": {
        "mode": "password",
        "config": {
            "password": "temp_install_key_$(openssl rand -hex 8)"
        }
    }
}
EOF

    # 4️⃣ IPTABLES
iptables -I INPUT -p udp --dport 3666 -j ACCEPT
netfilter-persistent save

    # Service systemd
    cat > /etc/systemd/system/slowudp.service << EOF
[Unit]
Description=Hysteria SlowUDP (Port $PORT)
After=network.target ufw.service
[Service]
Type=simple
ExecStart=/usr/local/bin/slowudp -c $CONFIG_FILE
Restart=always
User=nobody
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload && systemctl enable --now slowudp
    sleep 3
    check_status
}

# 2. CRÉER UTILISATEUR (Ordre: obfs → password → expiration)
create_user() {
    check_status || { color_echo red "Installez d'abord le tunnel"; return 1; }
    
    color_echo yellow "=== NOUVEL UTILISATEUR ==="
    
    # 1. OBFUSCATION
    read -p "Obfs password (Entrée=random): " obfs_pwd
    obfs_pwd=${obfs_pwd:-$(openssl rand -hex 16)}
    color_echo yellow "Obfs: $obfs_pwd"
    
    # 2. AUTH PASSWORD
    read -s -p "Auth password (Entrée=random): " auth_pwd
    echo
    auth_pwd=${auth_pwd:-$(openssl rand -hex 16)}
    color_echo yellow "Auth: $auth_pwd"
    
    # 3. EXPIRATION
    read -p "Durée (jours) [30]: " days
    days=${days:-30}
    EXP_DATE=$(date -d "+$days days" '+%d/%m/%Y')
    color_echo yellow "Expire: $EXP_DATE ($days jours)"
    
    # MISE À JOUR CONFIG JSON EVOZI
    cat > $CONFIG_FILE << EOF
{
    "protocol": "udp",
    "listen": ":$PORT",
    "exclude_port": [53,5300,5667,4466,36712],
    "resolve_preference": "46",
    "cert": "$SLOWUDP_DIR/cert.crt",
    "key": "$SLOWUDP_DIR/private.key",
    "alpn": "h3",
    $( [[ -n "$obfs_pwd" ]] && echo ""obfs": "$obfs_pwd"," )
    "auth": {
        "mode": "password",
        "config": {
            "password": "$auth_pwd"
        }
    }
}
EOF
    
    # CONFIG HTTP INJECTOR
    IP=$(curl -s4 ip.sb)
    URL="hysteria://$IP:$PORT?protocol=udp&upmbps=50&downmbps=100&auth=$auth_pwd&obfsParam=$obfs_pwd&peer=$DEFAULT_SNI&insecure=1&alpn=h3&version=slowudp#SlowUDP-User"
    
    echo ""
    color_echo green "✅ UTILISATEUR CONFIGURÉ !"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    color_echo yellow "📱 HTTP Injector Config:"
    echo "  $URL"
    color_echo yellow "📅 Expiration: $EXP_DATE"
    color_echo yellow "🔐 Obfs: $obfs_pwd"
    color_echo yellow "🔑 Auth: $auth_pwd"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Sauvegarde
    mkdir -p /root/slowudp
    echo "$URL" > "/root/slowudp/user_$(date +%Y%m%d_%H%M).txt"
    qrencode -s 8 -o "/root/slowudp/user_$(date +%Y%m%d_%H%M).png" "$URL"
    
    systemctl restart slowudp
    sleep 2
    check_status
}

# 3. AFFICHAGE INFO ACTUELLE
show_current_config() {
    check_status || { color_echo red "Tunnel non installé"; return 1; }
    
    color_echo cyan "=== CONFIGURATION ACTUELLE ==="
    echo "Port: $PORT"
    echo "SNI: $DEFAULT_SNI"
    
    if [[ -f $CONFIG_FILE ]]; then
        OBFS=$(grep '"obfs"' $CONFIG_FILE | sed 's/.*"obfs": "([^"]*)".*/\u0001/')
        AUTH=$(grep -A3 '"password"' $CONFIG_FILE | grep '"password"' | tail -1 | sed 's/.*"password": "([^"]*)".*/\u0001/')
        [[ -n $OBFS ]] && color_echo yellow "Obfs: $OBFS"
        [[ -n $AUTH ]] && color_echo yellow "Auth: $AUTH"
    fi
    
    IP=$(curl -s4 ip.sb)
    URL="hysteria://$IP:$PORT?protocol=udp&upmbps=50&downmbps=100&auth=$AUTH&obfsParam=$OBFS&peer=$DEFAULT_SNI&insecure=1&alpn=h3&version=slowudp#Current"
    echo ""
    color_echo yellow "📱 Config actuelle:"
    echo "  $URL"
}

# 4. DÉSINSTALLER
uninstall_hysteria() {
    color_echo yellow "🗑️ Désinstallation..."
    systemctl stop slowudp >/dev/null 2>&1
    rm -rf /etc/systemd/system/slowudp.service $SLOWUDP_DIR /usr/local/bin/slowudp /root/slowudp
    systemctl daemon-reload
    ufw delete allow $PORT/udp 2>/dev/null
    color_echo green "✅ Supprimé"
}

# PANNEAU PRINCIPAL
main_panel() {
    clear
    cat << "EOF"
╔══════════════════════════════════════════════════════╗
║           🐌⚡ HYSTERIA SLOWUDP - VPS PANEL v3.0     ║
║                     Port: 3666 Fixe                 ║
╚══════════════════════════════════════════════════════╝
EOF
    
    check_status
    echo ""
    
    echo "1) 🚀 Installer Hysteria SlowUDP"
    echo "2) ➕ Créer/Modifier utilisateur"
    echo "3) 📋 Voir config actuelle"
    echo "4) 🗑️  Désinstaller tunnel"
    echo "0) ❌ Quitter"
    echo ""
    read -rp "► " choice
    
    case $choice in
        1) install_hysteria ;;
        2) create_user ;;
        3) show_current_config ;;
        4) uninstall_hysteria ;;
        0) exit 0 ;;
        *) color_echo red "Option invalide" ;;
    esac
    
    echo; read -p "Entrée pour continuer..."; main_panel
}

[[ $EUID -ne 0 ]] && { color_echo red "Exécuter en ROOT"; exit 1; }
main_panel
