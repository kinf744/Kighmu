#!/bin/bash
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

USER_FILE="/etc/kighmu/users.list"

clear
echo -e "${CYAN}+==============================================+${RESET}"
echo -e "|            GESTION DES UTILISATEURS         |"
echo -e "${CYAN}+==============================================+${RESET}"

if [ ! -f "$USER_FILE" ]; then
    echo -e "${RED}Fichier utilisateur introuvable.${RESET}"
    exit 1
fi

printf "${BOLD}%-20s %-10s %-10s${RESET}\n" "UTILISATEUR" "LIMITÉ" "APPAREILS"
echo -e "${CYAN}----------------------------------------------${RESET}"

# Connexions SSH/Dropbear via 'who'
declare -A ssh_counts
while read -r user _; do
    ((ssh_counts[$user]++))
done < <(who)

# Connexions Dropbear extraites de logs (fonction adaptée, exemple très basique)
fun_drop() {
    port_dropbear=$(ps aux | grep dropbear | awk 'NR==1 {print $17}')
    log=/var/log/auth.log
    loginsukses='Password auth succeeded'
    pids=$(ps ax | grep dropbear | grep " $port_dropbear" | awk '{print $1}')
    declare -A dropd

    for pid in $pids; do
        login=$(grep "$pid" "$log" | grep "$loginsukses" | tail -1)
        if [[ $login ]]; then
            user=$(echo "$login" | awk '{print $10}')
            ((dropd[$user]++))
        fi
    done

    for u in "${!dropd[@]}"; do
        echo "$u ${dropd[$u]}"
    done
}

declare -A drop_counts
if netstat -nltp | grep -q 'dropbear'; then
    while read -r user count; do
        drop_counts["$user"]=$count
    done < <(fun_drop)
fi

# Connexions OpenVPN (très basique)
declare -A ovpn_counts
if [[ -f /etc/openvpn/openvpn-status.log ]]; then
    while read -r line; do
        user=$(echo "$line" | cut -d',' -f2)
        ((ovpn_counts[$user]++))
    done < <(grep CLIENT_LIST /etc/openvpn/openvpn-status.log)
fi

# IPs clients SlowDNS/UDP Custom/SOCKS Python
mapfile -t slowdns_ips < <(ss -u -a | grep ":5300" | awk '{print $5}' | cut -d':' -f1 | sort | uniq)
mapfile -t udp_custom_ips < <(ss -u -a | grep ":54000" | awk '{print $5}' | cut -d':' -f1 | sort | uniq)
mapfile -t socks_ips < <(ss -tn src :8080 | awk 'NR>1 {print $5}' | cut -d':' -f1 | sort | uniq)

while IFS="|" read -r username password limite expire_date hostip domain slowdns_ns; do
    ssh_connected=${ssh_counts[$username]:-0}
    drop_connected=${drop_counts[$username]:-0}
    ovpn_connected=${ovpn_counts[$username]:-0}

    total_conn=$((ssh_connected + drop_connected + ovpn_connected))

    for ip in "${slowdns_ips[@]}"; do
        [[ "$ip" == "$hostip" ]] && total_conn=$((total_conn + 1)) && break
    done

    for ip in "${udp_custom_ips[@]}"; do
        [[ "$ip" == "$hostip" ]] && total_conn=$((total_conn + 1)) && break
    done

    for ip in "${socks_ips[@]}"; do
        [[ "$ip" == "$hostip" ]] && total_conn=$((total_conn + 1)) && break
    done

    printf "%-20s %-10s %-10d\n" "$username" "$limite" "$total_conn"
done < "$USER_FILE"

echo -e "${CYAN}+==============================================+${RESET}"
read -p "Appuyez sur Entrée pour revenir au menu..."
