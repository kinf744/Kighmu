#!/bin/bash
# ===============================================
# Kighmu VPS Manager - Création Utilisateur Test
# ===============================================

# Couleurs (comme le panneau principal)
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# Charger les infos globales Kighmu
if [ -f ~/.kighmu_info ]; then
    source ~/.kighmu_info
else
    echo -e "${RED}Erreur : fichier ~/.kighmu_info introuvable, informations globales manquantes.${RESET}"
    exit 1
fi

# Charger la clé publique SlowDNS
if [ -f /etc/slowdns/server.pub ]; then
    SLOWDNS_KEY=$(< /etc/slowdns/server.pub)
else
    SLOWDNS_KEY="${RED}Clé publique SlowDNS non trouvée!${RESET}"
fi

# Charger le NameServer SlowDNS exact depuis le fichier de config
if [ -f /etc/slowdns/ns.conf ]; then
    SLOWDNS_NS=$(< /etc/slowdns/ns.conf)
else
    echo -e "${RED}Erreur : fichier /etc/slowdns/ns.conf introuvable.${RESET}"
    exit 1
fi

# Fichiers et dossiers nécessaires
USER_FILE="/etc/kighmu/users.list"
mkdir -p /etc/kighmu
touch "$USER_FILE"
chmod 600 "$USER_FILE"

TEST_DIR="/etc/kighmu/userteste"
mkdir -p "$TEST_DIR"

clear
echo -e "${CYAN}+==================================================+${RESET}"
echo -e "|              CRÉATION D'UTILISATEUR TEST          |"
echo -e "${CYAN}+==================================================+${RESET}"

# Lecture des informations
read -p "Nom d'utilisateur : " username
if [[ -z "$username" ]]; then
    echo -e "${RED}Nom d'utilisateur vide, annulation.${RESET}"
    exit 1
fi

if id "$username" &>/dev/null; then
    echo -e "${RED}Cet utilisateur existe déjà.${RESET}"
    exit 1
fi

read -p "Mot de passe : " password
if [[ -z "$password" ]]; then
    echo -e "${RED}Mot de passe vide, annulation.${RESET}"
    exit 1
fi

read -p "Nombre d'appareils autorisés : " limite
if ! [[ "$limite" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Limite invalide, annulation.${RESET}"
    exit 1
fi

read -p "Durée de validité (en minutes) : " minutes
if ! [[ "$minutes" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Durée invalide, annulation.${RESET}"
    exit 1
fi

useradd -M -s /bin/false "$username" || { echo -e "${RED}Erreur lors de la création du compte${RESET}"; exit 1; }
echo "$username:$password" | chpasswd

expire_date=$(date -d "+$minutes minutes" '+%Y-%m-%d %H:%M:%S')

HOST_IP=$(curl -s https://api.ipify.org)

echo "$username|$password|$limite|$expire_date|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> "$USER_FILE"

CLEAN_SCRIPT="$TEST_DIR/$username-clean.sh"
cat > "$CLEAN_SCRIPT" <<EOF
#!/bin/bash
pkill -f "$username"
userdel --force "$username"
grep -v "^$username|" $USER_FILE > /tmp/users.tmp && mv /tmp/users.tmp $USER_FILE
rm -f "$CLEAN_SCRIPT"
exit 0
EOF
chmod +x "$CLEAN_SCRIPT"

if ! command -v at >/dev/null 2>&1; then
    echo -e "${YELLOW}La commande 'at' n'est pas installée. Veuillez l'installer pour la suppression automatique.${RESET}"
else
    echo "bash $CLEAN_SCRIPT" | at now + "$minutes" minutes 2>/dev/null
fi

BANNER_PATH="/etc/ssh/sshd_banner"
USER_HOME="/home/$username"
if [ ! -d "$USER_HOME" ]; then
    mkdir -p "$USER_HOME"
    chown "$username":"$username" "$USER_HOME"
fi

echo -e "
# Affichage du banner Kighmu VPS Manager
if [ -f $BANNER_PATH ]; then
    cat \$BANNER_PATH
fi
" > "$USER_HOME/.bashrc"

chown "$username":"$username" "$USER_HOME/.bashrc"
chmod 644 "$USER_HOME/.bashrc"

echo -e "${CYAN}+==================================================+${RESET}"
echo -e "*NOUVEAU UTILISATEUR CRÉÉ*"
echo -e "${CYAN}──────────────────────────────────────────────${RESET}"
echo -e "${YELLOW}DOMAIN        :${RESET} $DOMAIN"
echo -e "${YELLOW}Adresse IP    :${RESET} $HOST_IP"
echo -e "${YELLOW}Utilisateur   :${RESET} $username"
echo -e "${YELLOW}Mot de passe  :${RESET} $password"
echo -e "${YELLOW}Limite        :${RESET} $limite"
echo -e "${YELLOW}Date d'expire :${RESET} $expire_date"
echo -e "${CYAN}──────────────────────────────────────────────${RESET}"
echo "En APPS comme HTTP Injector, KPN Rev, etc."
echo ""
echo -e "🙍 HTTP-Direct  : ${GREEN}$HOST_IP:90@$username:$password${RESET}"
echo -e "🙍 SSL/TLS(SNI) : ${GREEN}$HOST_IP:443@$username:$password${RESET}"
echo -e "🙍 Proxy(WS)    : ${GREEN}$DOMAIN:8080@$username:$password${RESET}"
echo -e "🙍 SSH UDP     : ${GREEN}$HOST_IP:1-65535@$username:$password${RESET}"
echo ""
echo -e "${CYAN}───────────── CONFIG SLOWDNS ─────────────${RESET}"
echo -e "${YELLOW}Pub Key :${RESET}"
echo "$SLOWDNS_KEY"
echo -e "${YELLOW}NameServer (NS) :${RESET} $SLOWDNS_NS"
echo -e "${CYAN}──────────────────────────────────────────────${RESET}"
echo -e "${GREEN}Le compte sera supprimé automatiquement après $minutes minutes.${RESET}"
echo -e "${GREEN}Compte créé avec succès${RESET}"
