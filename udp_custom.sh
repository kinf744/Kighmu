#!/bin/bash
# =====================================================
# UDP Custom Server - Installation Complète + Exclude Ports
# Compatible HTTP Custom VPN - Port 36712
# Ubuntu 20.04+ / Debian 12+
# =====================================================

set -euo pipefail

# Couleurs
RED='\u001B[1;31m'
GREEN='\u001B[1;32m'
YELLOW='\u001B[1;33m'
BLUE='\u001B[1;34m'
NC='\u001B[0m'

LOG_FILE="/var/log/udp-custom-install.log"
UDP_DIR="/root/udp"
UDP_BIN="$UDP_DIR/udp-custom"
CONFIG_FILE="$UDP_DIR/config.json"
UDPGW_BIN="/usr/bin/udpgw"
SERVICE_UDP="udp-custom.service"
SERVICE_UDPGW="udpgw.service"
UDP_PORT=36712

# Ports à exclure par défaut (DNS, SlowDNS, OpenVPN, WireGuard, etc.)
DEFAULT_EXCLUDE_PORTS="53,80,8443,8880,5300,9090,4466,444,5401,54000"

# Logging
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

print_center() {
    local msg="$*"
    local cols=$(tput cols 2>/dev/null || echo 80)
    printf "%*s
" $(( (${#msg} + cols) / 2 )) "$msg"
}

msg_ok() { log "${GREEN}[OK]${NC} $*"; }
msg_info() { log "${BLUE}[INFO]${NC} $*"; }
msg_warn() { log "${YELLOW}[WARN]${NC} $*"; }
msg_error() { log "${RED}[ERROR]${NC} $*"; exit 1; }

# Fonction exclusion de ports interactive
setup_exclude_ports() {
    echo ""
    print_center "Configuration des ports à EXCLURE"
    echo "Ports par défaut à exclure: $DEFAULT_EXCLUDE_PORTS"
    echo "(DNS:53, SlowDNS:5300, WireGuard:51820, OpenVPN:1194, etc.)"
    echo ""
    
    read -p "Ports à exclure (Entrée=par défaut '$DEFAULT_EXCLUDE_PORTS'): " EXCLUDE_INPUT
    EXCLUDE_PORTS="${EXCLUDE_INPUT:-$DEFAULT_EXCLUDE_PORTS}"
    
    # Validation
    if [[ ! "$EXCLUDE_PORTS" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
        msg_warn "Format invalide, utilisation des ports par défaut"
        EXCLUDE_PORTS="$DEFAULT_EXCLUDE_PORTS"
    fi
    
    # Vérifier que le port principal n'est pas exclu
    if echo "$EXCLUDE_PORTS" | grep -q ",$UDP_PORT," || [[ "$EXCLUDE_PORTS" == *",$UDP_PORT"* ]] || [[ "$EXCLUDE_PORTS" == *"$UDP_PORT,"* ]]; then
        msg_error "ERREUR: Le port principal $UDP_PORT (36712) ne peut pas être exclu !"
    fi
    
    msg_ok "Ports exclus: $EXCLUDE_PORTS"
    echo "exclude_ports: "$EXCLUDE_PORTS"" >> "$CONFIG_FILE"
}

# Vérifications préalables
check_root() {
    [[ "$(whoami)" != "root" ]] && msg_error "Ce script doit être exécuté en root"
}

check_os() {
    local os_version=$(lsb_release -rs 2>/dev/null || cat /etc/os-release | grep VERSION_ID | cut -d'"' -f2)
    [[ "$os_version" < "20" ]] && msg_error "Ubuntu 20.04+ ou Debian 12+ requis"
    msg_ok "OS compatible détecté"
}

cleanup_previous() {
    msg_info "Nettoyage des installations précédentes..."
    systemctl stop $SERVICE_UDP 2>/dev/null || true
    systemctl stop $SERVICE_UDPGW 2>/dev/null || true
    systemctl disable $SERVICE_UDP 2>/dev/null || true
    systemctl disable $SERVICE_UDPGW 2>/dev/null || true
    rm -rf "$UDP_DIR" "$UDPGW_BIN"
    rm -f /etc/systemd/system/$SERVICE_UDP /etc/systemd/system/$SERVICE_UDPGW
    msg_ok "Nettoyage terminé"
}

install_dependencies() {
    msg_info "Installation des dépendances..."
    apt update
    apt install -y wget curl dos2unix ca-certificates jq
    msg_ok "Dépendances installées"
}

download_binaries() {
    msg_info "Téléchargement des binaires UDP Custom..."
    mkdir -p "$UDP_DIR"
    
    wget -q "https://raw.github.com/http-custom/udp-custom/main/bin/udp-custom-linux-amd64" -O "$UDP_BIN"
    chmod +x "$UDP_BIN"
    
    wget -q "https://raw.github.com/http-custom/udp-custom/main/module/udpgw" -O "$UDPGW_BIN"
    chmod +x "$UDPGW_BIN"
    
    msg_ok "Binaires téléchargés"
}

create_config() {
    msg_info "Création de la configuration (port $UDP_PORT)..."
    
    # Config de base
    cat > "$CONFIG_FILE" << 'EOF'
{
  "listen": ":36712",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": {
    "mode": "passwords"
  }
}
EOF
    
    # Ajout des ports exclus
    setup_exclude_ports
    
    chmod 644 "$CONFIG_FILE"
    msg_ok "Config créée avec exclusion de ports: $CONFIG_FILE"
}

create_services() {
    msg_info "Création des services systemd..."
    
    cat > "/etc/systemd/system/$SERVICE_UDP" << 'EOF'
[Unit]
Description=UDP Custom by ePro Dev. Team

[Service]
User=root
Type=simple
ExecStart=/root/udp/udp-custom server
WorkingDirectory=/root/udp/
Restart=always
RestartSec=2s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF
    
    cat > "/etc/systemd/system/$SERVICE_UDPGW" << 'EOF'
[Unit]
Description=UDP Gateway for Custom Protocols
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/udpgw
Restart=on-failure
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable $SERVICE_UDP
    systemctl enable $SERVICE_UDPGW
    msg_ok "Services créés et activés"
}

start_services() {
    msg_info "Démarrage des services..."
    systemctl start $SERVICE_UDPGW
    sleep 2
    systemctl start $SERVICE_UDP
    sleep 3
    
    if systemctl is-active --quiet $SERVICE_UDP; then
        msg_ok "UDP Custom démarré sur port $UDP_PORT"
    else
        msg_error "Échec du démarrage UDP Custom"
    fi
}

show_status() {
    clear
    print_center "=============================================="
    print_center "UDP Custom - Installation Réussie ✅"
    print_center "=============================================="
    echo ""
    
    msg_info "Services actifs:"
    systemctl status $SERVICE_UDP --no-pager -l | head -15
    
    echo ""
    msg_info "Configuration:"
    echo "  Port UDP: $UDP_PORT"
    echo "  Ports exclus: $EXCLUDE_PORTS"
    echo "  Config: $CONFIG_FILE"
    
    echo ""
    msg_info "Commandes utiles:"
    echo "  systemctl restart $SERVICE_UDP          # Redémarrer après modif config"
    echo "  journalctl -u $SERVICE_UDP -f          # Logs en temps réel"
    echo "  netstat -ulnp | grep $UDP_PORT         # Vérifier port"
    echo "  nano $CONFIG_FILE                      # Modifier config/ports"
    
    echo ""
    print_center "HTTP Custom Configuration:"
    echo "  IP: $(curl -4s ifconfig.co 2>/dev/null || echo 'Vérifiez votre IP')"
    echo "  Port: $UDP_PORT"
    echo "  Mode: UDP Custom"
    print_center "=============================================="
    
    echo ""
    msg_info "Modification future des ports exclus:"
    echo "  1. Éditez $CONFIG_FILE"
    echo "  2. systemctl restart $SERVICE_UDP"
}

# ================================================
# MAIN
# ================================================

log "=== Début installation UDP Custom avec exclusion ports ==="

check_root
check_os
cleanup_previous
install_dependencies
download_binaries
create_config
create_services
start_services

msg_ok "Installation terminée avec succès!"
show_status

log "=== Installation terminée ==="
