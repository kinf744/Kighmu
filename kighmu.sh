#!/bin/bash
# ==============================================
# Kighmu VPS Manager - Version Dynamique & SSH Fix + Mode Debug
# ==============================================

_DEBUG="off"  # mettre "on" pour activer le mode debug réseau

DEBUG() {
  if [ "$_DEBUG" = "on" ]; then
    echo -e "${YELLOW}[DEBUG] $*${RESET}"
  fi
}

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
MAGENTA_VIF="\e[1;35m"
CYAN="\e[36m"
CYAN_VIF="\e[1;36m"
BOLD="\e[1m"
RESET="\e[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_FILE="/etc/kighmu/users.list"
AUTH_LOG="/var/log/auth.log"
OPENVPN_STATUS="/etc/openvpn/openvpn-status.log"
WIREGUARD_CMD="wg"

detect_interfaces() {
  ip -o link show up | awk -F': ' '{print $2}' | grep -v '^lo$' | grep -vE '^(docker|veth|br|virbr|wl|vmnet|vboxnet)'
}

bytes_to_gb() {
  echo "scale=2; $1/1024/1024/1024" | bc
}

count_ssh_users() {
  # Compte les utilisateurs avec home dans /home et shell valide dans /etc/shells
  awk -F: '
    $6 ~ /^\/home/ && system("grep -Fxq " $7 " /etc/shells") == 0 {print $1}
  ' /etc/passwd | wc -l
}

# Fonctions pour connecter utilisateurs (reprendre celles déclarées dans l'ancien script si besoin)
get_user_ips_by_service() {
    # Usage: get_user_ips_by_service <port> (example: 22 for SSH)
    ss -tpn | grep ":$1" | grep -v '127.0.0.1' | grep ESTAB | awk -F'[ ,]+' '{print $6}' | sed -r 's/.*addr=//;s/port=.*//'
}

get_dropbear_user_ips() {
    ps aux | grep dropbear | grep 'root@' | grep -v grep | awk '{print $17}' | sed 's/]:.*//;s/\[//'
}

get_openvpn_user_ips() {
    if [ -f "$OPENVPN_STATUS" ]; then
        grep -E ",([0-9]{1,3}\.){3}[0-9]{1,3}," "$OPENVPN_STATUS" | awk -F, '{print $1}'
    fi
}

get_wireguard_user_ips() {
    if command -v $WIREGUARD_CMD &>/dev/null; then
        $WIREGUARD_CMD show | grep 'endpoint' | awk '{print $2}' | cut -d: -f1
    fi
}


while true; do
    clear

    OS_INFO=$(if [ -f /etc/os-release ]; then . /etc/os-release; echo "$NAME $VERSION_ID"; else uname -s; fi)
    IP=$(hostname -I | awk '{print $1}')
    TOTAL_RAM=$(free -m | awk 'NR==2{print $2 " Mo"}')
    CPU_FREQ=$(lscpu | awk -F: '/CPU max MHz/ {gsub(/^[ \t]+/, "", $2); print $2 " MHz"}')
    RAM_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2}')
    CPU_USAGE=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.2f%%", usage}')

    # ----- Utilisateurs connectés -----
    mapfile -t ssh_ips < <(get_user_ips_by_service 22 2>/dev/null || echo "")
    mapfile -t dropbear_ips < <(get_dropbear_user_ips 2>/dev/null || echo "")
    mapfile -t openvpn_ips < <(get_openvpn_user_ips 2>/dev/null || echo "")
    mapfile -t wireguard_ips < <(get_wireguard_user_ips 2>/dev/null || echo "")
    all_ips=("${ssh_ips[@]}" "${dropbear_ips[@]}" "${openvpn_ips[@]}" "${wireguard_ips[@]}")
    total_connected=$(printf "%s\n" "${all_ips[@]}" | awk '{print $1}' | sort -u | grep -v '^$' | wc -l)

    # Compte précis des utilisateurs SSH
    SSH_USERS_COUNT=$(count_ssh_users)

    # ----- Consommation réseau dynamique -----
    mapfile -t NET_INTERFACES < <(detect_interfaces)
    DEBUG "Interfaces détectées : ${NET_INTERFACES[*]}"

    DATA_DAY_BYTES=0
    DATA_MONTH_BYTES=0

    for iface in "${NET_INTERFACES[@]}"; do
      day_raw=$(vnstat -i "$iface" --oneline 2>/dev/null | cut -d\; -f9)
      month_raw=$(vnstat -i "$iface" --oneline 2>/dev/null | cut -d\; -f15)
      day_bytes=$(echo "$day_raw" | tr -cd '0-9')
      month_bytes=$(echo "$month_raw" | tr -cd '0-9')
      day_bytes=${day_bytes:-0}
      month_bytes=${month_bytes:-0}
      DEBUG "Interface $iface - Jour: $day_bytes octets, Mois: $month_bytes octets"
      DATA_DAY_BYTES=$((DATA_DAY_BYTES + day_bytes))
      DATA_MONTH_BYTES=$((DATA_MONTH_BYTES + month_bytes))
    done

    DATA_DAY_GB=$(bytes_to_gb "$DATA_DAY_BYTES")
    DATA_MONTH_GB=$(bytes_to_gb "$DATA_MONTH_BYTES")

    echo -e "${CYAN}+======================================================+${RESET}"
    echo -e "${BOLD}${MAGENTA}|                  🚀 KIGHMU MANAGER 🇨🇲 🚀             |${RESET}"
    echo -e "${CYAN}+======================================================+${RESET}"

    printf " OS: %-20s | IP: %-15s\n" "$OS_INFO" "$IP"
    echo -e "${CYAN} Taille RAM: ${GREEN}$TOTAL_RAM${RESET}"
    echo -e "${CYAN} CPU fréquence: ${YELLOW}$CPU_FREQ${RESET}"
    printf " RAM utilisée: ${GREEN}%-6s${RESET} | CPU utilisé: ${YELLOW}%-6s${RESET}\n" "$RAM_USAGE" "$CPU_USAGE"

    echo -e "${CYAN}+======================================================+${RESET}"
    printf " Utilisateurs SSH: ${BLUE}%-4d${RESET} | Appareils connectés: ${MAGENTA}%-4d${RESET}\n" "$SSH_USERS_COUNT" "$total_connected"
    printf " Consommation aujourd'hui : ${MAGENTA_VIF}%.2f Go${RESET} | Ce mois-ci : ${CYAN_VIF}%.2f Go${RESET}\n" "$DATA_DAY_GB" "$DATA_MONTH_GB"

    echo -e "${CYAN}+======================================================+${RESET}"

    echo -e "${BOLD}${YELLOW}|                    MENU PRINCIPAL:                   |${RESET}"
    echo -e "${CYAN}+======================================================+${RESET}"
    echo -e "${GREEN}${BOLD}[01]${RESET} ${YELLOW}Créer un utilisateur SSH${RESET}"
    echo -e "${GREEN}${BOLD}[02]${RESET} ${YELLOW}Créer un test utilisateur${RESET}"
    echo -e "${GREEN}${BOLD}[03]${RESET} ${YELLOW}Voir les utilisateurs en ligne${RESET}"
    echo -e "${GREEN}${BOLD}[04]${RESET} ${YELLOW}Modifier durée / mot de passe utilisateur${RESET}"
    echo -e "${GREEN}${BOLD}[05]${RESET} ${YELLOW}Supprimer un utilisateur${RESET}"
    echo -e "${GREEN}${BOLD}[06]${RESET} ${YELLOW}Message du serveur${RESET}"
    echo -e "${GREEN}${BOLD}[07]${RESET} ${YELLOW}Installation de mode${RESET}"
    echo -e "${GREEN}${BOLD}[08]${RESET} ${YELLOW}V2ray slowdns mode${RESET}"
    echo -e "${GREEN}${BOLD}[09]${RESET} ${YELLOW}Désinstaller le script${RESET}"
    echo -e "${GREEN}${BOLD}[10]${RESET} ${YELLOW}Blocage de torrents${RESET}"
    echo -e "${RED}[00] Quitter${RESET}"
    echo -e "${CYAN}+======================================================+${RESET}"
    echo -ne "${BOLD}${YELLOW} Entrez votre choix [1-10]: ${RESET}"
    read -r choix
    echo -e "${CYAN}+------------------------------------------------------+${RESET}"

    case $choix in
        1) bash "$SCRIPT_DIR/menu1.sh" ;;
        2) bash "$SCRIPT_DIR/menu2.sh" ;;
        3) bash "$SCRIPT_DIR/menu3.sh" ;;
        4) bash "$SCRIPT_DIR/menu_4.sh" ;;
        5) bash "$SCRIPT_DIR/menu4.sh" ;;
        6) bash "$SCRIPT_DIR/menu4_2.sh" ;;
        7) bash "$SCRIPT_DIR/menu5.sh" ;;
        8) bash "$SCRIPT_DIR/menu_5.sh" ;;
        9)
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
        10) bash "$SCRIPT_DIR/menu7.sh" ;;
        00)
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

