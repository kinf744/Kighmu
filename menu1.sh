#!/bin/bash
# menu1.sh - Création d'utilisateur normal avec panneau de contrôle dynamique

USER_FILE="/etc/kighmu/users.list"
INSTALL_DIR="$HOME/Kighmu"
WIDTH=60

# Couleurs
CYAN="\e[36m"   # lignes
YELLOW="\e[33m" # titre
RESET="\e[0m"

# Fonctions d'affichage
line_full() { echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
content_line() { printf "| %-56s |\n" "$1"; }
center_line() {
    local text="$1"
    local padding=$(( (WIDTH - ${#text}) / 2 ))
    printf "|%*s%s%*s|\n" "$padding" "" "$text" "$padding" ""
}

# Vérifier l'état d'un service
service_status() {
    local svc=$1
    if systemctl list-unit-files | grep -q "^$svc.service"; then
        if systemctl is-active --quiet "$svc"; then
            echo "[actif]"
        else
            echo "[inactif]"
        fi
    else
        echo "[non installé]"
    fi
}

# Ports par défaut
SSH_PORT=22
DROPBEAR_PORT=90
SLOWDNS_PORT=5300
SOCKS_PORT=8080
WEB_NGINX=81
SSL_PORT=444
BADVPN1=7200
BADVPN2=7300
UDP_CUSTOM="1-65535"

# Panneau d’accueil
clear
line_full
center_line "${YELLOW}CRÉATION D'UTILISATEUR${RESET}"
line_full

# Demande des infos utilisateur
read -p "Nom d'utilisateur : " username
read -s -p "Mot de passe : " password
echo ""
read -p "Nombre d'appareils autorisés : " limite
read -p "Durée de validité (en jours) : " days

# Calcul date d'expiration
expire_date=$(date -d "+$days days" '+%Y-%m-%d')

# Création utilisateur système
useradd -M -s /bin/false "$username"
echo "$username:$password" | chpasswd

# IP publique
HOST_IP=$(curl -s https://api.ipify.org)

# Clé publique SlowDNS
if [ -f /etc/slowdns/server.pub ]; then
    SLOWDNS_KEY=$(cat /etc/slowdns/server.pub)
else
    SLOWDNS_KEY="Clé publique SlowDNS non trouvée!"
fi

# NS SlowDNS
SLOWDNS_NS="${SLOWDNS_NS:-slowdns5.kighmup.ddns-ip.net}"

# Sauvegarde des infos
mkdir -p /etc/kighmu
touch "$USER_FILE"
chmod 600 "$USER_FILE"
echo "$username|$password|$limite|$expire_date|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> "$USER_FILE"

# Affichage résumé dynamique
echo ""
line_full
center_line "${YELLOW}INFORMATIONS UTILISATEUR${RESET}"
line_simple
content_line "UTILISATEUR : $username"
content_line "MOT DE PASSE  : $password"
content_line "LIMITE       : $limite"
content_line "DATE EXPIRÉE : $expire_date"
content_line "IP/DOMAIN    : $HOST_IP / $DOMAIN"
line_simple
center_line "${YELLOW}PORTS DES MODES INSTALLÉS${RESET}"
line_simple
content_line "SSH         : $SSH_PORT $(service_status ssh)"
content_line "Dropbear    : $DROPBEAR_PORT $(service_status dropbear)"
content_line "SlowDNS     : $SLOWDNS_PORT $(service_status slowdns)"
content_line "SOCKS/Python: $SOCKS_PORT $(service_status socks-python)"
content_line "SSL/TLS     : $SSL_PORT $(service_status nginx)"
content_line "Web Nginx   : $WEB_NGINX $(service_status nginx)"
content_line "BadVPN 1    : $BADVPN1 $(service_status badvpn)"
content_line "BadVPN 2    : $BADVPN2 $(service_status badvpn)"
content_line "UDP Custom  : $UDP_CUSTOM $(service_status udp-custom)"
line_full

center_line "${YELLOW}CONFIGURATION SLOWDNS${RESET}"
line_simple
content_line "Pub KEY : $SLOWDNS_KEY"
content_line "NameServer (NS) : $SLOWDNS_NS"
line_full

echo "Compte créé avec succès."
