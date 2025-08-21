#!/bin/bash
# menu2_color.sh sécurisé avec suivi TRAFFIC et retour menu

INSTALL_DIR="$HOME/Kighmu"

# Couleurs
RESET="\e[0m"
BOLD="\e[1m"
CYAN="\e[36m"
GREEN="\e[32m"
RED="\e[31m"
MAGENTA="\e[35m"

WIDTH=60

line_full() { echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
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
    DOMAIN="non_defini"
fi

# Charger clé SlowDNS
SLOWDNS_KEY="Clé publique SlowDNS non trouvée!"
if [ -f /etc/slowdns/server.pub ]; then
    SLOWDNS_KEY=$(cat /etc/slowdns/server.pub)
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
useradd -M -s /bin/false "$username" 2>/dev/null || true
echo "$username:$password" | chpasswd 2>/dev/null || true

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

# Création chaîne iptables TRAFFIC sécurisée
iptables -N TRAFFIC 2>/dev/null || true
iptables -F TRAFFIC 2>/dev/null || true
iptables -A TRAFFIC -m owner --uid-owner "$username" -j RETURN 2>/dev/null || true

line_full
center_line "${GREEN}Utilisateur test $username créé avec succès !${RESET}"
line_full

echo ""
echo "*NOUVEAU UTILISATEUR TEST CRÉÉ*"
echo "DOMAIN        : $DOMAIN"
echo "Host/IP       : $HOST_IP"
echo "UTILISATEUR   : $username"
echo "MOT DE PASSE  : $password"
echo "LIMITE        : $limite"
echo "DATE EXPIRÉE  : $expire_date"
echo ""

read -n1 -r -p "Appuyez sur une touche pour revenir au menu principal..." key
bash "$INSTALL_DIR/kighmu.sh"
