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

# Vérifier que le script est lancé en root
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Erreur : ce script doit être lancé avec les droits root.${RESET}"
  exit 1
fi

# Charger les infos globales Kighmu
if [ -f ~/.kighmu_info ]; then
    source ~/.kighmu_info
else
    echo -e "${RED}Erreur : fichier ~/.kighmu_info introuvable, informations globales manquantes.${RESET}"
    exit 1
fi

# ==============================
# AUTO-DÉTECTION OpenSSH / Dropbear
# ==============================
detect_ssh_shell() {
    if pgrep -x dropbear >/dev/null 2>&1 || systemctl is-active --quiet dropbear 2>/dev/null; then
        echo "/usr/sbin/nologin"
        return
    fi

    if pgrep -x sshd >/dev/null 2>&1 || systemctl is-active --quiet ssh 2>/dev/null; then
        echo "/bin/bash"
        return
    fi

    echo "/usr/sbin/nologin"
}

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
LOCK_FILE="/etc/kighmu/users.list.lock"
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

read -sp "Mot de passe : " password
echo
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

# ==============================
# Création utilisateur (AUTO)
# ==============================
USER_SHELL=$(detect_ssh_shell)

if ! useradd -M -s "$USER_SHELL" "$username"; then
  echo -e "${RED}Erreur lors de la création du compte.${RESET}"
  exit 1
fi

if ! echo "$username:$password" | chpasswd; then
  echo -e "${RED}Erreur lors de la définition du mot de passe.${RESET}"
  userdel --force "$username"
  exit 1
fi

expire_date=$(date -d "+$minutes minutes" '+%Y-%m-%d %H:%M:%S')
HOST_IP=$(curl -s https://api.ipify.org)

# Écriture sécurisée avec verrou
(
  flock -x 200 || { echo -e "${RED}Impossible d'obtenir le verrou sur $USER_FILE.${RESET}"; exit 1; }
  echo "$username|$password|$limite|$expire_date|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> "$USER_FILE"
) 200>"$LOCK_FILE"

# ==============================
# Script de suppression automatique
# ==============================
CLEAN_SCRIPT="$TEST_DIR/$username-clean.sh"
cat > "$CLEAN_SCRIPT" <<EOF
#!/bin/bash
pkill -u "$username"
userdel --force "$username"
(
  flock -x 200 || exit 1
  grep -v "^$username|" $USER_FILE > /tmp/users.tmp
  mv /tmp/users.tmp $USER_FILE
) 200>"$LOCK_FILE"
rm -f "$CLEAN_SCRIPT"
exit 0
EOF
chmod +x "$CLEAN_SCRIPT"

# Planification suppression
if command -v at >/dev/null 2>&1; then
    echo "bash $CLEAN_SCRIPT" | at now + "$minutes" min 2>/dev/null || \
      echo -e "${YELLOW}Échec de la planification avec at.${RESET}"
else
    echo -e "${YELLOW}La commande 'at' n'est pas installée.${RESET}"
fi

# ==============================
# Home minimal + bannière
# ==============================
BANNER_PATH="/etc/ssh/sshd_banner"
USER_HOME="/home/$username"

if [ ! -d "$USER_HOME" ]; then
    mkdir -p "$USER_HOME"
    chown "$username:$username" "$USER_HOME"
fi

cat > "$USER_HOME/.bashrc" <<EOF
if [ -f $BANNER_PATH ]; then
    cat $BANNER_PATH
fi
EOF

chown "$username:$username" "$USER_HOME/.bashrc"
chmod 644 "$USER_HOME/.bashrc"

# ==============================
# Affichage final
# ==============================
echo -e "✨ 𝙉𝙊𝙐𝙑𝙀𝘼𝙐 𝙐𝙏𝙄𝙇𝙄𝙎𝘼𝙏𝙀𝙐𝙍 𝙏𝙀𝙎𝙏 𝘾𝙍𝙀‌𝙀‌ ✨"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "🔐 𝙋𝙊𝙍𝙏𝙎 𝘿𝙄𝙎𝙋𝙊𝙉𝙄𝘽𝙇𝙀𝙎 :"
echo -e "∘ SSH: 22          ∘ System-DNS: 53"
echo -e "∘ SSH WS: 80       ∘ WEB-NGINX: 81"
echo -e "∘ DROPBEAR: 2222   ∘ SSL: 444"
echo -e "∘ BadVPN: 7200     ∘ BadVPN: 7300"
echo -e "∘ FASTDNS: 5300    ∘ UDP-Custom: 54000"
echo -e "∘ Hysteria: 22000  ∘ Proxy WS: 9090"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${YELLOW}🌍 𝘿𝙊𝙈𝘼𝙄𝙉𝙀 :${RESET} $DOMAIN"
echo -e "${YELLOW}📌 𝙄𝙋 𝙃𝙊𝙎𝙏 :${RESET} $HOST_IP"
echo -e "${YELLOW}👤 𝙐𝙏𝙄𝙇𝙄𝙎𝘼𝙏𝙀𝙐𝙍 :${RESET} $username"
echo -e "${YELLOW}🔑 𝙈𝙊𝙏 𝘿𝙀 𝙋𝘼𝙎𝙎𝙀 :${RESET} $password"
echo -e "${YELLOW}📦 𝙇𝙄𝙈𝙄𝙏𝙀 :${RESET} $limite"
echo -e "${YELLOW}📅 𝘿𝘼𝙏𝙀 𝘿'𝙀𝙓𝙋𝙄𝙍𝘼𝙏𝙄𝙊𝙉 :${RESET} $expire_date"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo "📲 𝘼𝙋𝙋𝙎 : HTTP Injector, CUSTOM, SOCKSIP TUNNEL, SSC, etc."
echo ""
echo -e "➡️ 𝙎𝙎𝙃 𝙒𝙎 : ${GREEN}$DOMAIN:80@$username:$password${RESET}"
echo -e "➡️ 𝙎𝙎𝙇/𝙏𝙇𝙎 : ${GREEN}$HOST_IP:444@$username:$password${RESET}"
echo -e "➡️ 𝙋𝙍𝙊𝙓𝙔 𝙒𝙎 : ${GREEN}$HOST_IP:9090@$username:$password${RESET}"
echo -e "➡️ 𝙎𝙎𝙃 𝙐𝘿𝙋 : ${GREEN}$HOST_IP:54000@$username:$password${RESET}"
echo -e "➡️ 𝙃𝙔𝙎𝙏𝙀𝙍𝙄𝘼 : ${GREEN}$DOMAIN:22000@$username:$password${RESET}"
echo ""
echo -e "📜 𝙋𝘼𝙔𝙇𝙊𝘼𝘿 𝙒𝙎:"
echo -e "${GREEN}GET / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]${RESET}"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "🚀 𝘾𝙊𝙉𝙁𝙄𝙂 𝙁𝘼𝙎𝙏𝘿𝙉𝙎 (5300) 
echo -e "${YELLOW}🔐 Pub KEY:${RESET}"
echo "$SLOWDNS_KEY"
echo -e "${YELLOW}NameServer:
echo -e "${RESET} $SLOWDNS_NS"
echo -e ""
echo -e "${GREEN}✅ 𝘾𝙊𝙈𝙋𝙏𝙀 𝘾𝙍𝙀‌𝙀‌ 𝘼𝙑𝙀𝘾 𝙎𝙐𝘾𝘾𝙀‌𝙎${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

read -p "Appuyez sur Entrée pour revenir au menu..."
