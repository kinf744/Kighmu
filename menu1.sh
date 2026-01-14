#!/bin/bash
# menu1.sh
# Création utilisateur SSH/WS + durée + quota Go (VNSTAT)
set -euo pipefail

# ================= COULEURS =================
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

clear

# ================= CONFIG GLOBALE =================
if [[ -f ~/.kighmu_info ]]; then
    source ~/.kighmu_info
else
    echo -e "${RED}Erreur : ~/.kighmu_info introuvable.${RESET}"
    read -p "Entrée pour revenir..."
    exit 1
fi

# ================= SLOWDNS =================
SLOWDNS_KEY=$(cat /etc/slowdns/server.pub 2>/dev/null || echo "NON DISPONIBLE")
SLOWDNS_NS=$(cat /etc/slowdns/ns.conf 2>/dev/null || echo "")

# ================= EN-TÊTE =================
echo -e "${CYAN}+==================================================+${RESET}"
echo -e "|        CRÉATION D'UTILISATEUR SSH (QUOTA)        |"
echo -e "${CYAN}+==================================================+${RESET}"

# ================= SAISIE =================
read -rp "Nom d'utilisateur : " username

if id "$username" &>/dev/null; then
    echo -e "${RED}Utilisateur déjà existant.${RESET}"
    read -p "Entrée pour revenir..."
    exit 1
fi

read -rp "Mot de passe : " password
read -rp "Nombre d'appareils autorisés : " limite
read -rp "Durée de validité (jours) : " days
read -rp "Quota DATA (en Go) : " quota

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

# ================= BASE KIGHMU =================
mkdir -p /etc/kighmu
USER_FILE="/etc/kighmu/users.list"
touch "$USER_FILE"
chmod 600 "$USER_FILE"

HOST_IP=$(hostname -I | awk '{print $1}')

# ===== AJOUT SÉCURISÉ (ANTI-DOUBLON) =====
grep -v "^$username|" "$USER_FILE" > /tmp/users.tmp || true
mv /tmp/users.tmp "$USER_FILE"

echo "$username|$password|$limite|$expire_date|$quota|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> "$USER_FILE"

# ================= QUOTA VNSTAT =================
QUOTA_DIR="/etc/sshws-quota"
QUOTA_DB="$QUOTA_DIR/users.db"
USAGE_DB="$QUOTA_DIR/usage.db"

mkdir -p "$QUOTA_DIR"
touch "$QUOTA_DB" "$USAGE_DB"

# Ajout quota si absent
grep -q "^$username:" "$QUOTA_DB" || echo "$username:$quota" >> "$QUOTA_DB"
grep -q "^$username:" "$USAGE_DB" || echo "$username:0" >> "$USAGE_DB"

# ================= BANNER =================
USER_HOME="/home/$username"
BANNER_PATH="/etc/ssh/sshd_banner"

cat > "$USER_HOME/.bashrc" <<EOF
[[ -f $BANNER_PATH ]] && cat $BANNER_PATH
EOF

chown "$username:$username" "$USER_HOME/.bashrc"
chmod 644 "$USER_HOME/.bashrc"

# ================= AFFICHAGE FINAL =================
CREATED_DATE=$(date '+%Y-%m-%d')
DAYS_LEFT=$(( ( $(date -d "$expire_date" +%s) - $(date +%s) ) / 86400 ))

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
echo -e "${YELLOW}🌍 DOMAINE           :${RESET} $DOMAIN"
echo -e "${YELLOW}📌 IP HOST           :${RESET} $HOST_IP"
echo -e "${YELLOW}👤 UTILISATEUR       :${RESET} $username"
echo -e "${YELLOW}🔑 MOT DE PASSE      :${RESET} $password"
echo -e "${YELLOW}📦 LIMITE APPAREILS  :${RESET} $limite"
echo -e "${YELLOW}📊 QUOTA TOTAL       :${RESET} $quota Go"
echo -e "${YELLOW}📅 DATE CRÉATION     :${RESET} $CREATED_DATE"
echo -e "${YELLOW}📅 EXPIRATION        :${RESET} $expire_date"
echo -e "${YELLOW}⏳ JOURS RESTANTS    :${RESET} $DAYS_LEFT jours"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "📊 GESTION DATA :"
echo -e "∘ Méthode       : vnStat (global serveur)"
echo -e "∘ Blocage auto  : OUI (quota atteint)"
echo -e "∘ Reset quota   : ❌ Aucun (sauf reset manuel)"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo "📲 APPS COMPATIBLES :"
echo "HTTP Injector, CUSTOM, SOCKSIP TUNNEL, SSC, V2Ray, Xray"

echo ""
echo -e "➡️ SSH WS     : ${GREEN}$DOMAIN:80@$username:$password${RESET}"
echo -e "➡️ SSL/TLS    : ${GREEN}$HOST_IP:444@$username:$password${RESET}"
echo -e "➡️ PROXY WS   : ${GREEN}$HOST_IP:9090@$username:$password${RESET}"
echo -e "➡️ SSH UDP    : ${GREEN}$HOST_IP:54000@$username:$password${RESET}"
echo -e "➡️ HYSTERIA   : ${GREEN}$DOMAIN:22000@$username:$password${RESET}"

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
echo -e "${RED}⚠️ NOTE IMPORTANTE :${RESET}"
echo -e "⛔ Le compte sera AUTOMATIQUEMENT BLOQUÉ dès que le quota DATA est atteint,"
echo -e "⛔ même si la date d'expiration n'est pas encore atteinte."

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}✅ COMPTE CRÉÉ AVEC SUCCÈS${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

read -p "Appuyez sur Entrée pour revenir au menu..."
