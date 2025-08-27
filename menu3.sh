#!/bin/bash
# menu3.sh
# Amélioration du script pour un comptage précis des appareils par utilisateur

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

# Récupération des IP TCP établies pour un port
get_established_tcp_ips() {
    local port=$1
    ss -tn state established sport = :$port 2>/dev/null | awk 'NR>1 {print $5}' | cut -d':' -f1 | sort -u
}

# Récupération des IP UDP "actives" récentes sur un port
get_active_udp_ips() {
    local port=$1
    ss -nu sport = :$port 2>/dev/null | awk 'NR>1 {print $5}' | cut -d':' -f1 | sort -u
}

# Dropbear: utilisateurs avec IP depuis auth.log et PID en cours
get_dropbear_users() {
    local auth_log="$AUTH_LOG"
    local pids=($(pgrep dropbear))
    for pid in "${pids[@]}"; do
        local entry=$(grep "Password auth succeeded" $auth_log | grep "dropbear\[$pid\]" | tail -1)
        if [[ -n $entry ]]; then
            local user=$(echo "$entry" | awk '{print $10}' | tr -d "'")
            local ip=$(echo "$entry" | awk -F'from ' '{print $2}' | awk '{print $1}')
            echo "$user $ip"
        fi
    done
}

# SSH: utilisateurs avec IP depuis auth.log et PID en cours
get_ssh_ips() {
    local users=($(who | awk '{print $1}' | sort -u))
    for user in "${users[@]}"; do
        local pids=($(pgrep -u "$user" sshd))
        for pid in "${pids[@]}"; do
            local entry=$(grep "Accepted password" "$AUTH_LOG" | grep "sshd\[$pid\]" | tail -1)
            if [[ -n $entry ]]; then
                local user_logged=$(echo "$entry" | awk '{print $9}')
                local ip=$(echo "$entry" | awk '{print $11}')
                echo "$user_logged $ip"
            fi
        done
    done
}

# OpenVPN : récupère utilisateur et IP
get_openvpn_ips() {
    if [ -f "$OPENVPN_STATUS" ]; then
        grep 'CLIENT_LIST' "$OPENVPN_STATUS" | awk -F',' '{print $2" "$3}'
    fi
}

# WireGuard : récupère peer (user) et IP endpoint
get_wireguard_ips() {
    if command -v $WIREGUARD_CMD >/dev/null 2>&1; then
        $WIREGUARD_CMD show | awk '
            /peer: / {peer=$2}
            /endpoint:/ {print peer" "$2}
        ' | cut -d: -f1,2
    fi
}

while IFS="|" read -r username password limite expire_date rest; do
    ssh_ips=$(get_ssh_ips | awk -v user="$username" '$1==user {print $2}')
    dropbear_ips=$(get_dropbear_users | awk -v user="$username" '$1==user {print $2}')
    openvpn_ips=$(get_openvpn_ips | awk -v user="$username" '$1==user {print $2}')
    wireguard_ips=$(get_wireguard_ips | awk -v user="$username" '$1==user {print $2}')
    slowdns_ips=$(get_active_udp_ips $SLOWDNS_PORT)
    udp_custom_ips=$(get_active_udp_ips $UDP_CUSTOM_PORT)
    socks_ips=$(get_established_tcp_ips $SOCKS_PORT)

    # Fusionne toutes les IP pour cet utilisateur
    user_ips=$(echo -e "$ssh_ips\n$dropbear_ips\n$openvpn_ips\n$wireguard_ips" | sort -u | grep -v "^$")
    # Note : slowdns, udp custom, socks IPs ne sont pas attribués à un utilisateur spécifique, donc non inclus ici

    connected_devices=$(echo "$user_ips" | wc -l)

    # Calcul durée connexion SSH utilisateur (premier sshd)
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

    proto_ips=""
    [[ "$ssh_ips" ]]      && proto_ips+="SSH:$(echo $ssh_ips | tr '\n' ',') "
    [[ "$dropbear_ips" ]] && proto_ips+="Dropbear:$(echo $dropbear_ips | tr '\n' ',') "
    [[ "$openvpn_ips" ]]  && proto_ips+="OpenVPN:$(echo $openvpn_ips | tr '\n' ',') "
    [[ "$wireguard_ips" ]]&& proto_ips+="WireGuard:$(echo $wireguard_ips | tr '\n' ',') "
    [[ "$slowdns_ips" ]]  && proto_ips+="SlowDNS:$(echo $slowdns_ips | tr '\n' ',') "
    [[ "$udp_custom_ips" ]]&& proto_ips+="UDP:$(echo $udp_custom_ips | tr '\n' ',') "
    [[ "$socks_ips" ]]    && proto_ips+="SOCKS:$(echo $socks_ips | tr '\n' ',') "

    printf "%-15s %-12d %-10s %-12s %-45s\n" "$username" "$connected_devices" "$limite" "$connection_time" "$proto_ips"
done < "$USER_FILE"
