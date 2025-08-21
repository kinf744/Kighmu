#!/bin/bash
# menu3_realtime.sh
# Afficher en temps réel les utilisateurs, connexions et consommation Go

USER_FILE="/etc/kighmu/users.list"
REFRESH=3
WIDTH=70

# Couleurs
RESET="\e[0m"
BOLD="\e[1m"
CYAN="\e[36m"
MAGENTA="\e[35m"
YELLOW="\e[33m"

line_full() { echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"; }
center_line() {
    local text="$1"
    local padding=$(( (WIDTH - ${#text}) / 2 ))
    printf "|%*s%s%*s|\n" $padding "" "$text" $padding ""
}
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }

get_traffic() {
    local username="$1"
    local bytes=$(iptables -L TRAFFIC -v -n | grep "$username" | awk '{sum += $2} END {print sum}')
    if [ -z "$bytes" ]; then echo "0"; else echo $((bytes/1024/1024/1024)); fi
}

get_connections() {
    local username="$1"
    local ssh_count=$(who | awk '{print $1}' | grep -c "^$username$")
    local udp_count=$(pgrep -f "udp_custom.sh" | wc -l)
    local socks_count=$(pgrep -f "KIGHMUPROXY.py" | wc -l)
    echo $((ssh_count + udp_count + socks_count))
}

show_stats() {
    clear
    line_full
    center_line "${BOLD}${MAGENTA}UTILISATEURS EN LIGNE - EN TEMPS RÉEL${RESET}"
    line_full
    printf "| %-15s %-12s %-12s |\n" "UTILISATEUR" "CONNECTÉS" "CONSOMMÉ (Go)"
    line_simple

    while IFS="|" read -r username password limite expire_date host_ip domain slowdns_ns; do
        connected=$(get_connections "$username")
        traffic=$(get_traffic "$username")
        printf "| %-15s %-12s %-12s |\n" "$username" "$connected" "$traffic"
    done < "$USER_FILE"

    line_full
    echo -e "${YELLOW}Actualisation toutes les $REFRESH secondes. Ctrl+C pour quitter.${RESET}"
}

while true; do
    show_stats
    sleep $REFRESH
done
