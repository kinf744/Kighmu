#!/bin/bash
# menu3-dynamique.sh
# Affiche les utilisateurs en ligne avec nombre d'appareils, limite et durée de connexion,
# incluant connexions Dropbear, SSH, SlowDNS, UDP custom, SOCKS, OpenVPN et WireGuard

USER_FILE="/etc/kighmu/users.list"
AUTH_LOG="/var/log/auth.log"
OPENVPN_STATUS="/etc/openvpn/openvpn-status.log"
SLOWDNS_PORT=5300
UDP_CUSTOM_PORT=54000
SOCKS_PORT=8080
WIREGUARD_CMD="wg"

echo "+---------------------------------------------------------------+"
echo "|            UTILISATEURS ET APPAREILS CONNECTÉS                |"
echo "+---------------------------------------------------------------+"

if [ ! -f "$USER_FILE" ]; then
    echo "Aucun utilisateur trouvé."
    exit 0
fi

printf "%-15s %-12s %-10s %-12s %-45s\n" "UTILISATEUR" "APPAREILS" "LIMITE" "TEMPS_CONN." "PROTOCOLES (IP connectées)"
echo "-----------------------------------------------------------------------------------------------"

# Récupère les IP (TCP ou UDP) connectées sur un port précis
get_port_ips() {
    local port=$1
    local proto=$2
    ss -n -"$proto" sport = :$port | awk 'NR>1{print $5}' | cut -d':' -f1 | sort -u
}

# Dropbear : utilisateurs connectés
get_dropbear_users() {
    ps ax | grep dropbear | grep -v grep | awk '{print $1}' | while read pid; do
        entry=$(grep "Password auth succeeded" $AUTH_LOG | grep "dropbear\[$pid\]")
        if [[ $entry ]]; then
            user=$(echo $entry | awk '{print $10}' | tr -d "'")
            ip=$(echo $entry | awk -F'from ' '{print $2}' | awk '{print $1}')
            echo "$user $ip"
        fi
    done
}

# SSH : IP connectées par utilisateur
get_ssh_ips() {
    ps -u $(who | awk '{print $1}' | sort -u | xargs) | grep sshd | awk '{print $1}' | while read pid; do
        entry=$(grep "Accepted password" $AUTH_LOG | grep "sshd[$pid]")
        if [[ $entry ]]; then
            user=$(echo $entry | awk '{print $9}')
            ip=$(echo $entry | awk '{print $11}')
            echo "$user $ip"
        fi
    done
}

# OpenVPN : adresses IP connectées
get_openvpn_ips() {
    if [ -f "$OPENVPN_STATUS" ]; then
        grep 'CLIENT_LIST' "$OPENVPN_STATUS" | awk -F',' '{print $2" "$3}'
    fi
}

# WireGuard : adresses IP connectées
get_wireguard_ips() {
    if command -v $WIREGUARD_CMD >/dev/null; then
        $WIREGUARD_CMD show | awk '/peer: /{peer=$2} /endpoint:/{print peer" "$2}' | cut -d: -f1,2
    fi
}

while IFS="|" read -r username password limite expire_date rest; do
    # Récupération des IP pour chaque protocole
    ssh_ips=$(get_ssh_ips | awk -v user="$username" '$1==user {print $2}')
    dropbear_ips=$(get_dropbear_users | awk -v user="$username" '$1==user {print $2}')
    openvpn_ips=$(get_openvpn_ips | awk -v user="$username" '$1==user {print $2}')
    wireguard_ips=$(get_wireguard_ips | awk -v user="$username" '$1==user {print $2}')
    slowdns_ips=$(get_port_ips $SLOWDNS_PORT "u")
    udp_custom_ips=$(get_port_ips $UDP_CUSTOM_PORT "u")
    socks_ips=$(get_port_ips $SOCKS_PORT "t")

    # Construit la liste unique des IP connectées par utilisateur
    user_ips=$(echo -e "$ssh_ips\n$dropbear_ips\n$openvpn_ips\n$wireguard_ips\n$socks_ips" | sort -u | grep -v "^$")

    # Compte le nombre d'appareils
    connected_devices=$(echo "$user_ips" | wc -l)

    # Calcule la durée de connexion SSH (premier sshd)
    pid=$(pgrep -u "$username" sshd | head -n1)
    if [[ -z "$pid" ]]; then
        connection_time="00:00:00"
    else
        etime=$(ps -p "$pid" -o etime= | tr -d ' ')
        if [[ "$etime" =~ ^[0-9]+-[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
            days=${etime%%-*}
            timepart=${etime#*-}
            IFS=: read -r hh mm ss <<< "$timepart"
            total_h=$((10#$days*24 + 10#$hh))
            connection_time=$(printf "%02d:%02d:%02d" $total_h $mm $ss)
        else
            connection_time=$etime
        fi
    fi

    # Prépare le résumé des protocoles et IP connectées
    proto_ips=""
    [[ "$ssh_ips" ]]         && proto_ips+="SSH:$(echo $ssh_ips | tr '\n' ',') "
    [[ "$dropbear_ips" ]]    && proto_ips+="Dropbear:$(echo $dropbear_ips | tr '\n' ',') "
    [[ "$openvpn_ips" ]]     && proto_ips+="OpenVPN:$(echo $openvpn_ips | tr '\n' ',') "
    [[ "$wireguard_ips" ]]   && proto_ips+="WireGuard:$(echo $wireguard_ips | tr '\n' ',') "
    [[ "$slowdns_ips" ]]     && proto_ips+="SlowDNS:$(echo $slowdns_ips | tr '\n' ',') "
    [[ "$udp_custom_ips" ]]  && proto_ips+="UDP:$(echo $udp_custom_ips | tr '\n' ',') "
    [[ "$socks_ips" ]]       && proto_ips+="SOCKS:$(echo $socks_ips | tr '\n' ',') "

    printf "%-15s %-12d %-10s %-12s %-45s\n" "$username" "$connected_devices" "$limite" "$connection_time" "$proto_ips"
done < "$USER_FILE"
