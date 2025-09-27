#!/bin/bash
# menu3.sh
# Afficher nom d'utilisateur, limite, nombre total de connexions, et nombre d'appareils (IPs uniques) par utilisateur

# Couleurs pour cadre et mise en forme
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

USER_FILE="/etc/kighmu/users.list"
AUTH_LOG="/var/log/auth.log"
OPENVPN_STATUS="/etc/openvpn/openvpn-status.log"

clear
echo -e "${CYAN}+==============================================================+${RESET}"
echo -e "|                  UTILISATEURS ET CONNEXIONS                  |"
echo -e "${CYAN}+==============================================================+${RESET}"

if [ ! -f "$USER_FILE" ]; then
    echo -e "${RED}Aucun utilisateur trouvé.${RESET}"
    exit 0
fi

printf "${BOLD}%-20s %-10s %-12s %-12s %-12s${RESET}\n" "UTILISATEUR" "LIMITÉ" "CONNEXIONS" "APPAREILS" "OPENVPN_CONN"
echo -e "${CYAN}----------------------------------------------------------------${RESET}"

while IFS="|" read -r username password limite expire_date hostip domain slowdns_ns; do
    
    # Connexions SSHD actives (sessions)
    ssh_connexions=$(ps aux | grep "sshd: $username@" | grep -v grep | wc -l)

    # IPs uniques de connexions SSHD
    ssh_unique_ips=$(ss -tnp | grep sshd | grep ESTAB | grep "$username@" | awk '{print $5}' | cut -d':' -f1 | sort | uniq | wc -l)

    # Connexions Dropbear actives (sessions)
    drop_connexions=$(pgrep -u $username dropbear | wc -l)

    # IPs uniques Dropbear (via auth.log)
    drop_unique_ips=$(grep "dropbear.*Password auth succeeded" $AUTH_LOG | grep "for $username" | awk '{print $(NF-3)}' | sort | uniq | wc -l)

    # Si Dropbear ne tourne pas, on met 0
    if ! pgrep dropbear > /dev/null; then
        drop_connexions=0
        drop_unique_ips=0
    fi

    # Connexions OpenVPN
    if [ -f "$OPENVPN_STATUS" ]; then
        openvpn_connexions=$(grep -w "$username" "$OPENVPN_STATUS" | wc -l)
    else
        openvpn_connexions=0
    fi

    # Total connexions (sshd + dropbear)
    total_connexions=$((ssh_connexions + drop_connexions))

    # Total appareils (IPs uniques sshd + dropbear)
    total_unique_ips=$((ssh_unique_ips + drop_unique_ips))

    # Affichage formaté
    printf "%-20s %-10s %-12d %-12d %-12d\n" "$username" "$limite" "$total_connexions" "$total_unique_ips" "$openvpn_connexions"

done < "$USER_FILE"

echo -e "${CYAN}+==============================================================+${RESET}"

read -p "Appuyez sur Entrée pour revenir au menu..."

