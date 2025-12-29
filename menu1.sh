#!/bin/bash
# menu1.sh
# Créer un utilisateur normal et sauvegarder ses infos
set -euo pipefail

# ===============================
# DÉTECTION MODE BOT TELEGRAM
# ===============================
BOT_MODE=false
if [[ $# -ge 4 ]]; then
    BOT_MODE=true
    username="$1"
    password="$2"
    limite="$3"
    days="$4"
fi

# ===============================
# DÉFINITION DES COULEURS
# ===============================
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# Désactiver clear en mode bot
$BOT_MODE || clear

# ===============================
# CHARGEMENT CONFIG GLOBALE
# ===============================
if [ -f ~/.kighmu_info ]; then
    source ~/.kighmu_info
else
    echo -e "${RED}Erreur : fichier ~/.kighmu_info introuvable, informations globales manquantes.${RESET}"
    $BOT_MODE && exit 1
    read -p "Appuyez sur Entrée pour revenir au menu..."
    exit 1
fi

# ===============================
# SLOWDNS
# ===============================
if [ -f /etc/slowdns/server.pub ]; then
    SLOWDNS_KEY=$(cat /etc/slowdns/server.pub)
else
    SLOWDNS_KEY="${RED}Clé publique SlowDNS non trouvée!${RESET}"
fi

if [ -f /etc/slowdns/ns.conf ]; then
    SLOWDNS_NS=$(cat /etc/slowdns/ns.conf)
else
    SLOWDNS_NS=""
    echo -e "${YELLOW}Attention : fichier /etc/slowdns/ns.conf introuvable. Poursuite sans NS.${RESET}"
fi

# ===============================
# ENTÊTE
# ===============================
echo -e "${CYAN}+==================================================+${RESET}"
echo -e "|                CRÉATION D'UTILISATEUR             |"
echo -e "${CYAN}+==================================================+${RESET}"

# ===============================
# SAISIE INFOS (LOCAL UNIQUEMENT)
# ===============================
if ! $BOT_MODE; then
    read -p "Nom d'utilisateur : " username
fi

if [[ -z "${username:-}" ]]; then
    echo -e "${RED}Nom d'utilisateur vide, annulation.${RESET}"
    exit 1
fi

if id "$username" &>/dev/null; then
    echo -e "${RED}L'utilisateur existe déjà.${RESET}"
    exit 1
fi

if ! $BOT_MODE; then
    read -p "Mot de passe : " password
    read -p "Nombre d'appareils autorisés : " limite
    read -p "Durée de validité (en jours) : " days
fi

# ===============================
# VALIDATION
# ===============================
if ! [[ "$limite" =~ ^[0-9]+$ ]] || ! [[ "$days" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Nombre d'appareils ou durée non valides.${RESET}"
    exit 1
fi

# ===============================
# EXPIRATION
# ===============================
expire_date=$(date -d "+$days days" '+%Y-%m-%d')

# ===============================
# CRÉATION UTILISATEUR
# ===============================
useradd -m -s /bin/bash "$username"
echo "$username:$password" | chpasswd
chage -E "$expire_date" "$username"

# ===============================
# FICHIER UTILISATEURS
# ===============================
USER_FILE="/etc/kighmu/users.list"
mkdir -p /etc/kighmu
touch "$USER_FILE"
chmod 600 "$USER_FILE"

HOST_IP=$(hostname -I | awk '{print $1}')

echo "$username|$password|$limite|$expire_date|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> "$USER_FILE"

# ===============================
# BANNER SSH
# ===============================
BANNER_PATH="/etc/ssh/sshd_banner"
USER_HOME="/home/$username"

mkdir -p "$USER_HOME"
chown "$username:$username" "$USER_HOME"

cat > "$USER_HOME/.bashrc" <<EOF
if [ -f $BANNER_PATH ]; then
    cat \$BANNER_PATH
fi
EOF

chown "$username:$username" "$USER_HOME/.bashrc"
chmod 644 "$USER_HOME/.bashrc"

# ===============================
# RÉSUMÉ FINAL (INCHANGÉ)
# ===============================
echo -e "${CYAN}+=================================================================+${RESET}"
echo -e "*NOUVEAU UTILISATEUR CRÉÉ*"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "∘ SSH: 22                  ∘ System-DNS: 53"
echo -e "∘ SSH WS: 80       ∘ WEB-NGINX: 81"
echo -e "∘ DROPBEAR: 2222             ∘ SSL: 444"
echo -e "∘ BadVPN: 7200             ∘ BadVPN: 7300"
echo -e "∘ FASTDNS: 5300            ∘ UDP-Custom: 1-65535"
echo -e "∘ Hysteria: 22000          ∘ Proxy WS: 9090"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${YELLOW}DOMAIN         :${RESET} $DOMAIN"
echo -e "${YELLOW}Host/IP-Address:${RESET} $HOST_IP"
echo -e "${YELLOW}UTILISATEUR    :${RESET} $username"
echo -e "${YELLOW}MOT DE PASSE   :${RESET} $password"
echo -e "${YELLOW}LIMITE         :${RESET} $limite"
echo -e "${YELLOW}DATE EXPIRÉE   :${RESET} $expire_date"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo "En APPS comme HTTP Injector, CUSTOM, SOCKSIP TUNNEL, SSC, etc."
echo ""
echo -e "🙍 SSH WS     : ${GREEN}$DOMAIN:80@$username:$password${RESET}"
echo -e "🙍 SSL/TLS(SNI)    : ${GREEN}$HOST_IP:444@$username:$password${RESET}"
echo -e "🙍 Proxy(WS)       : ${GREEN}$HOST_IP:9090@$username:$password${RESET}"
echo -e "🙍 SSH UDP         : ${GREEN}$HOST_IP:1-65535@$username:$password${RESET}"
echo -e "🙍 Hysteria (UDP)  : ${GREEN}$DOMAIN:22000@$username:$password${RESET}"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━  CONFIGS FASTDNS PORT 5300 ━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${YELLOW}Pub KEY :${RESET}"
echo "$SLOWDNS_KEY"
echo -e "${YELLOW}NameServer (NS) :${RESET} $SLOWDNS_NS"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}Compte créé avec succès${RESET}"

$BOT_MODE || read -p "Appuyez sur Entrée pour revenir au menu..."
