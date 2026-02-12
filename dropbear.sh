#!/bin/bash
set -euo pipefail

# ==============================
# VARIABLES
# ==============================
DROPBEAR_BIN="/usr/local/bin/dropbear"
DROPBEAR_DIR="/etc/dropbear"
DROPBEAR_PORT=109
DROPBEAR_BANNER="/etc/dropbear/banner.txt"
SYSTEMD_FILE="/etc/systemd/system/dropbear.service"
DROPBEAR_VERSION_MIN="2022.83"

# ==============================
# DETECTION VERSION OS
# ==============================
source /etc/os-release
OS_ID="$ID"
OS_VERSION="$VERSION_ID"

BANNER="SSH-2.0-dropbear_$DROPBEAR_VERSION_MIN"

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
# INSTALL DEPENDANCES
# ==============================
apt update -y
apt install -y build-essential zlib1g-dev wget tar dos2unix

# ==============================
# DROPBEAR INSTALL / COMPILE
# ==============================
NEED_COMPILE=false

if command -v dropbear >/dev/null 2>&1; then
    EXIST_VER=$(dropbear -V 2>&1 | awk '{print $2}' | tr -d 'v')
    if dpkg --compare-versions "$EXIST_VER" lt "$DROPBEAR_VERSION_MIN"; then
        warn "Version Dropbear ($EXIST_VER) trop ancienne. Compilation requise."
        NEED_COMPILE=true
    else
        info "Dropbear version $EXIST_VER déjà OK."
        DROPBEAR_BIN=$(command -v dropbear)
    fi
else
    info "Dropbear absent, compilation requise."
    NEED_COMPILE=true
fi

if [ "$NEED_COMPILE" = true ]; then
    info "Téléchargement et compilation Dropbear $DROPBEAR_VERSION_MIN..."
    cd /usr/local/src
    wget -q "https://matt.ucc.asn.au/dropbear/releases/dropbear-$DROPBEAR_VERSION_MIN.tar.bz2"
    tar -xjf "dropbear-$DROPBEAR_VERSION_MIN.tar.bz2"
    cd "dropbear-$DROPBEAR_VERSION_MIN"
    ./configure --prefix=/usr/local
    make && make install
    info "Dropbear compilé et installé dans /usr/local/bin/dropbear"
fi

# ==============================
# STOP ANCIEN SERVICE
# ==============================
info "Arrêt et désactivation de l’ancien service Dropbear..."
systemctl stop dropbear 2>/dev/null || true
systemctl disable dropbear 2>/dev/null || true

# ==============================
# CREATION DOSSIER ET CLES
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
            warn "Clé $key non supportée, ignorée"
        fi
    fi
done

if ls "$DROPBEAR_DIR"/* >/dev/null 2>&1; then
    chmod 600 "$DROPBEAR_DIR"/*
    chown root:root "$DROPBEAR_DIR"/*
else
    error "Aucune clé host générée ! Vérifier Dropbear"
fi

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
