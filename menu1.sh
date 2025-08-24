#!/bin/bash
# ==============================================
# menu1.sh - Création d'utilisateur SSH complet
# ==============================================

INSTALL_DIR="$HOME/Kighmu"
WIDTH=60

# Couleurs
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

# Fonctions d'affichage
line_full() { echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
content_line() { printf "| %-56s |\n" "$1"; }
center_line() { 
    local text="$1"
    local clean_text=$(echo -e "$text" | sed 's/\x1B\[[0-9;]*[mK]//g')
    local padding=$(( (WIDTH - ${#clean_text}) / 2 ))
    printf "|%*s%s%*s|\n" "$padding" "" "$text" "$padding" ""
}

# Statut des services/modes
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

# Fonction pour demander une info avec 2 essais max
ask_input() {
    local prompt="$1"
    local silent="$2"
    local input=""
    local attempts=0

    while [ $attempts -lt 2 ]; do
        if [ "$silent" == "true" ]; then
            read -s -p "$prompt" input
            echo ""
        else
            read -p "$prompt" input
        fi

        if [ -n "$input" ]; then
            echo "$input"
            return
        fi

        attempts=$((attempts + 1))
        echo -e "${RED}Valeur obligatoire. Essai $attempts/2${RESET}"
    done

    echo -e "${RED}Création annulée.${RESET}"
    exit 1
}

# Début du panneau
clear
line_full
center_line "CRÉATION D'UTILISATEUR"
line_full

# Demande infos utilisateur
username=$(ask_input "Nom d'utilisateur : " false)
password=$(ask_input "Mot de passe : " true)
limite=$(ask_input "Nombre d'appareils autorisés : " false)
days=$(ask_input "Durée de validité (jours) : " false)

# Création utilisateur et calcul expiration
expire_date=$(date -d "+$days days" '+%Y-%m-%d')
useradd -M -s /bin/false "$username"
echo "$username:$password" | chpasswd

# Sauvegarde dans fichier users.list
mkdir -p /etc/kighmu
touch /etc/kighmu/users.list
chmod 600 /etc/kighmu/users.list
HOST_IP=$(curl -s https://api.ipify.org)
SLOWDNS_KEY=$(cat /etc/slowdns/server.pub 2>/dev/null || echo "Clé publique SlowDNS non trouvée!")
SLOWDNS_NS="${SLOWDNS_NS:-slowdns5.kighmup.ddns-ip.net}"
echo "$username|$password|$limite|$expire_date|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> /etc/kighmu/users.list

# Affichage dynamique complet
line_full
center_line "INFORMATIONS UTILISATEUR"
line_simple
content_line "UTILISATEUR : $username"
content_line "MOT DE PASSE  : $password"
content_line "LIMITE       : $limite"
content_line "DATE EXPIRÉE : $expire_date"
content_line "IP/DOMAIN    : $HOST_IP / $DOMAIN"
line_simple
center_line "PORTS DES MODES INSTALLÉS"
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
center_line "CONFIGURATION SLOWDNS"
line_simple
content_line "Pub KEY        : $SLOWDNS_KEY"
content_line "NameServer (NS): $SLOWDNS_NS"
line_full

read -p "Appuyez sur Entrée pour revenir au menu..."
