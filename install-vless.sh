#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  Bot Telegram VLESS Generator — Panneau de contrôle
#  Compatible : Ubuntu 20.04 / 22.04 / 24.04
# ═══════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()   { echo -e "  ${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "  ${YELLOW}[!]${NC} $1"; }
error() { echo -e "  ${RED}[✗]${NC} $1"; }

# ─── Statut du bot ───────────────────────────────────────
get_status() {
    if systemctl is-active --quiet vless-bot 2>/dev/null; then
        echo -e "${GREEN}${BOLD}● ACTIF${NC}"
    else
        echo -e "${RED}${BOLD}○ INACTIF${NC}"
    fi
}

# ─── Panneau de contrôle ─────────────────────────────────
show_menu() {
    clear
    echo ""
    echo -e "${BLUE}${BOLD}  ╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}${BOLD}  ║     🤖  Bot Telegram VLESS Generator         ║${NC}"
    echo -e "${BLUE}${BOLD}  ╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Statut du bot :  $(get_status)"
    echo ""
    echo -e "${CYAN}  ┌──────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}  │${NC}                                              ${CYAN}│${NC}"
    echo -e "${CYAN}  │${NC}   ${BOLD}1.${NC}  🚀  Installer et lancer le bot           ${CYAN}│${NC}"
    echo -e "${CYAN}  │${NC}                                              ${CYAN}│${NC}"
    echo -e "${CYAN}  │${NC}   ${BOLD}2.${NC}  🗑️   Désinstaller le bot                   ${CYAN}│${NC}"
    echo -e "${CYAN}  │${NC}                                              ${CYAN}│${NC}"
    echo -e "${CYAN}  │${NC}   ${BOLD}3.${NC}  ❌  Quitter                                ${CYAN}│${NC}"
    echo -e "${CYAN}  │${NC}                                              ${CYAN}│${NC}"
    echo -e "${CYAN}  └──────────────────────────────────────────────┘${NC}"
    echo ""
    echo -ne "  ${BOLD}Choix [1-3] :${NC} "
}

# ═══════════════════════════════════════════════════════════
#  OPTION 1 — INSTALLATION
# ═══════════════════════════════════════════════════════════
install_bot() {
    clear
    echo ""
    echo -e "${BLUE}${BOLD}  ══════════════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}    🚀  Installation du bot${NC}"
    echo -e "${BLUE}${BOLD}  ══════════════════════════════════════════════${NC}"
    echo ""

    # Vérification root
    if [ "$EUID" -ne 0 ]; then
        error "Lance ce script en tant que root : sudo bash install.sh"
        echo ""
        read -p "  Appuie sur Entrée pour revenir au menu…"
        return
    fi

    # Chercher vless_bot.py : d'abord dans le dossier courant, sinon dans ~/Kighmu/
    if [ -f "vless_bot.py" ]; then
        VLESS_BOT_SRC="vless_bot.py"
    elif [ -f "$HOME/Kighmu/vless_bot.py" ]; then
        VLESS_BOT_SRC="$HOME/Kighmu/vless_bot.py"
        log "vless_bot.py trouvé dans $HOME/Kighmu/"
    else
        error "vless_bot.py introuvable !"
        warn "Chemin vérifié : $(pwd)/vless_bot.py"
        warn "Chemin vérifié : $HOME/Kighmu/vless_bot.py"
        echo ""
        read -p "  Appuie sur Entrée pour revenir au menu…"
        return
    fi

    # Vérifier si déjà installé et actif
    if systemctl is-active --quiet vless-bot 2>/dev/null; then
        warn "Le bot est déjà installé et actif."
        echo ""
        read -p "  Appuie sur Entrée pour revenir au menu…"
        return
    fi

    # [1/6] Mise à jour système
    echo -e "  ${YELLOW}[1/6]${NC} Mise à jour du système…"
    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get install -y -qq python3 python3-pip python3-venv curl wget gnupg2 apt-transport-https
    log "Système mis à jour"

    # [2/6] Google Cloud CLI
    echo ""
    echo -e "  ${YELLOW}[2/6]${NC} Installation Google Cloud CLI…"
    if ! command -v gcloud &> /dev/null; then
        echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
            | tee /etc/apt/sources.list.d/google-cloud-sdk.list > /dev/null
        curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
            | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
        apt-get update -qq
        apt-get install -y -qq google-cloud-cli
        log "Google Cloud CLI installé"
    else
        log "Google Cloud CLI déjà présent"
    fi

    # [3/6] Dossiers + copie fichier
    echo ""
    echo -e "  ${YELLOW}[3/6]${NC} Création des dossiers…"
    mkdir -p /opt/vless-bot
    mkdir -p /var/log/vless-bot
    mkdir -p /var/lib/vless-bot
    cp "$VLESS_BOT_SRC" /opt/vless-bot/vless_bot.py
    log "vless_bot.py copié dans /opt/vless-bot/"

    # [4/6] Dépendances Python
    echo ""
    echo -e "  ${YELLOW}[4/6]${NC} Installation des dépendances Python…"
    cd /opt/vless-bot
    python3 -m venv venv
    source venv/bin/activate
    pip install --quiet --upgrade pip
    pip install --quiet "python-telegram-bot==21.0.1"
    deactivate
    log "python-telegram-bot installé"

    # [5/6] Token Telegram
    echo ""
    echo -e "  ${YELLOW}[5/6]${NC} Configuration du token Telegram…"
    echo ""
    read -p "  🤖 Token Telegram (@BotFather) : " BOT_TOKEN_INPUT
    if [ -n "$BOT_TOKEN_INPUT" ]; then
        sed -i "s|BOT_TOKEN.*=.*\"TON_BOT_TOKEN_ICI\"|BOT_TOKEN          = \"${BOT_TOKEN_INPUT}\"|" \
            /opt/vless-bot/vless_bot.py
        log "Token inséré dans vless_bot.py"
    else
        warn "Token ignoré — édite manuellement /opt/vless-bot/vless_bot.py"
    fi

    # [6/6] Service systemd
    echo ""
    echo -e "  ${YELLOW}[6/6]${NC} Création du service systemd…"
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
    systemctl enable vless-bot > /dev/null 2>&1
    log "Service systemd créé et activé"

    # Lancement
    echo ""
    echo -e "  ${YELLOW}──────────────────────────────────────────────${NC}"
    warn "Avant de démarrer, authentifie gcloud sur ton VPS :"
    echo -e "  ${GREEN}gcloud auth login${NC}"
    echo -e "  ${YELLOW}──────────────────────────────────────────────${NC}"
    echo ""
    read -p "  Lancer le bot maintenant ? [o/N] : " LAUNCH
    if [[ "$LAUNCH" =~ ^[oO]$ ]]; then
        systemctl start vless-bot
        sleep 2
        echo ""
        if systemctl is-active --quiet vless-bot; then
            echo -e "  ${GREEN}${BOLD}╔══════════════════════════════════════╗${NC}"
            echo -e "  ${GREEN}${BOLD}║   ✅  Bot démarré avec succès !       ║${NC}"
            echo -e "  ${GREEN}${BOLD}╚══════════════════════════════════════╝${NC}"
        else
            echo -e "  ${RED}${BOLD}╔══════════════════════════════════════╗${NC}"
            echo -e "  ${RED}${BOLD}║   ✗  Échec du démarrage du bot        ║${NC}"
            echo -e "  ${RED}${BOLD}╚══════════════════════════════════════╝${NC}"
            error "Vérifie les logs : tail -f /var/log/vless-bot/error.log"
        fi
    fi

    echo ""
    echo -e "  ${CYAN}Logs en direct :${NC} tail -f /var/log/vless-bot/bot.log"
    echo ""
    read -p "  Appuie sur Entrée pour revenir au menu…"
}

# ═══════════════════════════════════════════════════════════
#  OPTION 2 — DÉSINSTALLATION
# ═══════════════════════════════════════════════════════════
uninstall_bot() {
    clear
    echo ""
    echo -e "${RED}${BOLD}  ══════════════════════════════════════════════${NC}"
    echo -e "${RED}${BOLD}    🗑️   Désinstallation du bot${NC}"
    echo -e "${RED}${BOLD}  ══════════════════════════════════════════════${NC}"
    echo ""

    if [ "$EUID" -ne 0 ]; then
        error "Lance ce script en tant que root."
        echo ""
        read -p "  Appuie sur Entrée pour revenir au menu…"
        return
    fi

    warn "Cette action supprime le bot, les logs et la base de données."
    echo ""
    read -p "  Confirmer la désinstallation ? [o/N] : " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[oO]$ ]]; then
        warn "Désinstallation annulée."
        echo ""
        read -p "  Appuie sur Entrée pour revenir au menu…"
        return
    fi

    echo ""
    # Arrêt service
    systemctl stop vless-bot 2>/dev/null  && log "Service arrêté"      || warn "Service déjà arrêté"
    systemctl disable vless-bot 2>/dev/null
    rm -f /etc/systemd/system/vless-bot.service
    systemctl daemon-reload
    log "Service systemd supprimé"

    # Suppression fichiers
    rm -rf /opt/vless-bot   && log "Fichiers supprimés  (/opt/vless-bot)"
    rm -rf /var/log/vless-bot && log "Logs supprimés      (/var/log/vless-bot)"
    rm -rf /var/lib/vless-bot && log "Base supprimée      (/var/lib/vless-bot)"

    echo ""
    echo -e "  ${GREEN}${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "  ${GREEN}${BOLD}║   ✅  Bot désinstallé avec succès !   ║${NC}"
    echo -e "  ${GREEN}${BOLD}╚══════════════════════════════════════╝${NC}"
    echo ""
    read -p "  Appuie sur Entrée pour revenir au menu…"
}

# ═══════════════════════════════════════════════════════════
#  BOUCLE PRINCIPALE
# ═══════════════════════════════════════════════════════════
while true; do
    show_menu
    read -r choice
    case "$choice" in
        1) install_bot   ;;
        2) uninstall_bot ;;
        3)
            clear
            echo ""
            echo -e "  ${GREEN}À bientôt !${NC}"
            echo ""
            exit 0
            ;;
        *)
            echo -e "\n  ${RED}Option invalide. Choisis 1, 2 ou 3.${NC}"
            sleep 1
            ;;
    esac
done
