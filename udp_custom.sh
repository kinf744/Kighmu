#!/bin/bash
# =====================================================
# UDP Custom Server - Installation Complète + Exclude Ports
# Compatible HTTP Custom VPN - Port 36712
# Ubuntu 20.04+ / Debian 12+
# =====================================================

set -eo pipefail   # Retirer le -u

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

DEFAULT_EXCLUDE_PORTS="53,80,8443,8880,5300,9090,4466,444,5401,54000"

# Logging
log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"; }
print_center() { local msg="$*"; local cols=80; cols=$(tput cols 2>/dev/null || echo 80); printf "%*s\n" $(( (${#msg} + cols) / 2 )) "$msg"; }
msg_ok() { log "${GREEN}[OK]${NC} $*"; }
msg_info() { log "${BLUE}[INFO]${NC} $*"; }
msg_warn() { log "${YELLOW}[WARN]${NC} $*"; }
msg_error() { log "${RED}[ERROR]${NC} $*"; exit 1; }

# ================= Fonctions =================

setup_exclude_ports() {
    echo ""
    print_center "Configuration des ports à EXCLURE"
    echo "Ports par défaut à exclure: $DEFAULT_EXCLUDE_PORTS"
    echo "(DNS:53, SlowDNS:5300, WireGuard:51820, OpenVPN:1194, etc.)"
    echo ""

    read -p "Ports à exclure (Entrée=par défaut '$DEFAULT_EXCLUDE_PORTS'): " EXCLUDE_INPUT
    EXCLUDE_PORTS="${EXCLUDE_INPUT:-$DEFAULT_EXCLUDE_PORTS}"

    if [[ ! "$EXCLUDE_PORTS" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
        msg_warn "Format invalide, utilisation des ports par défaut"
        EXCLUDE_PORTS="$DEFAULT_EXCLUDE_PORTS"
    fi

    if echo ",$EXCLUDE_PORTS," | grep -q ",$UDP_PORT,"; then
        msg_error "ERREUR: Le port principal $UDP_PORT ne peut pas être exclu !"
    fi

    msg_ok "Ports exclus: $EXCLUDE_PORTS"
}

check_root() { [[ "$(whoami)" != "root" ]] && msg_error "Ce script doit être exécuté en root"; }

check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            ubuntu)
                (( ${VERSION_ID%%.*} < 20 )) && msg_warn "Ubuntu < 20 détecté, installation possible mais non garantie"
                ;;
            debian)
                (( ${VERSION_ID%%.*} < 12 )) && msg_warn "Debian < 12 détecté, installation possible mais non garantie"
                ;;
            *)
                msg_warn "OS non standard détecté: $ID"
                ;;
        esac
        msg_ok "OS détecté: ${PRETTY_NAME:-$ID}"
    else
        msg_warn "/etc/os-release non trouvé, continuation forcée"
    fi
}

cleanup_previous() {
    msg_info "Nettoyage des installations précédentes..."
    systemctl stop $SERVICE_UDP 2>/dev/null || true
    systemctl stop $SERVICE_UDPGW 2>/dev/null || true
    systemctl disable $SERVICE_UDP 2>/dev/null || true
    systemctl disable $SERVICE_UDPGW 2>/dev/null || true
    rm -rf "$UDP_DIR" "$UDPGW_BIN" 2>/dev/null || true
    rm -f /etc/systemd/system/$SERVICE_UDP /etc/systemd/system/$SERVICE_UDPGW 2>/dev/null || true
    rm -f /usr/local/bin/udp-custom 2>/dev/null || true
    msg_ok "Nettoyage terminé"
}

install_dependencies() {
    msg_info "Installation des dépendances..."
    apt update || true
    apt install -y wget curl dos2unix ca-certificates jq || true
    msg_ok "Dépendances installées"
}

download_binaries() {
    msg_info "Téléchargement des binaires UDP Custom..."
    mkdir -p "$UDP_DIR"
    wget -q "https://raw.github.com/http-custom/udp-custom/main/bin/udp-custom-linux-amd64" -O "$UDP_BIN" || true
    chmod +x "$UDP_BIN" || true
    ln -sf "$UDP_BIN" /usr/local/bin/udp-custom || true
    wget -q "https://raw.github.com/http-custom/udp-custom/main/module/udpgw" -O "$UDPGW_BIN" || true
    chmod +x "$UDPGW_BIN" || true
    msg_ok "Binaires téléchargés"
}

create_config() {
    msg_info "Création de la configuration (port $UDP_PORT)..."
    setup_exclude_ports
    IFS=',' read -ra PORTS <<< "$EXCLUDE_PORTS"
    EXCLUDE_JSON=$(printf "%s," "${PORTS[@]}")
    EXCLUDE_JSON="[${EXCLUDE_JSON%,}]"

    cat > "$CONFIG_FILE" << EOF
{
  "listen": ":$UDP_PORT",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "exclude_ports": $EXCLUDE_JSON,
  "auth": {
    "mode": "passwords"
  }
}
EOF

    chmod 644 "$CONFIG_FILE" || true
    msg_ok "Config créée: $CONFIG_FILE"
}

create_services() {
    msg_info "Création des services systemd..."

    cat > "/etc/systemd/system/$SERVICE_UDP" << EOF
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

    cat > "/etc/systemd/system/$SERVICE_UDPGW" << EOF
[Unit]
Description=UDP Gateway for Custom Protocols
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/udpgw --listen-addr 0.0.0.0:7300
Restart=on-failure
RestartSec=3
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload || true
    systemctl enable $SERVICE_UDP || true
    systemctl enable $SERVICE_UDPGW || true
    msg_ok "Services créés et activés"
}

start_services() {
    msg_info "Démarrage des services..."
    systemctl start $SERVICE_UDPGW || true
    sleep 2
    systemctl start $SERVICE_UDP || true
    sleep 3
    msg_ok "Services démarrés (vérifiez avec systemctl status $SERVICE_UDP)"
}

show_status() {
    clear
    print_center "=============================================="
    print_center "UDP Custom - Installation Réussie ✅"
    print_center "=============================================="
    msg_info "Configuration:"
    echo "Port UDP: $UDP_PORT"
    echo "Ports exclus: $EXCLUDE_PORTS"
    echo "Config: $CONFIG_FILE"
}

# ================= MAIN =================
log "=== Début installation UDP Custom ==="
check_root
check_os
cleanup_previous
install_dependencies
download_binaries
create_config
create_services
start_services
msg_ok "Installation terminée!"
show_status
log "=== Installation terminée ==="
