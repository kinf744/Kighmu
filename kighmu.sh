#!/bin/bash
# ==============================================
# Kighmu VPS Manager - Version Dynamique Corrigée
# ==============================================

# Vérifier si root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "\e[31m[ERREUR]\e[0m Veuillez exécuter ce script en root."
    exit 1
fi

# Couleurs
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_FILE="/etc/kighmu/users.list"
AUTH_LOG="/var/log/auth.log"
OPENVPN_STATUS="/etc/openvpn/openvpn-status.log"
WIREGUARD_CMD="wg"

get_ssh_users_count() {
    grep -cE "/home" /etc/passwd
}

# Fonction pour récupérer IP et utilisateur des connexions TCP établies sur un port
get_user_ips_by_service() {
    local port="$1"
    ss -tnp state established sport = :$port 2>/dev/null | awk '
    NR>1 {
        split($6,a,",");
        pid=a[2]; sub("pid=","",pid);
        ip=$5; sub(/:[0-9]+$/,"",ip);
        cmd="ps -p " pid " -o user= 2>/dev/null"
        cmd | getline user
        close(cmd)
        if(user!="" && ip!="") print user, ip
    }'
}

# Dropbear IP par utilisateur via pgrep et auth.log
get_dropbear_user_ips() {
    local pids=($(pgrep dropbear))
    for pid in "${pids[@]}"; do
        local entry=$(grep "Password auth succeeded" "$AUTH_LOG" | grep "dropbear\[$pid\]" | tail -1)
        if [[ -n $entry ]]; then
            local user=$(echo "$entry" | awk '{print $10}' | tr -d "'")
            local ip=$(echo "$entry" | awk -F'from ' '{print $2}' | awk '{print $1}')
            echo "$user $ip"
        fi
    done
}

# OpenVPN IP et utilisateur via statut
get_openvpn_user_ips() {
    if [ -f "$OPENVPN_STATUS" ]; then
        grep 'CLIENT_LIST' "$OPENVPN_STATUS" | awk -F',' '{print $2, $3}'
    fi
}

# WireGuard IP et utilisateur
get_wireguard_user_ips() {
    if command -v $WIREGUARD_CMD >/dev/null 2>&1; then
        $WIREGUARD_CMD show | awk '
            /peer: / {peer=$2}
            /endpoint:/ {print peer, $2}
        ' | cut -d: -f1,2
    fi
}

# Calcule durée connexion SSH la plus ancienne
get_ssh_connection_time() {
    local user="$1"
    local pids=($(pgrep -u "$user" sshd))
    local earliest=0
    for pid in "${pids[@]}"; do
        local etime=$(ps -p "$pid" -o etime= | tr -d ' ')
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

while true; do
    clear
    OS_INFO=$(if [ -f /etc/os-release ]; then . /etc/os-release; echo "$NAME $VERSION_ID"; else uname -s; fi)
    IP=$(hostname -I | awk '{print $1}')
    RAM_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2}')
    CPU_USAGE=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.2f%%", usage}')
    SSH_USERS_COUNT=$(get_ssh_users_count)
    
    # Nombre total d'appareils connectés (optionnel: fusionner par utilisateur si besoin)
    # Ici on affiche la somme sur tous les services (simple version)
    mapfile -t ssh_ips < <(get_user_ips_by_service 22)
    mapfile -t dropbear_ips < <(get_dropbear_user_ips)
    mapfile -t openvpn_ips < <(get_openvpn_user_ips)
    mapfile -t wireguard_ips < <(get_wireguard_user_ips)

    all_ips=("${ssh_ips[@]}" "${dropbear_ips[@]}" "${openvpn_ips[@]}" "${wireguard_ips[@]}")
    total_connected=$(printf "%s\n" "${all_ips[@]}" | awk '{print $2}' | sort -u | wc -l)

    echo -e "${CYAN}+==================================================+${RESET}"
    echo -e "${BOLD}${MAGENTA}|                🚀 KIGHMU MANAGER 🇨🇲 🚀           |${RESET}"
    echo -e "${CYAN}+==================================================+${RESET}"

    printf " OS: %-20s | IP: %-15s\n" "$OS_INFO" "$IP"

    printf " RAM utilisée: ${GREEN}%-6s${RESET} | CPU utilisé: ${YELLOW}%-6s${RESET}\n" "$RAM_USAGE" "$CPU_USAGE"

    echo -e "${CYAN}+--------------------------------------------------+${RESET}"

    printf " Utilisateurs SSH: ${BLUE}%-4d${RESET} | Appareils connectés: ${MAGENTA}%-4d${RESET}\n" "$SSH_USERS_COUNT" "$total_connected"

    echo -e "${CYAN}+--------------------------------------------------+${RESET}"

    echo -e "${BOLD}${YELLOW}|                  MENU PRINCIPAL:                 |${RESET}"
    echo -e "${CYAN}+--------------------------------------------------+${RESET}"
    echo -e "${GREEN}[01]${RESET} Créer un utilisateur SSH"
    echo -e "${GREEN}[02]${RESET} Créer un test utilisateur"
    echo -e "${GREEN}[03]${RESET} Voir les utilisateurs en ligne"
    echo -e "${GREEN}[04]${RESET} Modifier durée / mot de passe utilisateur"
    echo -e "${GREEN}[05]${RESET} Supprimer un utilisateur"
    echo -e "${GREEN}[06]${RESET} Installation de mode"
    echo -e "${GREEN}[07]${RESET} V2ray slowdns mode"
    echo -e "${GREEN}[08]${RESET} Désinstaller le script"
    echo -e "${GREEN}[09]${RESET} Blocage de torrents"
    echo -e "${RED}[10] Quitter${RESET}"
    echo -e "${CYAN}+--------------------------------------------------+${RESET}"
    echo -ne "${BOLD}${YELLOW} Entrez votre choix [1-10]: ${RESET}"
    read -r choix
    echo -e "${CYAN}+--------------------------------------------------+${RESET}"

    case $choix in
        1) bash "$SCRIPT_DIR/menu1.sh" ;;
        2) bash "$SCRIPT_DIR/menu2.sh" ;;
        3) bash "$SCRIPT_DIR/menu3.sh" ;;
        4) bash "$SCRIPT_DIR/menu_4.sh" ;;
        5) bash "$SCRIPT_DIR/menu4.sh" ;;
        6) bash "$SCRIPT_DIR/menu5.sh" ;;
        7) bash "$SCRIPT_DIR/menu_5.sh" ;;
        8)
            echo -e "${YELLOW}⚠️  Vous êtes sur le point de désinstaller le script.${RESET}"
            read -p "Voulez-vous vraiment continuer ? (o/N): " confirm
            if [[ "$confirm" =~ ^[Oo]$ ]]; then
                echo -e "${RED}Désinstallation en cours...${RESET}"
                rm -rf "$SCRIPT_DIR"
                clear
                echo -e "${RED}✅ Script désinstallé avec succès.${RESET}"
                echo -e "${CYAN}Le panneau de contrôle est maintenant désactivé.${RESET}"
                exit 0
            else
                echo -e "${GREEN}Opération annulée, retour au menu...${RESET}"
            fi
            ;;
        9) bash "$SCRIPT_DIR/menu7.sh" ;;
        10)
            clear
            echo -e "${RED}Au revoir !${RESET}"
            exit 0
            ;;
        *)
            echo -e "${RED}Choix invalide !${RESET}" ;;
    esac

    echo ""
    read -p "Appuyez sur Entrée pour revenir au menu..."
done
