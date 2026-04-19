#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  Installation automatique du Bot Telegram VLESS Generator
#  Compatible : Ubuntu 20.04 / 22.04 / 24.04
#  Fichier unique : vless_bot.py
# ═══════════════════════════════════════════════════════════

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
error()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
header() { echo -e "\n${BLUE}══════════════════════════════════════${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}══════════════════════════════════════${NC}"; }

# ─── Vérification root ───────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    error "Lance ce script en tant que root : sudo bash install.sh"
fi

# ─── Vérifier que vless_bot.py est présent ───────────────
if [ ! -f "vless_bot.py" ]; then
    error "vless_bot.py introuvable ! Place install.sh et vless_bot.py dans le même dossier."
fi

header "🤖 Installation Bot Telegram VLESS Generator"

# ─── Mise à jour système ─────────────────────────────────
header "1/6 — Mise à jour du système"
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq python3 python3-pip python3-venv curl wget gnupg2 apt-transport-https
log "Système mis à jour"

# ─── Google Cloud CLI ────────────────────────────────────
header "2/6 — Installation Google Cloud CLI"
if ! command -v gcloud &> /dev/null; then
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        | tee /etc/apt/sources.list.d/google-cloud-sdk.list
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
    apt-get update -qq
    apt-get install -y -qq google-cloud-cli
    log "Google Cloud CLI installé"
else
    log "Google Cloud CLI déjà présent"
fi

# ─── Création des dossiers ────────────────────────────────
header "3/6 — Création des dossiers"
mkdir -p /opt/vless-bot
mkdir -p /var/log/vless-bot
mkdir -p /var/lib/vless-bot
log "Dossiers créés"

# ─── Copie du fichier unique ──────────────────────────────
cp vless_bot.py /opt/vless-bot/vless_bot.py
log "vless_bot.py copié dans /opt/vless-bot/"

# ─── Environnement Python ────────────────────────────────
header "4/6 — Installation des dépendances Python"
cd /opt/vless-bot
python3 -m venv venv
source venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet "python-telegram-bot==21.0.1"
deactivate
log "Dépendances installées"

# ─── Saisie du token Telegram ────────────────────────────
header "5/6 — Configuration du token Telegram"
echo ""
warn "Il faut insérer ton token Telegram dans vless_bot.py"
echo ""
read -p "  🤖 Token Telegram (@BotFather) : " BOT_TOKEN_INPUT

if [ -n "$BOT_TOKEN_INPUT" ]; then
    # Remplace la valeur dans le fichier
    sed -i "s|BOT_TOKEN.*=.*\"TON_BOT_TOKEN_ICI\"|BOT_TOKEN          = \"${BOT_TOKEN_INPUT}\"|" \
        /opt/vless-bot/vless_bot.py
    log "Token inséré dans vless_bot.py"
else
    warn "Token ignoré — édite manuellement /opt/vless-bot/vless_bot.py (ligne BOT_TOKEN)"
fi

# ─── Service systemd ─────────────────────────────────────
header "6/6 — Création du service systemd"

cat > /etc/systemd/system/vless-bot.service << 'EOF'
[Unit]
Description=Bot Telegram VLESS Generator
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/vless-bot
ExecStart=/opt/vless-bot/venv/bin/python3 /opt/vless-bot/vless_bot.py
Restart=always
RestartSec=10
StandardOutput=append:/var/log/vless-bot/bot.log
StandardError=append:/var/log/vless-bot/error.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vless-bot
log "Service systemd créé et activé"

# ─── Résumé ───────────────────────────────────────────────
header "✅ Installation terminée !"
echo ""
echo -e "  📄 Bot             : ${GREEN}/opt/vless-bot/vless_bot.py${NC}"
echo -e "  📋 Logs            : ${GREEN}/var/log/vless-bot/bot.log${NC}"
echo -e "  🗄  Base de données : ${GREEN}/var/lib/vless-bot/vless_bot.db${NC}"
echo ""
echo -e "  ${YELLOW}Commandes utiles :${NC}"
echo -e "  • Démarrer  : ${GREEN}systemctl start vless-bot${NC}"
echo -e "  • Arrêter   : ${GREEN}systemctl stop vless-bot${NC}"
echo -e "  • Statut    : ${GREEN}systemctl status vless-bot${NC}"
echo -e "  • Logs live : ${GREEN}tail -f /var/log/vless-bot/bot.log${NC}"
echo -e "  • Modifier  : ${GREEN}nano /opt/vless-bot/vless_bot.py${NC}"
echo ""
echo -e "  ${YELLOW}⚠️  Avant de démarrer :${NC}"
echo -e "  1. Authentifie gcloud : ${GREEN}gcloud auth login${NC}"
echo -e "  2. Démarre le bot     : ${GREEN}systemctl start vless-bot${NC}"
echo ""
