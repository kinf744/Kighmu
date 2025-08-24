#!/bin/bash
# menu2.sh - Création d'un test utilisateur SSH avec affichage dynamique

INSTALL_DIR="$HOME/Kighmu"
USER_FILE="/etc/kighmu/users.list"
WIDTH=60

# Couleurs
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# Fonctions d'affichage
line_full() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
center_line() {
    local text="$1"
    local padding=$(( (WIDTH - ${#text}) / 2 ))
    printf "|%*s%s%*s|\n" "$padding" "" "$text" "$padding" ""
}
content_line() { printf "| %-56s |\n" "$1"; }

# Fonction pour le statut d'un service
service_status() {
    local svc="$1"
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

# Création panneau
clear
line_full
center_line "${YELLOW}CRÉATION D'UN TEST UTILISATEUR${RESET}"
line_full

# Demande informations test utilisateur
read -p "Nom de test utilisateur : " username
read -s -p "Mot de passe : " password
echo ""
read -p "Nombre d'appareils autorisés : " limite
read -p "Durée de validité (jours) : " days

# Calcul date expiration et création utilisateur
expire_date=$(date -d "+$days days" '+%Y-%m-%d')
useradd -M -s /bin/false "$username"
echo "$username:$password" | chpasswd

# Récupération informations réseau et SlowDNS
HOST_IP=$(curl -s https://api.ipify.org)
SLOWDNS_KEY=$(cat /etc/slowdns/server.pub 2>/dev/null || echo "Clé publique SlowDNS non trouvée!")
SLOWDNS_NS="${SLOWDNS_NS:-slowdns5.kighmup.ddns-ip.net}"
DOMAIN="${DOMAIN:-localhost}"

# Sauvegarde
mkdir -p /etc/kighmu
touch "$USER_FILE"
chmod 600 "$USER_FILE"
echo "$username|$password|$limite|$expire_date|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> "$USER_FILE"

# Affichage dynamique
line_full
center_line "${YELLOW}INFORMATIONS TEST UTILISATEUR${RESET}"
line_simple
content_line "UTILISATEUR : $username"
content_line "MOT DE PASSE  : $password"
content_line "LIMITE       : $limite"
content_line "DATE EXPIRÉE : $expire_date"
content_line "IP/DOMAIN    : $HOST_IP / $DOMAIN"
line_simple
center_line "${YELLOW}PORTS DES MODES INSTALLÉS${RESET}"
line_simple
content_line "SSH         : 22 $(service_status ssh)"
content_line "Dropbear    : 90 $(service_status dropbear)"
content_line "SlowDNS     : 5300 $(service_status slowdns)"
content_line "SOCKS/Python: 8080 $(service_status socks-python)"
content_line "SSL/TLS     : 443 $(service_status nginx)"
content_line "Web Nginx   : 81 $(service_status nginx)"
content_line "BadVPN 1    : 7200 $(service_status badvpn)"
content_line "BadVPN 2    : 7300 $(service_status badvpn)"
content_line "UDP Custom  : 1-65535 $(service_status udp-custom)"
line_full
center_line "${YELLOW}CONFIGURATION SLOWDNS${RESET}"
line_simple
content_line "Pub KEY : $SLOWDNS_KEY"
content_line "NameServer (NS) : $SLOWDNS_NS"
line_full

read -p "Appuyez sur Entrée pour revenir au menu..."
