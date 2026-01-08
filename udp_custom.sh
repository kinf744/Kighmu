#!/bin/bash
# =====================================================
# UDP Custom Server - Installation Complète + Exclude Ports
# Compatible HTTP Custom VPN - Port 36712
# Ubuntu 20.04+ / Debian 12+
# =====================================================

set -euo pipefail

# ================== COULEURS ==================
RED='\u001B[1;31m'
GREEN='\u001B[1;32m'
YELLOW='\u001B[1;33m'
BLUE='\u001B[1;34m'
NC='\u001B[0m'

# ================== VARIABLES =================
LOG_FILE="/var/log/udp-custom-install.log"
UDP_DIR="/root/udp"
UDP_BIN="$UDP_DIR/udp-custom"
CONFIG_FILE="$UDP_DIR/config.json"
UDPGW_BIN="/usr/bin/udpgw"
SERVICE_UDP="udp-custom.service"
SERVICE_UDPGW="udpgw.service"
UDP_PORT=36712

DEFAULT_EXCLUDE_PORTS="53,80,8443,8880,5300,9090,4466,444,5401,54000"
EXCLUDE_PORTS="$DEFAULT_EXCLUDE_PORTS"

# ================== LOGGING ==================
log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"; }
msg_ok()   { log "${GREEN}[OK]${NC} $*"; }
msg_info() { log "${BLUE}[INFO]${NC} $*"; }
msg_warn() { log "${YELLOW}[WARN]${NC} $*"; }
msg_error(){ log "${RED}[ERROR]${NC} $*"; exit 1; }

print_center() {
    local msg="$*"
    local cols=80
    [[ -t 1 ]] && cols=$(tput cols 2>/dev/null || echo 80)
    printf "%*s\n" $(( (${#msg} + cols) / 2 )) "$msg"
}

# ================== FONCTIONS ==================

setup_exclude_ports() {
    EXCLUDE_PORTS="$DEFAULT_EXCLUDE_PORTS"

    if [[ -t 0 ]]; then
        echo ""
        print_center "Configuration des ports à EXCLURE"
        echo "Ports par défaut : $DEFAULT_EXCLUDE_PORTS"
        read -r -p "Ports à exclure (Entrée = défaut) : " input
        [[ -n "$input" ]] && EXCLUDE_PORTS="$input"
    else
        msg_warn "Pas de TTY détecté → ports par défaut utilisés"
    fi

    if [[ ! "$EXCLUDE_PORTS" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
        msg_warn "Format invalide → ports par défaut"
        EXCLUDE_PORTS="$DEFAULT_EXCLUDE_PORTS"
    fi

    if echo ",$EXCLUDE_PORTS," | grep -q ",$UDP_PORT,"; then
        msg_error "Le port principal $UDP_PORT ne peut pas être exclu"
    fi

    msg_ok "Ports exclus: $EXCLUDE_PORTS"
}

check_root() {
    [[ "$(id -u)" -ne 0 ]] && msg_error "Ce script doit être exécuté en root"
}

check_os() {
    . /etc/os-release
    case "$ID" in
        ubuntu) (( ${VERSION_ID%%.*} < 20 )) && msg_error "Ubuntu 20.04+ requis" ;;
        debian) (( ${VERSION_ID%%.*} < 12 )) && msg_error "Debian 12+ requis" ;;
        *) msg_error "OS non supporté: $ID" ;;
    esac
    msg_ok "OS compatible détecté: $PRETTY_NAME"
}

cleanup_previous() {
    msg_info "Nettoyage des anciennes installations..."
    systemctl stop $SERVICE_UDP $SERVICE_UDPGW 2>/dev/null || true
    systemctl disable $SERVICE_UDP $SERVICE_UDPGW 2>/dev/null || true
    rm -rf "$UDP_DIR" "$UDPGW_BIN"
    rm -f /etc/systemd/system/$SERVICE_UDP /etc/systemd/system/$SERVICE_UDPGW
    rm -f /usr/local/bin/udp-custom
    msg_ok "Nettoyage terminé"
}

install_dependencies() {
    msg_info "Installation des dépendances..."
    apt update
    apt install -y wget curl ca-certificates jq
    msg_ok "Dépendances installées"
}

download_binaries() {
    msg_info "Téléchargement des binaires UDP Custom..."
    mkdir -p "$UDP_DIR"

    wget -q https://raw.githubusercontent.com/http-custom/udp-custom/main/bin/udp-custom-linux-amd64 -O "$UDP_BIN"
    chmod +x "$UDP_BIN"
    ln -sf "$UDP_BIN" /usr/local/bin/udp-custom

    wget -q https://raw.githubusercontent.com/http-custom/udp-custom/main/module/udpgw -O "$UDPGW_BIN"
    chmod +x "$UDPGW_BIN"

    msg_ok "Binaires téléchargés"
}

create_config() {
    msg_info "Création de la configuration..."

    set +e
    setup_exclude_ports
    set -e

    IFS=',' read -ra PORTS <<< "$EXCLUDE_PORTS"
    EXCLUDE_JSON=$(printf "%s," "${PORTS[@]}")
    EXCLUDE_JSON="[${EXCLUDE_JSON%,}]"

    cat > "$CONFIG_FILE" <<EOF
{
  "listen": ":$UDP_PORT",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "exclude_ports": $EXCLUDE_JSON,
  "auth": { "mode": "passwords" }
}
EOF

    chmod 644 "$CONFIG_FILE"
    msg_ok "Configuration créée"
}

create_services() {
    msg_info "Création des services systemd..."

    cat > /etc/systemd/system/$SERVICE_UDP <<EOF
[Unit]
Description=UDP Custom Server
After=network.target

[Service]
ExecStart=$UDP_BIN server
WorkingDirectory=$UDP_DIR
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/$SERVICE_UDPGW <<EOF
[Unit]
Description=UDP Gateway
After=network.target

[Service]
ExecStart=$UDPGW_BIN --listen-addr 0.0.0.0:7300
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable $SERVICE_UDP $SERVICE_UDPGW
    msg_ok "Services installés"
}

start_services() {
    msg_info "Démarrage des services..."
    systemctl restart $SERVICE_UDPGW
    systemctl restart $SERVICE_UDP
    sleep 2

    systemctl is-active --quiet $SERVICE_UDP \
        && msg_ok "UDP Custom actif sur le port $UDP_PORT" \
        || msg_error "Échec du démarrage UDP Custom"
}

show_status() {
    clear
    print_center "=============================================="
    print_center "UDP CUSTOM - INSTALLATION RÉUSSIE ✅"
    print_center "=============================================="
    echo ""
    echo " Port UDP       : $UDP_PORT"
    echo " Ports exclus   : $EXCLUDE_PORTS"
    echo " Config         : $CONFIG_FILE"
    echo ""
    echo " Commandes utiles :"
    echo "  systemctl restart $SERVICE_UDP"
    echo "  journalctl -u $SERVICE_UDP -f"
    echo ""
    print_center "=============================================="
}

# ================== MAIN ==================
log "=== Début installation UDP Custom ==="
check_root
check_os
cleanup_previous
install_dependencies
download_binaries
create_config
create_services
start_services
show_status
log "=== Installation terminée ==="
