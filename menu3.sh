#!/bin/bash
# menu3.sh
# Afficher les utilisateurs en ligne avec nombre d'appareils, limite et durée de connexion,
# incluant connexions Dropbear, SSH, SlowDNS, UDP custom et SOCKS

USER_FILE="/etc/kighmu/users.list"
SLOWDNS_PORT=5300
UDP_CUSTOM_PORT=54000
SOCKS_PORT=8080
AUTH_LOG="/var/log/auth.log"

echo "+--------------------------------------------------------------+"
echo "|                    UTILISATEURS EN LIGNE                     |"
echo "+--------------------------------------------------------------+"

if [ ! -f "$USER_FILE" ]; then
    echo "Aucun utilisateur trouvé."
    exit 0
fi

printf "%-15s %-12s %-10s %-12s\n" "UTILISATEUR" "CONNECTÉS" "LIMITE" "TEMPS_CONNEXION"
echo "--------------------------------------------------------------"

# Fonction pour obtenir les utilisateurs connectés via Dropbear à partir du journal auth.log
get_dropbear_users() {
    local pid_list=$(ps ax | grep dropbear | grep -v grep | awk '{print $1}')
    for pid in $pid_list; do
        local login_entry=$(grep "Password auth succeeded" $AUTH_LOG | grep "dropbear\[$pid\]")
        if [[ -n "$login_entry" ]]; then
            local user=$(echo "$login_entry" | awk '{print $10}' | tr -d "'")
            echo "$pid:$user"
        fi
    done
}

# Fonction pour calculer le temps de connexion SSH de l'utilisateur (premier sshd)
get_ssh_connection_time() {
    local user=$1
    local pid=$(pgrep -u "$user" sshd | head -n1)
    if [[ -z "$pid" ]]; then
        echo "00:00:00"
        return
    fi
    local etime=$(ps -p "$pid" -o etime= | tr -d ' ')
    if [[ "$etime" =~ ^[0-9]+-[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
        days=${etime%%-*}
        timepart=${etime#*-}
        IFS=: read -r hh mm ss <<< "$timepart"
        total_h=$((10#$days*24 + 10#$hh))
        printf "%02d:%02d:%02d\n" $total_h $mm $ss
    else
        echo "$etime"
    fi
}

# Fonctions pour récupérer les adresses IP uniques connectées sur un port (UDP ou TCP)
get_udp_ips() {
    local port=$1
    ss -u -a sport = :$port 2>/dev/null | grep -oP '(?<= )[^ ]+(?=:[0-9]+)' | sort -u
}

get_tcp_ips() {
    local port=$1
    ss -t -a sport = :$port 2>/dev/null | grep -oP '(?<= )[^ ]+(?=:[0-9]+)' | sort -u
}

while IFS="|" read -r username password limite expire_date rest; do
    # Connexions SSH classiques (via who)
    ssh_connected=$(who | awk -v user="$username" '$1 == user' | wc -l)

    # Connexions Dropbear par utilisateur via auth.log
    drop_connections=$(get_dropbear_users | grep -c ":$username")

    # Connexions SlowDNS, UDP custom et SOCKS (compte global, non attribué à l'utilisateur)
    slowdns_count=$(get_udp_ips $SLOWDNS_PORT | wc -l)
    udp_custom_count=$(get_udp_ips $UDP_CUSTOM_PORT | wc -l)
    socks_count=$(get_tcp_ips $SOCKS_PORT | wc -l)

    # Total des connexions utilisateurs pour SSH + Dropbear (approximation)
    total_connexions=$((ssh_connected + drop_connections))

    # Temps de connexion SSH estimé pour l'utilisateur
    connection_time=$(get_ssh_connection_time "$username")

    printf "%-15s %-12d %-10s %-12s\n" "$username" "$total_connexions" "$limite" "$connection_time"
done < "$USER_FILE"
