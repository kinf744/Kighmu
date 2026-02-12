#!/bin/bash
set -euo pipefail

# ==============================
# VARIABLES
# ==============================
DROPBEAR_DIR="/etc/dropbear"
DROPBEAR_PORT=109
DROPBEAR_BANNER="/etc/dropbear/banner.txt"
SYSTEMD_FILE="/etc/systemd/system/dropbear-custom.service"
DROPBEAR_VERSION_MIN="2022.83"

# ==============================
# DETECTION VERSION OS
# ==============================
source /etc/os-release
OS_ID="$ID"
OS_VERSION="$VERSION_ID"

# ==============================
# COULEURS
# ==============================
RED='\u001B[0;31m'
GREEN='\u001B[0;32m'
YELLOW='\u001B[1;33m'
NC='\u001B[0m'

info(){ echo -e "${GREEN}[INFO]${NC} $1"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
error(){ echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ==============================
# ROOT CHECK
# ==============================
[ "$EUID" -ne 0 ] && { error "Exécuter en root"; }

# ==============================
# INSTALL DEPENDANCES
# ==============================
info "Mise à jour et installation des dépendances..."
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
    fi
else
    info "Dropbear absent, compilation requise."
    NEED_COMPILE=true
fi

if [ "$NEED_COMPILE" = true ]; then
    info "Téléchargement et compilation Dropbear $DROPBEAR_VERSION_MIN..."
    mkdir -p /usr/local/src
    cd /usr/local/src
    wget -q "https://matt.ucc.asn.au/dropbear/releases/dropbear-$DROPBEAR_VERSION_MIN.tar.bz2"
    tar -xjf "dropbear-$DROPBEAR_VERSION_MIN.tar.bz2"
    cd "dropbear-$DROPBEAR_VERSION_MIN"
    ./configure --prefix=/usr/local
    make && make install
    info "Dropbear compilé et installé dans /usr/local/bin/"
fi

# ==============================
# DETECTION BINAIRE CORRECTE (FIX PRINCIPAL)
# ==============================
if [ -x "/usr/local/bin/dropbear" ]; then
    DROPBEAR_BIN="/usr/local/bin/dropbear"
    DROPBEARKEY="/usr/local/bin/dropbearkey"
elif command -v dropbear >/dev/null 2>&1; then
    DROPBEAR_BIN="$(command -v dropbear)"
    DROPBEARKEY="$(command -v dropbearkey)"
else
    error "Binaire Dropbear introuvable !"
fi

info "Binaire détecté: $DROPBEAR_BIN"
info "dropbearkey: $DROPBEARKEY"
$DROPBEARKEY -V || error "dropbearkey ne fonctionne pas: $DROPBEARKEY"

# ==============================
# STOP ANCIEN SERVICE
# ==============================
info "Arrêt et désactivation de l'ancien service Dropbear..."
systemctl stop dropbear dropbear.service dropbear-custom.service 2>/dev/null || true
systemctl disable dropbear dropbear.service dropbear-custom.service 2>/dev/null || true

# ==============================
# CREATION DOSSIER ET CLES (FIX GÉNÉRATION)
# ==============================
info "Préparation des clés host Dropbear..."
mkdir -p "$DROPBEAR_DIR"
chmod 755 "$DROPBEAR_DIR"

for key in rsa ecdsa ed25519; do
    KEY_FILE="$DROPBEAR_DIR/dropbear_${key}_host_key"
    if [ ! -f "$KEY_FILE" ]; then
        info "Génération clé $key..."
        if "$DROPBEARKEY" -t "$key" -f "$KEY_FILE"; then
            info "✅ Clé $key générée"
        else
            warn "❌ Échec clé $key (ignorée)"
            rm -f "$KEY_FILE"
        fi
    else
        info "Clé $key déjà présente"
    fi
done

# Vérification critique
if ! ls "$DROPBEAR_DIR"/*_host_key >/dev/null 2>&1; then
    error "Aucune clé host générée !"
fi
chmod 600 "$DROPBEAR_DIR"/*_host_key
chown root:root "$DROPBEAR_DIR"/*_host_key
info "Clés prêtes: $(ls "$DROPBEAR_DIR"/*_host_key | xargs -n1 basename)"

# ==============================
# CREATION BANNER
# ==============================
info "Création du banner Dropbear..."
cat <<EOF > "$DROPBEAR_BANNER"
Dropbear SSH Server - $(hostname)
Ubuntu $OS_VERSION | Port: $DROPBEAR_PORT
EOF
chmod 644 "$DROPBEAR_BANNER"
chown root:root "$DROPBEAR_BANNER"

# ==============================
# CREATION SERVICE SYSTEMD
# ==============================
info "Création service systemd..."
cat > "$SYSTEMD_FILE" <<EOF
[Unit]
Description=Dropbear SSH Server Custom (port $DROPBEAR_PORT)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$DROPBEAR_BIN -F -E -p $DROPBEAR_PORT -w -g -b $DROPBEAR_BANNER -R
Restart=always
RestartSec=2
LimitNOFILE=1048576
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now dropbear-custom.service

# ==============================
# VERIFICATION FINALE
# ==============================
sleep 2
if systemctl is-active --quiet dropbear-custom.service && ss -tulpn | grep -q ":$DROPBEAR_PORT "; then
    info "🎉 ✅ Dropbear OK sur port $DROPBEAR_PORT !"
    info "🔗 Test: ssh -p $DROPBEAR_PORT root@$(hostname -I | awk '{print $1}')"
else
    warn "⚠️  Vérifier les logs:"
    systemctl status dropbear-custom.service --no-pager
    journalctl -u dropbear-custom.service -n 20 --no-pager
fi

info "📋 Status: systemctl status dropbear-custom.service"
info "📋 Logs:   journalctl -u dropbear-custom.service -f"
