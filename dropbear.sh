#!/bin/bash
set -euo pipefail

# ==============================
# VARIABLES
# ==============================
DROPBEAR_BIN="/usr/sbin/dropbear"
DROPBEAR_DIR="/etc/dropbear"
DROPBEAR_PORT=109
LOG_FILE="/var/log/dropbear-port109.log"

# ==============================
# DETECTION VERSION OS (DEBIAN + UBUNTU)
# ==============================
source /etc/os-release

OS_ID="$ID"
OS_VERSION="$VERSION_ID"

case "$OS_ID-$OS_VERSION" in
    ubuntu-20.04) DROPBEAR_VER="2019.78" ;;
    ubuntu-22.04) DROPBEAR_VER="2022.83" ;;
    ubuntu-24.04) DROPBEAR_VER="2024.84" ;;
    debian-10)    DROPBEAR_VER="2019.78" ;;
    debian-11)    DROPBEAR_VER="2022.83" ;;
    debian-12)    DROPBEAR_VER="2022.83" ;;
    *)            DROPBEAR_VER="2022.83" ;;
esac
BANNER="SSH-2.0-dropbear_$DROPBEAR_VER"

# ==============================
# COULEURS + FONCTIONS
# ==============================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ==============================
# ROOT CHECK
# ==============================
if [ "$EUID" -ne 0 ]; then
    error "Exécuter ce script en root"
    exit 1
fi

clear
echo "=========================================="
echo "   KIGHMU DROPBEAR WATCHDOG"
echo "   Bannière : $BANNER"
echo "=========================================="
echo "IP : $(hostname -I | awk '{print $1}')"
echo "=========================================="
echo

# ==============================
# INSTALL DROPBEAR
# ==============================
if ! command -v dropbear >/dev/null 2>&1; then
    info "Installation de Dropbear..."
    apt update -y
    apt install -y dropbear
else
    info "Dropbear déjà installé"
fi

# ==============================
# PREPARATION DES CLES
# ==============================
info "Vérification des clés Dropbear..."
mkdir -p "$DROPBEAR_DIR"
chmod 755 "$DROPBEAR_DIR"

if [ ! -f "$DROPBEAR_DIR/dropbear_rsa_host_key" ]; then
    info "Génération clé RSA Dropbear..."
    dropbearkey -t rsa -f "$DROPBEAR_DIR/dropbear_rsa_host_key"
fi

chmod 600 "$DROPBEAR_DIR"/*

# ==============================
# WATCHDOG PORT 109
# ==============================
info "Watchdog actif : Dropbear attend le port ${DROPBEAR_PORT}"
warn "Si OpenSSH occupe le port ${DROPBEAR_PORT}, Dropbear patientera"

while true; do
    # Si Dropbear écoute déjà → ne rien faire
    if ss -tlnp 2>/dev/null | grep -q ":$DROPBEAR_PORT.*dropbear"; then
        sleep 2
        continue
    fi

    # Si le port 109 est libre → lancer Dropbear
    if ! ss -tlnp 2>/dev/null | grep -q ":$DROPBEAR_PORT "; then
        echo "[$(date)] Port ${DROPBEAR_PORT} libre → lancement Dropbear ($BANNER)" >> "$LOG_FILE"

        $DROPBEAR_BIN \
            -F \
            -E \
            -p "$DROPBEAR_PORT" \
            -w \
            -s \
            -g \
            >> "$LOG_FILE" 2>&1 &

        sleep 1
    fi

    sleep 2
done
