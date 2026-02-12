#!/bin/bash
set -euo pipefail

# ==============================
# VARIABLES
# ==============================
DROPBEAR_BIN="/usr/sbin/dropbear"
DROPBEAR_DIR="/etc/dropbear"
DROPBEAR_PORT=109
DROPBEAR_BANNER="/etc/dropbear/banner.txt"
SYSTEMD_FILE="/etc/systemd/system/dropbear.service"

# ==============================
# DETECTION VERSION OS (UBUNTU)
# ==============================
source /etc/os-release
OS_ID="$ID"
OS_VERSION="$VERSION_ID"

case "$OS_ID-$OS_VERSION" in
    ubuntu-20.04) DROPBEAR_VER="2019.78" ;;
    ubuntu-22.04) DROPBEAR_VER="2020.81" ;;
    ubuntu-24.04) DROPBEAR_VER="2022.83" ;;
    *) DROPBEAR_VER="2022.83" ;;
esac

BANNER="SSH-2.0-dropbear_$DROPBEAR_VER"

# ==============================
# COULEURS
# ==============================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info(){ echo -e "${GREEN}[INFO]${NC} $1"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
error(){ echo -e "${RED}[ERROR]${NC} $1"; }

# ==============================
# ROOT CHECK
# ==============================
[ "$EUID" -ne 0 ] && { error "Exécuter en root"; exit 1; }

# ==============================
# COMMANDS CHECK
# ==============================
for cmd in dropbearkey dos2unix hostname ss; do
    command -v "$cmd" >/dev/null 2>&1 || { error "Commande $cmd introuvable"; exit 1; }
done

clear
echo "=========================================="
echo "   KIGHMU DROPBEAR SERVICE"
echo "   Bannière : $BANNER"
echo "=========================================="
echo "IP : $(hostname -I | awk '{print $1}')"
echo "=========================================="
echo

# ==============================
# INSTALL DROPBEAR
# ==============================
if ! command -v dropbear >/dev/null 2>&1; then
    info "Installation Dropbear..."
    apt update -y
    apt install -y dropbear
else
    info "Dropbear déjà installé"
fi

# ==============================
# STOP ANCIEN SERVICE
# ==============================
info "Arrêt de l’ancien service Dropbear..."
systemctl stop dropbear 2>/dev/null || true
systemctl disable dropbear 2>/dev/null || true

# ==============================
# VERIFICATION BINAIRE
# ==============================
[ ! -x "$DROPBEAR_BIN" ] && { error "Binaire absent"; exit 1; }

# ==============================
# PREPARATION DOSSIER + CLES
# ==============================
info "Préparation des clés host Dropbear..."
mkdir -p "$DROPBEAR_DIR"
chmod 755 "$DROPBEAR_DIR"

for key in rsa dss ecdsa ed25519; do
    KEY_FILE="$DROPBEAR_DIR/dropbear_${key}_host_key"
    if [ ! -f "$KEY_FILE" ]; then
        info "Génération clé $key..."
        if dropbearkey -t "$key" -f /dev/null >/dev/null 2>&1; then
            dropbearkey -t "$key" -f "$KEY_FILE"
        else
            warn "Clé $key non supportée par cette version de Dropbear, ignorée"
        fi
    fi
done

chmod 600 "$DROPBEAR_DIR"/*
chown root:root "$DROPBEAR_DIR"/*

# ==============================
# CREATION BANNER
# ==============================
info "Création du banner Dropbear..."
mkdir -p "$(dirname "$DROPBEAR_BANNER")"

cat <<EOF > "$DROPBEAR_BANNER"
Bienvenue sur Dropbear SSH
EOF

dos2unix "$DROPBEAR_BANNER" 2>/dev/null || true
chmod 644 "$DROPBEAR_BANNER"
chown root:root "$DROPBEAR_BANNER"

# ==============================
# CREATION SERVICE SYSTEMD
# ==============================
info "Création service systemd..."

cat <<EOF > "$SYSTEMD_FILE"
[Unit]
Description=Dropbear SSH Server on port $DROPBEAR_PORT
After=network.target

[Service]
ExecStart=$DROPBEAR_BIN -F -E -p $DROPBEAR_PORT -w -g -b $DROPBEAR_BANNER
Restart=always
RestartSec=2
LimitNOFILE=1048576
User=root

[Install]
WantedBy=multi-user.target
EOF

# ==============================
# DEMARRAGE SERVICE
# ==============================
systemctl daemon-reload
systemctl enable --now dropbear.service

info "✅ Dropbear actif sur port $DROPBEAR_PORT"
info "🔹 Vérifier : systemctl status dropbear.service"
info "🔹 Voir logs : journalctl -u dropbear.service -n 50"

# ==============================
# VERIFICATION PORT
# ==============================
if ss -tulpn | grep -q ":$DROPBEAR_PORT "; then
    info "Port $DROPBEAR_PORT OK et à l’écoute"
else
    warn "Port $DROPBEAR_PORT non ouvert ! Vérifier les logs"
fi
