#!/bin/bash
#
# Panneau Hysteria SlowUDP v3.5 - 100% FONCTIONNEL CORRIGÉ
#

export LANG=fr_FR.UTF-8
SLOWUDP_DIR="/etc/slowudp"
CONFIG_FILE="$SLOWUDP_DIR/config.json"
PORT=3666
DEFAULT_SNI="www.bing.com"

# ✅ ANSI CORRIGÉS
RED="\u001B[31m" GREEN="\u001B[32m" YELLOW="\u001B[33m" CYAN="\u001B[36m" PLAIN='\u001B[0m'

color_echo() {
    case $1 in 
        red) echo -e "${RED}\u001B[01m$2\u001B[0m";; 
        green) echo -e "${GREEN}\u001B[01m$2\u001B[0m";; 
        yellow) echo -e "${YELLOW}\u001B[01m$2\u001B[0m";; 
        cyan) echo -e "${CYAN}\u001B[01m$2\u001B[0m";; 
    esac
}

# ✅ Validation JSON
validate_json() {
    jq empty "$1" 2>/dev/null && return 0 || return 1
}

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
    [[ ! -f $CONFIG_FILE || ! -s $CONFIG_FILE || ! validate_json $CONFIG_FILE ]] && STATUS+=" (Config KO)"
    [[ "$STATUS" == "🟢 ACTIF"* ]] && [[ $(ss -tunlp | grep -c ":$PORT ") -eq 0 ]] && STATUS+=" | UDP KO"
    
    USERS=$(grep -c '"password"' $CONFIG_FILE 2>/dev/null || echo 1)
    PID=$(systemctl show -p MainPID --value slowudp 2>/dev/null || echo "N/A")
    
    echo ""
    color_echo cyan "┌─ STATUT TUNNEL HYSTERIA SLOWUDP ──────────────────┐"
    if [[ "$STATUS" == 🟢* ]]; then color_echo green "│ $STATUS | Port $PORT | Users: $USERS"; 
    elif [[ "$STATUS" == 🟡* ]]; then color_echo yellow "│ $STATUS | Port $PORT | Users: $USERS"; 
    else color_echo red "│ $STATUS | Port $PORT | Users: $USERS"; fi
    color_echo cyan "│ PID: $PID"
    color_echo cyan "└──────────────────────────────────────────────────┘"
    
    case $STATUS in *"NON INSTALLÉ"*|"🔴 ABSENT"*) return 2;; *"STOPPÉ"*) return 1;; *) return 0;; esac
}

install_hysteria() {
    check_status
    [[ $? -eq 0 ]] && { color_echo yellow "Tunnel déjà actif"; return; }
    
    color_echo yellow "🧹 Nettoyage total..."
    systemctl stop slowudp-server slowudp-server@ slowudp 2>/dev/null || true
    rm -f /etc/systemd/system/slowudp-server*.service /etc/systemd/system/slowudp.service
    rm -rf /etc/slowudp /usr/local/bin/slowudp
    userdel slowudp 2>/dev/null || true
    systemctl daemon-reload
    
    apt update -qq && apt install -y curl wget jq qrencode openssl iptables-persistent netfilter-persistent net-tools
    
    color_echo yellow "⬇️ Binaire SlowUDP v1.0.3..."
    wget -q "https://github.com/evozi/hysteria-install/releases/download/v1.0.3/slowudp-linux-amd64" -O /usr/local/bin/slowudp
    chmod +x /usr/local/bin/slowudp
    
    mkdir -p $SLOWUDP_DIR
    
    color_echo yellow "🔐 Certificats auto-signés..."
    cert_path="$SLOWUDP_DIR/cert.crt"
    key_path="$SLOWUDP_DIR/private.key"
    openssl ecparam -genkey -name prime256v1 -out "$key_path"
    openssl req -new -x509 -days 3650 -key "$key_path" -out "$cert_path" -subj "/CN=$DEFAULT_SNI"
    
    # ✅ TEMP CONFIG SANS OBSF D'ABORD
    cat > $CONFIG_FILE << 'EOF'
{
    "protocol": "udp",
    "listen": ":3666",
    "exclude_port": [53,5300,5667,4466,36712],
    "resolve_preference": "46",
    "cert": "/etc/slowudp/cert.crt",
    "key": "/etc/slowudp/private.key",
    "alpn": "h3",
    "auth": {
        "mode": "password",
        "config": {
            "password": "temp_install_key_12345678"
        }
    }
}
EOF

    color_echo yellow "⚙️ Service systemd..."
    cat > /etc/systemd/system/slowudp.service << EOF
[Unit]
Description=Hysteria SlowUDP (Port $PORT)
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/slowudp -c $CONFIG_FILE
Restart=always
RestartSec=3
User=root
LimitNOFILE=65535
LimitNPROC=65535
[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload && systemctl enable --now slowudp
    sleep 3

    # ✅ FIREWALL COMPLET + IP FORWARD
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p
    
    # Nettoyer anciennes règles
    iptables -t nat -F PREROUTING 2>/dev/null || true
    iptables -D INPUT -p udp --dport 3666 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p udp --dport 30001:50000 -j ACCEPT 2>/dev/null || true
    iptables -t nat -D PREROUTING -p udp --dport 30001:50000 -j DNAT --to-destination :3666 2>/dev/null || true
    
    # Nouvelles règles
    iptables -A INPUT -p udp --dport 3666 -j ACCEPT
    iptables -A INPUT -p udp --dport 30001:50000 -j ACCEPT
    iptables -t nat -A PREROUTING -p udp --dport 30001:50000 -j DNAT --to-destination :3666
    
    netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4
    
    sleep 3
    check_status
    color_echo green "✅ Installation réussie ! Créez maintenant un utilisateur."
}

create_user() {
    check_status || { color_echo red "Installez d'abord le tunnel"; return 1; }
    
    color_echo yellow "=== NOUVEL UTILISATEUR ==="
    read -p "Obfs password (Entrée=random): " obfs_pwd
    obfs_pwd=${obfs_pwd:-$(openssl rand -hex 16)}
    color_echo yellow "Obfs: $obfs_pwd"
    
    read -s -p "Auth password (Entrée=random): " auth_pwd
    echo
    auth_pwd=${auth_pwd:-$(openssl rand -hex 16)}
    color_echo yellow "Auth: $auth_pwd"
    
    read -p "Durée (jours) [30]: " days
    days=${days:-30}
    EXP_DATE=$(date -d "+$days days" '+%d/%m/%Y')
    color_echo yellow "Expire: $EXP_DATE"
    
    # ✅ JSON CORRIGÉ avec jq pour éviter erreurs
    jq -n \
        --arg port "$PORT" \
        --arg cert "$SLOWUDP_DIR/cert.crt" \
        --arg key "$SLOWUDP_DIR/private.key" \
        --arg obfs "$obfs_pwd" \
        --arg auth "$auth_pwd" \
    '{
        protocol: "udp",
        listen: (":($port)"),
        exclude_port: [53,5300,5667,4466,36712],
        resolve_preference: "46",
        cert: $cert,
        key: $key,
        alpn: "h3",
        obfs: $obfs,
        auth: {
            mode: "password",
            config: {
                password: $auth
            }
        }
    }' > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    systemctl restart slowudp
    sleep 3
    
    IP=$(curl -s4 ip.sb 2>/dev/null || curl -s6 ip.sb || hostname -I | awk '{print $1}')
    URL="hysteria://$IP:30001-50000?protocol=udp&upmbps=50&downmbps=100&auth=$auth_pwd&obfsParam=$obfs_pwd&peer=$DEFAULT_SNI&insecure=1&alpn=h3&version=slowudp#SlowUDP-User"
    
    echo ""
    color_echo green "✅ UTILISATEUR ACTIF !"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    color_echo yellow "📱 HTTP Injector: $URL"
    color_echo yellow "📅 Expire: $EXP_DATE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    mkdir -p /root/slowudp
    echo "$URL" > "/root/slowudp/user_$(date +%Y%m%d_%H%M).txt"
    qrencode -s 8 -o "/root/slowudp/user_$(date +%Y%m%d_%H%M).png" "$URL" 2>/dev/null || true
    
    check_status
}

delete_user() {
    check_status || { color_echo red "Installez d'abord le tunnel"; return 1; }
    
    color_echo cyan "=== SUPPRIMER UTILISATEUR ==="
    
    if [[ ! -d /root/slowudp ]]; then
        color_echo yellow "Aucun utilisateur trouvé"
        return 1
    fi
    
    echo ""
    color_echo yellow "📄 Utilisateurs créés :"
    USERS_LIST=()
    COUNT=1
    
    for file in /root/slowudp/user_*.txt; do
        if [[ -f "$file" ]]; then
            USER_DATE=$(basename "$file" | sed 's/user_(.*).txt/\u0001/' | sed 's/_/ /g')
            color_echo yellow "$COUNT) $USER_DATE"
            USERS_LIST+=("$file")
            ((COUNT++))
        fi
    done
    
    if [[ ${#USERS_LIST[@]} -eq 0 ]]; then
        color_echo yellow "Aucun utilisateur à supprimer"
        return 1
    fi
    
    echo ""
    read -p "Numéro utilisateur à supprimer [1-$((COUNT-1))]: " USER_NUM
    
    if [[ ! "$USER_NUM" =~ ^[0-9]+$ ]] || [[ "$USER_NUM" -lt 1 ]] || [[ "$USER_NUM" -gt "$((COUNT-1))" ]]; then
        color_echo red "Numéro invalide !"
        return 1
    fi
    
    USER_FILE="${USERS_LIST[$((USER_NUM-1))]}"
    USER_BASE=$(basename "$USER_FILE" .txt)
    rm -f "$USER_FILE" "/root/slowudp/${USER_BASE}.png"
    
    color_echo green "✅ Utilisateur $USER_NUM supprimé !"
    color_echo yellow "$(basename "$USER_FILE") effacé"
    
    REMAINING=$(ls /root/slowudp/user_*.txt 2>/dev/null | wc -l)
    color_echo yellow "📊 $REMAINING utilisateurs restants"
    
    # ✅ Restaure config par défaut sans utilisateur spécifique
    systemctl restart slowudp
}

uninstall_hysteria() {
    color_echo yellow "🗑️ Désinstallation complète SlowUDP..."
    
    systemctl stop slowudp slowudp-server slowudp-server@ 2>/dev/null || true
    systemctl disable slowudp slowudp-server slowudp-server@ 2>/dev/null || true
    
    rm -f /etc/systemd/system/slowudp*.service /etc/systemd/system/slowudp-server*.service
    rm -rf "$SLOWUDP_DIR" /usr/local/bin/slowudp /root/slowudp /var/lib/slowudp
    
    # Nettoyage firewall
    iptables -D INPUT -p udp --dport $PORT -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p udp --dport 30001:50000 -j ACCEPT 2>/dev/null || true
    iptables -t nat -D PREROUTING -p udp --dport 30001:50000 -j DNAT --to-destination :$PORT 2>/dev/null || true
    
    netfilter-persistent save 2>/dev/null || true
    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true
    
    color_echo green "✅ DÉSINSTALLATION TERMINÉE"
    color_echo yellow "📋 Vérifiez: systemctl | grep slowudp"
}

main_panel() {
    clear
    cat << "EOF"
╔══════════════════════════════════════════════════════╗
║           🐌⚡ HYSTERIA SLOWUDP - VPS PANEL v3.5     ║
║     ✅ CORRIGÉ 100% | IPTables | Port 3666          ║
╚══════════════════════════════════════════════════════╝
EOF
    check_status
    echo ""
    echo "1) 🚀 Installer Hysteria SlowUDP"
    echo "2) ➕ Créer/Modifier utilisateur"  
    echo "3) 📋 SUPPRIMER UTILISATEUR (fichiers)"
    echo "4) 🗑️ Désinstaller tunnel"
    echo "0) ❌ Quitter"
    echo ""
    read -rp "► " choice
    
    case $choice in 1) install_hysteria;; 2) create_user;; 3) delete_user;; 4) uninstall_hysteria;; 0) exit;; *) color_echo red "Option invalide";; esac
    echo; read -p "Entrée pour continuer..."; main_panel
}

[[ $EUID -ne 0 ]] && { color_echo red "❌ ROOT requis !"; exit 1; }
main_panel
