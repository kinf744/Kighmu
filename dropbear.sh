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
RED='\u001B[0;31m'
GREEN='\u001B[0;32m'
YELLOW='\u001B[1;33m'
NC='\u001B[0m'

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
        DROPBEAR_BIN=$(command -v dropbear)
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
    DROPBEAR_BIN="/usr/local/bin/dropbear"
    info "Dropbear compilé et installé dans $DROPBEAR_BIN"
    
    # Vérification binaire
    if [ ! -x "$DROPBEAR_BIN" ]; then
        error "Binaire Dropbear non trouvé après compilation: $DROPBEAR_BIN"
        exit 1
    fi
    info "Version compilée: $($DROPBEAR_BIN -V)"
fi

# ==============================
# STOP ANCIEN SERVICE
# ==============================
info "Arrêt et désactivation de l'ancien service Dropbear..."
systemctl stop dropbear 2>/dev/null || true
systemctl disable dropbear 2>/dev/null || true
systemctl stop dropbear.service 2>/dev/null || true
systemctl disable dropbear.service 2>/dev/null || true

# ==============================
# CREATION DOSSIER ET CLES
# ==============================
info "Préparation des clés host Dropbear..."
mkdir -p "$DROPBEAR_DIR"
chmod 755 "$DROPBEAR_DIR"

# Génération des clés (sans le test foireux /dev/null)
for key in rsa ecdsa ed25519; do
    KEY_FILE="$DROPBEAR_DIR/dropbear_${key}_host_key"
    if [ ! -f "$KEY_FILE" ]; then
        info "Génération clé $key..."
        if ! "$DROPBEAR_BIN"key -t "$key" -f "$KEY_FILE"; then
            warn "Échec génération clé $key (ignorée)"
            rm -f "$KEY_FILE"
        else
            info "Clé $key générée avec succès"
        fi
    else
        info "Clé $key déjà présente"
    fi
done

# Vérification critique: au moins UNE clé doit exister
if ! ls "$DROPBEAR_DIR"/*_host_key >/dev/null 2>&1; then
    error "Aucune clé host générée ! Dropbear ne démarrera pas."
    exit 1
fi

chmod 600 "$DROPBEAR_DIR"/*_host_key
chown root:root "$DROPBEAR_DIR"/*_host_key
info "Clés host prêtes: $(ls "$DROPBEAR_DIR"/*_host_key 2>/dev/null | xargs -n1 basename)"

# ==============================
# CREATION BANNER
# ==============================
info "Création du banner Dropbear..."
mkdir -p "$(dirname "$DROPBEAR_BANNER")"
cat <<EOF > "$DROPBEAR_BANNER"
Bienvenue sur Dropbear SSH Server
Port: $DROPBEAR_PORT | Version: $DROPBEAR_VERSION_MIN
EOF
dos2unix "$DROPBEAR_BANNER" 2>/dev/null || true
chmod 644 "$DROPBEAR_BANNER"
chown root:root "$DROPBEAR_BANNER"

# ==============================
# CREATION SERVICE SYSTEMD
# ==============================
info "Création service systemd..."
rm -f "$SYSTEMD_FILE"
cat <<EOF > "$SYSTEMD_FILE"
[Unit]
Description=Dropbear SSH Server on port $DROPBEAR_PORT
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=$DROPBEAR_BIN -F -E -p $DROPBEAR_PORT -w -g -b $DROPBEAR_BANNER -R
Restart=always
RestartSec=2
LimitNOFILE=1048576
LimitNPROC=65536
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# ==============================
# DEMARRAGE SERVICE
# ==============================
info "Démarrage service Dropbear..."
systemctl enable --now dropbear.service

# Attente et vérification
sleep 2
if systemctl is-active --quiet dropbear.service; then
    info "✅ Service Dropbear actif sur port $DROPBEAR_PORT"
else
    error "❌ Service Dropbear ne démarre pas !"
    systemctl status dropbear.service --no-pager
    journalctl -u dropbear.service -n 30 --no-pager
    exit 1
fi

# ==============================
# VERIFICATION PORT
# ==============================
if ss -tulpn | grep -q ":$DROPBEAR_PORT "; then
    info "✅ Port $DROPBEAR_PORT ouvert et à l'écoute"
    info "🔹 Test connexion: ssh -p $DROPBEAR_PORT root@IP_DU_SERVEUR"
else
    warn "⚠️  Port $DROPBEAR_PORT non visible (firewall?)"
    warn "🔹 Vérifier: journalctl -u dropbear.service -f"
fi

info "🎉 Installation Dropbear terminée avec succès !"
info "📋 Status: systemctl status dropbear.service"
info "📋 Logs:   journalctl -u dropbear.service -f"
