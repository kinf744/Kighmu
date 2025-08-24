#!/bin/bash
# ==============================================
# menu1.sh - Création d'utilisateur SSH
# ==============================================

INSTALL_DIR="$HOME/Kighmu"
WIDTH=60

# Couleurs
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# Fonctions d'affichage
line_full() { echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
content_line() { printf "| %-56s |\n" "$1"; }

center_line() {
    local text="$1"
    # Supprimer les séquences ANSI pour le calcul
    local clean_text=$(echo -e "$text" | sed 's/\x1B\[[0-9;]*[mK]//g')
    local padding=$(( (WIDTH - ${#clean_text}) / 2 ))
    printf "|%*s%s%*s|\n" "$padding" "" "$text" "$padding" ""
}

# Vérification que les fonctions systemctl existent pour le statut
service_status() {
    local svc="$1"
    if systemctl list-unit-files | grep -q "^$svc.service"; then
        if systemctl is-active --quiet "$svc"; then
            echo "[ACTIF]"
        else
            echo "[INACTIF]"
        fi
    else
        echo "[NON INSTALLÉ]"
    fi
}

# Début du panneau
clear
line_full
center_line "${YELLOW}CRÉATION D'UTILISATEUR${RESET}"
line_full

# Demande infos utilisateur
read -p "Nom d'utilisateur : " username
read -s -p "Mot de passe : " password
echo ""
read -p "Nombre d'appareils autorisés : " limite
read -p "Durée de validité (jours) : " days

# Calcul date expiration et création utilisateur
expire_date=$(date -d "+$days days" '+%Y-%m-%d')
useradd -M -s /bin/false "$username"
echo "$username:$password" | chpasswd

# Sauvegarde
HOST_IP=$(curl -s https://api.ipify.org)
SLOWDNS_KEY=$(cat /etc/slowdns/server.pub 2>/dev/null || echo "Clé publique SlowDNS non trouvée!")
SLOWDNS_NS="${SLOWDNS_NS:-slowdns5.kighmup.ddns-ip.net}"
mkdir -p /etc/kighmu
touch /etc/kighmu/users.list
chmod 600 /etc/kighmu/users.list
echo "$username|$password|$limite|$expire_date|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> /etc/kighmu/users.list

# Affichage dynamique
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
content_line "Pub KEY        : $SLOWDNS_KEY"
content_line "NameServer (NS): $SLOWDNS_NS"
line_full

read -p "Appuyez sur Entrée pour revenir au menu..."
