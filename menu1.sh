#!/bin/bash
# menu1.sh
# Création utilisateur SSH/WS + durée + quota Go (blocage si quota atteint)
set -euo pipefail

# ================= COULEURS =================
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

clear

# ================= CONFIG GLOBALE =================
if [ -f ~/.kighmu_info ]; then
    source ~/.kighmu_info
else
    echo -e "${RED}Erreur : ~/.kighmu_info introuvable.${RESET}"
    read -p "Entrée pour revenir..."
    exit 1
fi

# ================= SLOWDNS =================
if [ -f /etc/slowdns/server.pub ]; then
    SLOWDNS_KEY=$(cat /etc/slowdns/server.pub)
else
    SLOWDNS_KEY="NON DISPONIBLE"
fi

if [ -f /etc/slowdns/ns.conf ]; then
    SLOWDNS_NS=$(cat /etc/slowdns/ns.conf)
else
    SLOWDNS_NS=""
fi

# ================= EN-TÊTE =================
echo -e "${CYAN}+==================================================+${RESET}"
echo -e "|            CRÉATION D'UTILISATEUR SSH             |"
echo -e "${CYAN}+==================================================+${RESET}"

# ================= SAISIE =================
read -p "Nom d'utilisateur : " username

if id "$username" &>/dev/null; then
    echo -e "${RED}Utilisateur déjà existant.${RESET}"
    read -p "Entrée pour revenir..."
    exit 1
fi

read -p "Mot de passe : " password
read -p "Nombre d'appareils autorisés : " limite
read -p "Durée de validité (jours) : " days
read -p "Quota DATA (en Go) : " quota

# ================= VALIDATION =================
if ! [[ "$limite" =~ ^[0-9]+$ && "$days" =~ ^[0-9]+$ && "$quota" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Valeurs numériques invalides.${RESET}"
    read -p "Entrée pour revenir..."
    exit 1
fi

# ================= EXPIRATION =================
expire_date=$(date -d "+$days days" '+%Y-%m-%d')

# ================= CRÉATION USER =================
useradd -m -s /bin/bash "$username"
echo "$username:$password" | chpasswd
chage -E "$expire_date" "$username"

# ================= FICHIERS =================
mkdir -p /etc/kighmu
USER_FILE="/etc/kighmu/users.list"
touch "$USER_FILE"
chmod 600 "$USER_FILE"

HOST_IP=$(hostname -I | awk '{print $1}')

echo "$username|$password|$limite|$expire_date|$quota|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> "$USER_FILE"

# ================= QUOTA IPTABLES =================
QUOTA_DIR="/etc/sshws-quota"
QUOTA_DB="$QUOTA_DIR/users.db"

mkdir -p "$QUOTA_DIR"
touch "$QUOTA_DB"

# format: user:quotaGO:never
grep -q "^$username:" "$QUOTA_DB" || echo "$username:$quota:never" >> "$QUOTA_DB"

# ================= HOME + BANNER =================
BANNER_PATH="/etc/ssh/sshd_banner"
USER_HOME="/home/$username"

echo "
if [ -f $BANNER_PATH ]; then
  cat $BANNER_PATH
fi
" > "$USER_HOME/.bashrc"

chown "$username:$username" "$USER_HOME/.bashrc"
chmod 644 "$USER_HOME/.bashrc"

# ================= AFFICHAGE FINAL =================
echo -e "✨ 𝙉𝙊𝙐𝙑𝙀𝘼𝙐 𝙐𝙏𝙄𝙇𝙄𝙎𝘼𝙏𝙀𝙐𝙍 𝘾𝙍𝙀́𝙀́ ✨"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

echo -e "🔐 PORTS DISPONIBLES :"
echo -e "∘ SSH: 22          ∘ DNS: 53"
echo -e "∘ SSH WS: 80       ∘ NGINX: 81"
echo -e "∘ DROPBEAR: 2222   ∘ SSL: 444"
echo -e "∘ BadVPN: 7200/7300"
echo -e "∘ FASTDNS: 5300    ∘ UDP: 54000"
echo -e "∘ Hysteria: 22000  ∘ Proxy WS: 9090"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${YELLOW}🌍 DOMAINE :${RESET} $DOMAIN"
echo -e "${YELLOW}📌 IP HOST :${RESET} $HOST_IP"
echo -e "${YELLOW}👤 UTILISATEUR :${RESET} $username"
echo -e "${YELLOW}🔑 MOT DE PASSE :${RESET} $password"
echo -e "${YELLOW}📦 LIMITE APPAREILS :${RESET} $limite"
echo -e "${YELLOW}📊 QUOTA DATA :${RESET} $quota Go"
echo -e "${YELLOW}📅 EXPIRATION :${RESET} $expire_date"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo "📲 APPS : HTTP Injector, CUSTOM, SOCKSIP TUNNEL, SSC"
echo ""

echo -e "➡️ SSH WS : ${GREEN}$DOMAIN:80@$username:$password${RESET}"
echo -e "➡️ SSL/TLS : ${GREEN}$HOST_IP:444@$username:$password${RESET}"
echo -e "➡️ PROXY WS : ${GREEN}$HOST_IP:9090@$username:$password${RESET}"
echo -e "➡️ SSH UDP : ${GREEN}$HOST_IP:54000@$username:$password${RESET}"
echo -e "➡️ HYSTERIA : ${GREEN}$DOMAIN:22000@$username:$password${RESET}"

echo ""
echo -e "📜 PAYLOAD WS:"
echo -e "${GREEN}GET / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]Upgrade: websocket[crlf][crlf]${RESET}"

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "🚀 FASTDNS (5300)"
echo -e "${YELLOW}PUB KEY:${RESET}"
echo -e "$SLOWDNS_KEY"
echo -e "${YELLOW}NS:${RESET} $SLOWDNS_NS"

echo ""
echo -e "${GREEN}✅ COMPTE CRÉÉ AVEC SUCCÈS${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

read -p "Appuyez sur Entrée pour revenir au menu..."
