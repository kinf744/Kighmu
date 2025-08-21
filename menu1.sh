#!/bin/bash
# menu1_color.sh
# Créer un utilisateur normal et sauvegarder ses infos
INSTALL_DIR="$HOME/Kighmu"

# Couleurs
RESET="\e[0m"
BOLD="\e[1m"
CYAN="\e[36m"
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
MAGENTA="\e[35m"

WIDTH=60

line_full() {
    echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"
}

line_simple() {
    echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"
}

content_line() {
    local text="$1"
    local padding=$((WIDTH - ${#text}))
    printf "| %s%*s |\n" "$text" $padding ""
}

center_line() {
    local text="$1"
    local padding=$(( (WIDTH - ${#text}) / 2 ))
    printf "|%*s%s%*s|\n" $padding "" "$text" $padding ""
}

# Charger la configuration globale
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

# Cadre de saisie utilisateur
line_full
center_line "${BOLD}${MAGENTA}CRÉATION D'UTILISATEUR${RESET}"
line_full

read -p "Nom d'utilisateur : " username
read -s -p "Mot de passe : " password
echo ""
read -p "Nombre d'appareils autorisés : " limite
read -p "Durée de validité (en jours) : " days

line_simple

# Calcul de la date d'expiration
expire_date=$(date -d "+$days days" '+%Y-%m-%d')

# Créer l'utilisateur système
useradd -M -s /bin/false "$username"
echo "$username:$password" | chpasswd

# Définir ports et variables
SSH_PORT=22
SYSTEM_DNS=53
SOCKS_PORT=8080
WEB_NGINX=81
DROPBEAR=90
SSL_PORT=445
BADVPN1=7200
BADVPN2=7300
SLOWDNS_PORT=5300
UDP_CUSTOM="1-65535"

HOST_IP=$(curl -s https://api.ipify.org)
SLOWDNS_NS="${SLOWDNS_NS:-slowdns5.kighmup.ddns-ip.net}"

# Sauvegarder utilisateur
USER_FILE="/etc/kighmu/users.list"
mkdir -p /etc/kighmu
touch "$USER_FILE"
chmod 600 "$USER_FILE"
echo "$username|$password|$limite|$expire_date|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> "$USER_FILE"

line_full
center_line "${GREEN}Utilisateur $username créé avec succès !${RESET}"
line_full

# Affichage final hors cadre
echo ""
echo "*NOUVEAU UTILISATEUR CRÉÉ*"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "∘ SSH: $SSH_PORT            ∘ System-DNS: $SYSTEM_DNS"
echo "∘ SOCKS/PYTHON: $SOCKS_PORT   ∘ WEB-NGINX: $WEB_NGINX"
echo "∘ DROPBEAR: $DROPBEAR       ∘ SSL: $SSL_PORT"
echo "∘ BadVPN: $BADVPN1       ∘ BadVPN: $BADVPN2"
echo "∘ SlowDNS: $SLOWDNS_PORT      ∘ UDP-Custom: $UDP_CUSTOM"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "DOMAIN        : $DOMAIN"
echo "Host/IP-Address : $HOST_IP"
echo "UTILISATEUR   : $username"
echo "MOT DE PASSE  : $password"
echo "LIMITE       : $limite"
echo "DATE EXPIRÉE : $expire_date"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "En APPS comme HTTP Injector, CUSTOM, KPN Rev, etc."
echo ""
echo "🙍 HTTP-Direct  : $HOST_IP:90@$username:$password"
echo "🙍 SSL/TLS(SNI) : $HOST_IP:445@$username:$password"
echo "🙍 Proxy(WS)    : $DOMAIN:8080@$username:$password"
echo "🙍 SSH UDP     : $HOST_IP:1-65535@$username:$password"
echo ""
echo "━━━━━━━━━━━  CONFIGS SLOWDNS PORT 22 ━━━━━━━━━━━"
echo "Pub KEY :"
echo "$SLOWDNS_KEY"
echo "NameServer (NS) : $SLOWDNS_NS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
