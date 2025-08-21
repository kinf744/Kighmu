#!/bin/bash
# menu2_color_fixed.sh modifié avec suivi TRAFFIC
# Créer un utilisateur test avec suivi et sauvegarde

# Couleurs
RESET="\e[0m"
BOLD="\e[1m"
CYAN="\e[36m"
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
MAGENTA="\e[35m"

WIDTH=60

line_full() { echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
center_line() {
    local text="$1"
    local padding=$(( (WIDTH - ${#text}) / 2 ))
    printf "|%*s%s%*s|\n" $padding "" "$text" $padding ""
}

# Charger les infos globales Kighmu
if [ -f ~/.kighmu_info ]; then
    source ~/.kighmu_info
else
    echo -e "${RED}Erreur : fichier ~/.kighmu_info introuvable.${RESET}"
    exit 1
fi

# Charger la clé publique SlowDNS
if [ -f /etc/slowdns/server.pub ]; then
    SLOWDNS_KEY=$(cat /etc/slowdns/server.pub)
else
    SLOWDNS_KEY="Clé publique SlowDNS non trouvée!"
fi

# Cadre de saisie utilisateur test
line_full
center_line "${BOLD}${MAGENTA}CRÉATION D'UTILISATEUR TEST${RESET}"
line_full

read -p "Nom d'utilisateur : " username
read -s -p "Mot de passe : " password
echo ""
read -p "Nombre d'appareils autorisés : " limite
read -p "Durée de validité (en minutes) : " minutes

line_simple

# Calcul de la date d'expiration
expire_date=$(date -d "+$minutes minutes" '+%Y-%m-%d %H:%M:%S')

# Créer l'utilisateur système
useradd -M -s /bin/false "$username" 2>/dev/null
echo "$username:$password" | chpasswd

# Définir ports et services
SSH_PORT=22
SYSTEM_DNS=53
SOCKS_PORT=8080
WEB_NGINX=81
DROPBEAR=90
SSL_PORT=443
BADVPN1=7200
BADVPN2=7300
SLOWDNS_PORT=5300
UDP_CUSTOM="1-65535"

HOST_IP=$(curl -s https://api.ipify.org)
SLOWDNS_NS="${SLOWDNS_NS:-slowdns5.kighmup.ddns-ip.net}"

# Sauvegarder les infos utilisateur
USER_FILE="/etc/kighmu/users.list"
mkdir -p /etc/kighmu
touch "$USER_FILE"
chmod 600 "$USER_FILE"
echo "$username|$password|$limite|$expire_date|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> "$USER_FILE"

# Création chaîne iptables TRAFFIC si elle n'existe pas
if ! iptables -L TRAFFIC &>/dev/null; then
    iptables -N TRAFFIC
fi
iptables -F TRAFFIC

# Ajouter règle TRAFFIC pour cet utilisateur test (SSH/Dropbear par UID)
iptables -A TRAFFIC -m owner --uid-owner "$username" -j RETURN

line_full
center_line "${GREEN}Utilisateur test $username créé avec succès !${RESET}"
line_full

# Affichage final hors cadre
cat <<EOF

*NOUVEAU UTILISATEUR TEST CRÉÉ*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
∘ SSH: $SSH_PORT            ∘ System-DNS: $SYSTEM_DNS
∘ SOCKS/PYTHON: $SOCKS_PORT   ∘ WEB-NGINX: $WEB_NGINX
∘ DROPBEAR: $DROPBEAR       ∘ SSL: $SSL_PORT
∘ BadVPN: $BADVPN1       ∘ BadVPN: $BADVPN2
∘ SlowDNS: $SLOWDNS_PORT      ∘ UDP-Custom: $UDP_CUSTOM
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DOMAIN        : $DOMAIN
Host/IP-Address : $HOST_IP
UTILISATEUR   : $username
MOT DE PASSE  : $password
LIMITE       : $limite
DATE EXPIRÉE : $expire_date
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
En APPS comme HTTP Injector, CUSTOM, KPN Rev, etc.

🙍 HTTP-Direct  : $HOST_IP:90@$username:$password
🙍 SSL/TLS(SNI) : $HOST_IP:443@$username:$password
🙍 Proxy(WS)    : $DOMAIN:8080@$username:$password
🙍 SSH UDP     : $HOST_IP:1-65535@$username:$password

━━━━━━━━━━━  CONFIGS SLOWDNS PORT 22 ━━━━━━━━━━━
Pub KEY :
$SLOWDNS_KEY
NameServer (NS) : $SLOWDNS_NS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

# Retour au menu principal
read -p "Appuyez sur Entrée pour revenir au menu principal..." dummy
"$INSTALL_DIR/kighmu.sh"
