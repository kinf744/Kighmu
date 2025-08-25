#!/bin/bash
# menu3.sh
# Afficher les utilisateurs en ligne avec nombre d'appareils et limite, incluant tunnels SlowDNS, UDP custom et SOCKS

USER_FILE="/etc/kighmu/users.list"
SLOWDNS_PORT=5300
UDP_CUSTOM_PORT=54000
SOCKS_PORT=8080

echo "+--------------------------------------------------------------+"
echo "|                    UTILISATEURS EN LIGNE                     |"
echo "+--------------------------------------------------------------+"

if [ ! -f "$USER_FILE" ]; then
    echo "Aucun utilisateur trouvé."
    exit 0
fi

printf "%-15s %-10s %-10s\n" "UTILISATEUR" "CONNECTÉS" "LIMITE"
echo "--------------------------------------------------------------"

# Fonction pour récupérer IPs uniques des connexions UDP sur un port donné
get_udp_ips() {
    local port=$1
    ss -u -a | grep ":$port " | awk '{print $5}' | cut -d: -f1 | sort -u
}

# Fonction pour récupérer IPs uniques des connexions TCP sur un port donné (proxy SOCKS)
get_tcp_ips() {
    local port=$1
    ss -t -a | grep ":$port " | awk '{print $5}' | cut -d: -f1 | sort -u
}

while IFS="|" read -r username password limite expire_date rest; do
    # Connexions SSH classiques
    ssh_connected=$(who | awk -v user="$username" '$1 == user' | wc -l)

    # Connexions SlowDNS UDP 5300 (non liées directement à utilisateur, comptage global d'IP)
    slowdns_ips=$(get_udp_ips $SLOWDNS_PORT)

    # Connexions UDP custom 54000
    udp_custom_ips=$(get_udp_ips $UDP_CUSTOM_PORT)

    # Connexions proxy SOCKS TCP 8080
    socks_ips=$(get_tcp_ips $SOCKS_PORT)

    # Fusionner toutes les IP en liste unique
    all_ips=$(echo -e "${slowdns_ips}\n${udp_custom_ips}\n${socks_ips}" | sort -u)

    # Nombre total d'IP uniques connectées (approximation)
    total_connected=$(echo "$ssh_connected + $(echo "$slowdns_ips" | wc -l) + $(echo "$udp_custom_ips" | wc -l) + $(echo "$socks_ips" | wc -l)" | bc)

    printf "%-15s %-10s %-10s\n" "$username" "$total_connected" "$limite"
done < "$USER_FILE"
