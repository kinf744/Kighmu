#!/bin/bash
set -euo pipefail

# ==============================
# VARIABLES GLOBALES
# ==============================
DROPBEAR_DIR="/etc/dropbear"
DROPBEAR_PORT=109
DROPBEAR_BANNER="/etc/dropbear/banner.txt"
SYSTEMD_FILE="/etc/systemd/system/dropbear-custom.service"

# ==============================
# DETECTION SYSTEME
# ==============================
source /etc/os-release 2>/dev/null || source /etc/lsb-release 2>/dev/null || {
    echo "❌ Système non supporté (Ubuntu/Debian requis)" >&2
    exit 1
}

# Détection famille + version
if [[ "$ID" == "ubuntu" || "$ID_LIKE" == *"ubuntu"* || "$DISTRIB_ID" == "Ubuntu" ]]; then
    FAMILY="ubuntu"
    OS_VERSION="${VERSION_ID:-$DISTRIB_RELEASE}"
elif [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]]; then
    FAMILY="debian"
    OS_VERSION="${VERSION_ID}"
else
    echo "❌ Seulement Ubuntu/Debian supportés" >&2
    exit 1
fi

# Version majeure
OS_MAJOR=$(echo "$OS_VERSION" | cut -d. -f1)

info "🖥️  Système détecté: ${FAMILY^} $OS_VERSION (v$OS_MAJOR)"

# ==============================
# COULEURS + FONCTIONS
# ==============================
RED='\u001B[0;31m'; GREEN='\u001B[0;32m'; YELLOW='\u001B[1;33m'; NC='\u001B[0m'
info(){ echo -e "${GREEN}[INFO]${NC} $1"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
error(){ echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Root check
[ "$EUID" -ne 0 ] && { error "Exécuter en root"; }

# ==============================
# STRATEGIE D'INSTALL PAR VERSION
# ==============================
install_dropbear() {
    case $FAMILY in
        ubuntu)
            case $OS_MAJOR in
                20|22|24)
                    info "Installation Dropbear via APT (paquet officiel)"
                    apt update
                    apt install -y dropbear-bin dropbear-initramfs  # dropbear-bin = outils + dropbear-initramfs = clés auto
                    return 0
                    ;;
                *)
                    compile_dropbear
                    ;;
            esac
            ;;
        debian)
            case $OS_MAJOR in
                11|12)
                    info "Installation Dropbear via APT (Debian)"
                    apt update
                    apt install -y dropbear-bin dropbear-run
                    return 0
                    ;;
                *)
                    compile_dropbear
                    ;;
            esac
            ;;
    esac
}

compile_dropbear() {
    local VERSION="2022.83"
    info "Compilation Dropbear $VERSION (fallback)"
    
    apt update
    apt install -y build-essential zlib1g-dev wget tar
    
    cd /usr/local/src
    wget -q "https://matt.ucc.asn.au/dropbear/releases/dropbear-$VERSION.tar.bz2"
    tar -xjf "dropbear-$VERSION.tar.bz2" && rm -f "dropbear-$VERSION.tar.bz2"
    cd "dropbear-$VERSION"
    ./configure --prefix=/usr/local
    make && make install
    
    echo "/usr/local/bin" > /etc/ld.so.conf.d/dropbear.conf
    ldconfig
}

# ==============================
# INSTALL + CONFIG
# ==============================
info "🚀 Installation Dropbear adaptée à $FAMILY $OS_VERSION..."
install_dropbear

# Détection binaire installé
if [ -x "/usr/local/bin/dropbear" ]; then
    DROPBEAR_BIN="/usr/local/bin/dropbear"
    DROPBEARKEY="/usr/local/bin/dropbearkey"
elif command -v dropbear >/dev/null 2>&1; then
    DROPBEAR_BIN="$(command -v dropbear)"
    DROPBEARKEY="$(command -v dropbearkey)"
else
    error "Binaire Dropbear introuvable après installation"
fi

info "Binaire: $DROPBEAR_BIN (version: $($DROPBEAR_BIN -V 2>&1 | head -n1))"

# ==============================
# ARRET SERVICES ANCIENS
# ==============================
info "🛑 Arrêt services Dropbear existants..."
systemctl stop dropbear dropbear.service dropbear-custom.service 2>/dev/null | grep -v "not-loaded" || true
systemctl disable dropbear dropbear.service dropbear-custom.service 2>/dev/null | grep -v "not-loaded" || true

# ==============================
# CONFIG + CLES
# ==============================
info "🔐 Configuration Dropbear personnalisée..."

# Dossier + clés
mkdir -p "$DROPBEAR_DIR"
chmod 755 "$DROPBEAR_DIR"

# Génération clés (seulement si absentes)
for type in rsa ecdsa ed25519; do
    keyfile="$DROPBEAR_DIR/dropbear_${type}_host_key"
    if [[ ! -f "$keyfile" ]]; then
        info "Génération clé $type..."
        $DROPBEARKEY -t "$type" -f "$keyfile" || {
            warn "Clé $type échouée (ignorée)"
            rm -f "$keyfile"
        }
    fi
done

# Vérif critique
if ! ls "$DROPBEAR_DIR"/*host_key >/dev/null 2>&1; then
    error "Aucune clé host générée !"
fi
chmod 600 "$DROPBEAR_DIR"/*host_key
chown root:root "$DROPBEAR_DIR"/*host_key

# Banner
cat > "$DROPBEAR_BANNER" << EOF
Dropbear SSH Server - $(hostname) 
Ubuntu/$OS_VERSION | Port: $DROPBEAR_PORT
EOF
chmod 644 "$DROPBEAR_BANNER"

# ==============================
# SYSTEMD ADAPTE
# ==============================
info "⚙️  Service systemd personnalisé..."

cat > "$SYSTEMD_FILE" << EOF
[Unit]
Description=Dropbear SSH Server Custom (port $DROPBEAR_PORT)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$DROPBEAR_BIN -F -E \\
    -p $DROPBEAR_PORT \\
    -w -g \\
    -b $DROPBEAR_BANNER \\
    -R \\
    -K 300 -I 180
Restart=always
RestartSec=3
User=root
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "$SYSTEMD_FILE"

# ==============================
# VERIFICATIONS FINALES
# ==============================
sleep 2

if systemctl is-active --quiet dropbear-custom.service; then
    if ss -tulpn | grep -q ":$DROPBEAR_PORT "; then
        info "🎉 ✅ Dropbear ${FAMILY^} $OS_VERSION - PORT $DROPBEAR_PORT OK !"
        info "🔗 Test: ssh -p $DROPBEAR_PORT root@$(hostname -I | awk '{print $1}')"
    else
        warn "⚠️ Service OK mais port fermé (firewall?)"
        warn "🔍 Logs: journalctl -u dropbear-custom.service -f"
    fi
else
    error "❌ Service échoué !"
    systemctl status dropbear-custom.service --no-pager
    journalctl -u dropbear-custom.service -n 50 --no-pager
fi

info "📋 Status: systemctl status dropbear-custom.service"
info "📋 Logs:   journalctl -u dropbear-custom.service -f"
