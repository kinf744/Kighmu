cat > ~/Kighmu/dropbear.sh << 'EOF'
#!/bin/bash
set -euo pipefail

DROPBEAR_BIN="/usr/bin/dropbear"
DROPBEAR_CONF="/etc/default/dropbear"
DROPBEAR_DIR="/etc/dropbear"
BACKUP_DIR="/root/kighmu_dropbear_backup_$(date +%Y%m%d_%H%M%S)"

UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "22.04")
case "${UBUNTU_VERSION:0:5}" in
    "20.04") DROPBEAR_VER="2019.78" ;;
    "22.04") DROPBEAR_VER="2022.83" ;;
    "24.04") DROPBEAR_VER="2024.84" ;;
    *) DROPBEAR_VER="2022.83" ;;
esac
BANNER="SSH-2.0-dropbear_$DROPBEAR_VER"

RED='\u001B[0;31m' GREEN='\u001B[0;32m' YELLOW='\u001B[1;33m' NC='\u001B[0m'
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[X]${NC} $1"; }

[ "$EUID" -ne 0 ] && { error "Exécuter en root"; exit 1; }

header() {
    clear
    echo "=========================================="
    echo "    KIGHMU DROPBEAR MANAGER v1.0"
    echo "    Bannière: $BANNER"
    echo "=========================================="
    echo "IP: $(hostname -I | awk '{print $1}')"
    [ -n "$SSH_CONNECTION" ] && echo "SSH port: $(echo $SSH_CONNECTION | awk '{print $4}' | cut -d: -f2)"
    echo ""
}

show_menu() {
    header
    echo "OPTIONS:"
    echo "  1) Installer Dropbear sur port 2222 (SAFE)"
    echo "  2) Ajouter port 22 + redémarrer"
    echo ""
}

option1_2222() {
    header
    echo "=== OPTION 1: Dropbear sur port 2222 ==="
    info "Installation Dropbear..."
    apt-get update -qq && apt-get install -y dropbear
    info "Clés..."
    mkdir -p "$BACKUP_DIR" && rm -rf "$DROPBEAR_DIR"
    mkdir -p "$DROPBEAR_DIR" && chmod 755 "$DROPBEAR_DIR"
    umask 077 && dropbearkey -t rsa -f "$DROPBEAR_DIR/dropbear_rsa_host_key"
    chmod 600 "$DROPBEAR_DIR"/*
    cat > "$DROPBEAR_CONF" << EOF
NO_START=0
DROPBEAR_PORT=2222
DROPBEAR_EXTRA_ARGS="-w -s -g"
EOF
    systemctl daemon-reload && systemctl enable dropbear && systemctl restart dropbear
    sleep 3
    if systemctl is-active --quiet dropbear && ss -tlnp | grep -q :2222; then
        success "Dropbear 2222 OK !"
        success "TEST: ssh root@$(hostname -I | awk '{print $1}') -p 2222"
    else
        error "Échec 2222"; exit 1
    fi
    read -p "Test OK ?"
}

option2_add22() {
    header
    echo "=== OPTION 2: Ajouter port 22 ==="
    if ! ss -tlnp | grep -q :2222; then error "2222 non actif !"; read -p "Entrez..."; return; fi
    warn "Session peut être coupée !"
    read -p "Confirmer ? (o/n): " confirm
    [[ $confirm =~ ^[Oo]$ ]] || return
    cp "$DROPBEAR_CONF" "$BACKUP_DIR/"
    fuser -k 22/tcp 2>/dev/null || true
    sleep 2
    CURRENT_PORT=$(grep DROPBEAR_PORT "$DROPBEAR_CONF" | cut -d= -f2)
    cat > "$DROPBEAR_CONF" << EOF
NO_START=0
DROPBEAR_PORT=$CURRENT_PORT
DROPBEAR_EXTRA_ARGS="-p 22 -w -s -g"
EOF
    systemctl restart dropbear
    sleep 5
    if ss -tlnp | grep -q ":22.*dropbear"; then
        success "22 + 2222 OK !"
    else
        error "Échec ! Restauration..."
        cat > "$DROPBEAR_CONF" << EOF
NO_START=0
DROPBEAR_PORT=2222
DROPBEAR_EXTRA_ARGS="-w -s -g"
EOF
        systemctl restart dropbear
    fi
    read -p "Entrez..."
}

while true; do
    show_menu
    read -p "Choix (1-2): " choice
    case $choice in 1) option1_2222 ;; 2) option2_add22 ;; *) error "1 ou 2 !" ;; esac
done
EOF

chmod +x ~/Kighmu/dropbear.sh
install_dropbear
