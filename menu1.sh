#!/bin/bash
# menu1.sh
# Créer un utilisateur normal et sauvegarder ses infos
set -euo pipefail

# Définition des couleurs (comme dans le panneau principal)
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

clear

# Charger la configuration globale si elle existe
if [ -f ~/.kighmu_info ]; then
    source ~/.kighmu_info
else
    echo -e "${RED}Erreur : fichier ~/.kighmu_info introuvable, informations globales manquantes.${RESET}"
    read -p "Appuyez sur Entrée pour revenir au menu..." 
    exit 1
fi

# Charger la clé publique SlowDNS
if [ -f /etc/slowdns/server.pub ]; then
    SLOWDNS_KEY=$(cat /etc/slowdns/server.pub)
else
    SLOWDNS_KEY="${RED}Clé publique SlowDNS non trouvée!${RESET}"
fi

# Charger le NameServer SlowDNS exact depuis le fichier de config, sinon valeur vide
if [ -f /etc/slowdns/ns.conf ]; then
    SLOWDNS_NS=$(cat /etc/slowdns/ns.conf)
else
    SLOWDNS_NS=""
    echo -e "${YELLOW}Attention : fichier /etc/slowdns/ns.conf introuvable. Poursuite sans NS.${RESET}"
fi

echo -e "${CYAN}+==================================================+${RESET}"
echo -e "|                CRÉATION D'UTILISATEUR             |"
echo -e "${CYAN}+==================================================+${RESET}"

# Demander les informations
read -p "Nom d'utilisateur : " username

if id "$username" &>/dev/null; then
    echo -e "${RED}L'utilisateur existe déjà.${RESET}"
    read -p "Appuyez sur Entrée pour revenir au menu..."
    exit 1
fi

# Lecture mot de passe visible (sans masquage)
read -p "Mot de passe : " password

read -p "Nombre d'appareils autorisés : " limite
read -p "Durée de validité (en jours) : " days

# Validation simple
if ! [[ "$limite" =~ ^[0-9]+$ ]] || ! [[ "$days" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Nombre d'appareils ou durée non valides.${RESET}"
    read -p "Appuyez sur Entrée pour revenir au menu..."
    exit 1
fi

# Calculer la date d'expiration
expire_date=$(date -d "+$days days" '+%Y-%m-%d')

# Création utilisateur compatible OpenSSH / Dropbear
useradd -m -s /bin/bash "$username" || { echo -e "${RED}Erreur lors de la création${RESET}"; read -p "Appuyez sur Entrée pour revenir au menu..."; exit 1; }
echo "$username:$password" | chpasswd

# Appliquer la date d'expiration du compte
chage -E "$expire_date" "$username"

# Préparer fichier d'utilisateurs
USER_FILE="/etc/kighmu/users.list"
mkdir -p /etc/kighmu
touch "$USER_FILE"
chmod 600 "$USER_FILE"

HOST_IP=$(hostname -I | awk '{print $1}')

# Sauvegarder les infos utilisateur dans le format attendu par hysteria.sh
echo "$username|$password|$limite|$expire_date|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> "$USER_FILE"

# ================== ZIVPN SYNC (POST USER ADD) ==================
ZIVPN_CONFIG="/etc/zivpn/config.json"

if [ -f "$ZIVPN_CONFIG" ]; then
    command -v jq >/dev/null 2>&1 || return 0

    TODAY=$(date +%Y-%m-%d)

    ZIVPN_PASS=$(awk -F'|' -v today="$TODAY" '
    {
        if ($4 >= today) print $2
    }' /etc/kighmu/users.list | sort -u | jq -R . | jq -s .)

    jq --argjson arr "$ZIVPN_PASS" '
        .config = $arr
    ' "$ZIVPN_CONFIG" > /tmp/zivpn.json && mv /tmp/zivpn.json "$ZIVPN_CONFIG"

    systemctl restart zivpn
fi
# ================================================================

# Ajout automatique de l'affichage du banner personnalisé au login shell
BANNER_PATH="/etc/ssh/sshd_banner"

# Home minimal pour Dropbear / OpenSSH
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

# Résumé affichage coloré des informations utilisateur avec hysteria inclus
echo -e "✨ 𝙉𝙊𝙐𝙑𝙀𝘼𝙐 𝙐𝙏𝙄𝙇𝙄𝙎𝘼𝙏𝙀𝙐𝙍 𝘾𝙍𝙀‌𝙀‌ ✨"
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
echo -e "🚀 𝘾𝙊𝙉𝙁𝙄𝙂 𝙁𝘼𝙎𝙏𝘿𝙉𝙎 (5300)" 
echo -e "${YELLOW}🔐Pub KEY:${RESET}"
echo -e "$SLOWDNS_KEY"
echo -e "NameServer:"
echo -e "${YELLOW}$SLOWDNS_NS${RESET}"
echo ""
echo -e "${GREEN}✅ 𝘾𝙊𝙈𝙋𝙏𝙀 𝘾𝙍𝙀‌𝙀‌ 𝘼𝙑𝙀𝘾 𝙎𝙐𝘾𝘾𝙀‌𝙎${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

read -p "Appuyez sur Entrée pour revenir au menu..."
