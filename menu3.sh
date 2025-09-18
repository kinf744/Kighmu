#!/bin/bash
# menu3.sh
# Afficher nom d'utilisateur, limite, et nombre total d'appareils connectés

# Couleurs pour cadre et mise en forme
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

USER_FILE="/etc/kighmu/users.list"

clear
echo -e "${CYAN}+==============================================+${RESET}"
echo -e "|            UTILISATEURS ET CONNEXIONS        |"
echo -e "${CYAN}+==============================================+${RESET}"

if [ ! -f "$USER_FILE" ]; then
    echo -e "${RED}Aucun utilisateur trouvé.${RESET}"
    exit 0
fi

printf "${BOLD}%-20s %-10s %-10s${RESET}\n" "UTILISATEUR" "LIMITÉ" "APPAREILS"
echo -e "${CYAN}----------------------------------------------${RESET}"

# Connexions SSH/Dropbear via 'who'
mapfile -t active_sessions < <(who | awk '{print $1}')

# Comptage connexions par utilisateur pour SSH/Dropbear
declare -A ssh_counts
for user in "${active_sessions[@]}"; do
    ssh_counts["$user"]=$((ssh_counts["$user"] + 1))
done

# IPs clientes SlowDNS UDP port 5300
mapfile -t slowdns_ips < <(ss -u -a | grep ":5300" | awk '{print $5}' | cut -d':' -f1 | sort | uniq)

# IPs clientes UDP Custom port 54000
mapfile -t udp_custom_ips < <(ss -u -a | grep ":54000" | awk '{print $5}' | cut -d':' -f1 | sort | uniq)

# IPs clientes SOCKS Python TCP port 8080
mapfile -t socks_ips < <(ss -tn src :8080 | awk 'NR>1 {print $5}' | cut -d':' -f1 | sort | uniq)

while IFS="|" read -r username password limite expire_date hostip domain slowdns_ns; do

    ssh_connected=${ssh_counts["$username"]}
    ssh_connected=${ssh_connected:-0}

    # Compter le nombre total d'appareils connectés par IP de l'utilisateur
    total_conn=ssh_connected

    # SlowDNS connexions : on compte 1 si l'IP utilisateur est dans slowdns_ips
    for ip in "${slowdns_ips[@]}"; do
        if [[ "$ip" == "$hostip" ]]; then
            total_conn=$((total_conn + 1))
            break
        fi
    done

    # UDP Custom connexions
    for ip in "${udp_custom_ips[@]}"; do
        if [[ "$ip" == "$hostip" ]]; then
            total_conn=$((total_conn + 1))
            break
        fi
    done

    # SOCKS Python connexions
    for ip in "${socks_ips[@]}"; do
        if [[ "$ip" == "$hostip" ]]; then
            total_conn=$((total_conn + 1))
            break
        fi
    done

    printf "%-20s %-10s %-10d\n" "$username" "$limite" "$total_conn"

done < "$USER_FILE"

echo -e "${CYAN}+==============================================+${RESET}"

read -p "Appuyez sur Entrée pour revenir au menu..."
