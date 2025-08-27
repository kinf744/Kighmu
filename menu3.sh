#!/bin/bash
# Kighmu VPS Manager - Comptage précis des appareils connectés

USER_FILE="/etc/kighmu/users.list"
AUTH_LOG="/var/log/auth.log"
OPENVPN_STATUS="/etc/openvpn/openvpn-status.log"
SLOWDNS_PORT=5300
UDP_CUSTOM_PORT=54000
SOCKS_PORT=8080
WIREGUARD_CMD="wg"

if [ ! -f "$USER_FILE" ]; then
    echo "Aucun utilisateur trouvé."
    exit 1
fi

echo "+----------------------------------------------------------------------------------------+"
echo "|                            UTILISATEURS ET APPAREILS CONNECTÉS                         |"
echo "+----------------------------------------------------------------------------------------+"
printf "%-15s %-10s %-8s %-12s %-50s\n" "UTILISATEUR" "APPAREILS" "LIMITE" "TEMPS_CONN." "PROTOCOLES (IP connectées)"
echo "--------------------------------------------------------------------------------------------------------------"

# Fonction pour extraire IP, utilisateur depuis connexions SSH et Dropbear
get_user_ips_by_service() {
    local service_name=$1
    local service_port=$2
    ss -tnp state established sport = :$service_port 2>/dev/null | awk -v srv="$service_name" '
        NR>1 {
            split($6,a,",");
            pid=a[2]; sub("pid=","",pid);
            ip=$5; sub(/:[0-9]+$/,"",ip);
            cmd="ps -p "pid" -o user= 2>/dev/null";
            cmd | getline user;
            close(cmd);
            if (user != "" && ip != "") print user, ip;
        }
    '
}

# Fonction pour extraire IP et utilisateur Dropbear via auth.log et pgrep
get_dropbear_user_ips() {
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

# OpenVPN : récupère utilisateur et IP
get_openvpn_user_ips() {
    if [ -f "$OPENVPN_STATUS" ]; then
        grep 'CLIENT_LIST' "$OPENVPN_STATUS" | awk -F',' '{print $2, $3}'
    fi
}

# WireGuard : récupère peer (utilisateur) et IP endpoint
get_wireguard_user_ips() {
    if command -v $WIREGUARD_CMD >/dev/null 2>&1; then
        $WIREGUARD_CMD show | awk '
            /peer: / {peer=$2}
            /endpoint:/ {print peer, $2}
        ' | cut -d: -f1,2
    fi
}

# Calcule la durée de connexion SSH la plus ancienne pour un utilisateur
get_ssh_connection_time() {
    local user=$1
    local pids=($(pgrep -u "$user" sshd))
    local earliest=0
    for pid in "${pids[@]}"; do
        etime=$(ps -p "$pid" -o etime= | tr -d ' ')
        if [[ $etime =~ ^([0-9]+)-([0-9]{2}):([0-9]{2}):([0-9]{2})$ ]]; then
            days=${BASH_REMATCH[1]}
            hh=${BASH_REMATCH[2]}
            mm=${BASH_REMATCH[3]}
            ss=${BASH_REMATCH[4]}
            total_seconds=$((days*86400 + 10#$hh*3600 + 10#$mm*60 + 10#$ss))
        elif [[ $etime =~ ^([0-9]{2}):([0-9]{2}):([0-9]{2})$ ]]; then
            hh=${BASH_REMATCH[1]}
            mm=${BASH_REMATCH[2]}
            ss=${BASH_REMATCH[3]}
            total_seconds=$((10#$hh*3600 + 10#$mm*60 + 10#$ss))
        else
            total_seconds=0
        fi
        if [[ $earliest -eq 0 || $total_seconds -lt $earliest ]]; then
            earliest=$total_seconds
        fi
    done
    if [[ $earliest -gt 0 ]]; then
        printf '%02d:%02d:%02d\n' $((earliest/3600)) $(((earliest%3600)/60)) $((earliest%60))
    else
        echo "00:00:00"
    fi
}

while IFS="|" read -r username password limite expire_date rest; do
    ssh_ips=$(get_user_ips_by_service "sshd" 22 | awk -v u="$username" '$1==u {print $2}')
    dropbear_ips=$(get_dropbear_user_ips | awk -v u="$username" '$1==u {print $2}')
    openvpn_ips=$(get_openvpn_user_ips | awk -v u="$username" '$1==u {print $2}')
    wireguard_ips=$(get_wireguard_user_ips | awk -v u="$username" '$1==u {print $2}')
    
    # IPs multi-services fusionnées sans doublons
    user_ips=$(echo -e "$ssh_ips\n$dropbear_ips\n$openvpn_ips\n$wireguard_ips" | sort -u | grep -v "^$")

    connected_devices=$(echo "$user_ips" | wc -l)

    connection_time=$(get_ssh_connection_time "$username")

    proto_ips=""
    [[ "$ssh_ips" ]] && proto_ips+="SSH:$(echo $ssh_ips | tr '\n' ',') "
    [[ "$dropbear_ips" ]] && proto_ips+="Dropbear:$(echo $dropbear_ips | tr '\n' ',') "
    [[ "$openvpn_ips" ]] && proto_ips+="OpenVPN:$(echo $openvpn_ips | tr '\n' ',') "
    [[ "$wireguard_ips" ]] && proto_ips+="WireGuard:$(echo $wireguard_ips | tr '\n' ',') "

    printf "%-15s %-10d %-8s %-12s %-50s\n" "$username" "$connected_devices" "$limite" "$connection_time" "$proto_ips"
done < "$USER_FILE"
