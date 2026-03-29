#!/bin/bash
# ==============================================
# Kighmu VPS Manager - Version Dynamique & SSH Fix + Mode Debug
# ==============================================

_DEBUG="off"

DEBUG() {
  if [ "$_DEBUG" = "on" ]; then
    echo -e "${YELLOW}[DEBUG] $*${RESET}"
  fi
}

if [ "$(id -u)" -ne 0 ]; then
    echo -e "\e[31m[ERREUR]\e[0m Veuillez exécuter ce script en root."
    exit 1
fi

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
MAGENTA_VIF="\e[1;35m"
CYAN="\e[36m"
CYAN_VIF="\e[1;36m"
WHITE="\e[37m"
WHITE_BOLD="\e[1;37m"
BOLD="\e[1m"
RESET="\e[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_FILE="/etc/kighmu/users.list"
AUTH_LOG="/var/log/auth.log"

detect_interfaces() {
  ip -o link show up | awk -F': ' '{print $2}' | grep -v '^lo$' | grep -vE '^(docker|veth|br|virbr|wl|vmnet|vboxnet)'
}

# ── Conversion taille → Go (supporte KiB, MiB, GiB, TiB, PiB) ──
convert_to_gb() {
    local size_str=$1
    local num=$(echo "$size_str" | awk '{print $1}')
    local unit=$(echo "$size_str" | awk '{print $2}')
    case $unit in
        KiB) echo "scale=4; $num/1024/1024" | bc ;;
        MiB) echo "scale=4; $num/1024" | bc ;;
        GiB) echo "scale=4; $num" | bc ;;
        TiB) echo "scale=4; $num*1024" | bc ;;
        PiB) echo "scale=4; $num*1024*1024" | bc ;;
        *)   echo "0" ;;
    esac
}

count_ssh_users() {
  awk -F: '($3 >= 1000) && ($7 ~ /^\/(bin\/bash|bin\/sh|bin\/false)$/) {print $1}' /etc/passwd | wc -l
}

# ── Comptage appareils connectés (SSH-SSL, SSH-WS, SSH-Direct, etc.) ──
count_connected_devices() {
  # Compter les PIDs sshd uniques dont le propriétaire n'est pas root/sshd
  _ons=$(ss -tnp | grep ':22 ' | grep ESTAB | grep -oP 'pid=\K[0-9]+' | sort -u | while read pid; do
    user=$(ps -o user= -p "$pid" 2>/dev/null | tr -d ' ')
    [[ -n "$user" && "$user" != "root" && "$user" != "sshd" ]] && echo "$user"
  done | sort -u | wc -l)

  # OpenVPN
  [[ -e /etc/openvpn/openvpn-status.log ]] && _onop=$(grep -c "10.8.0" /etc/openvpn/openvpn-status.log) || _onop="0"

  # Dropbear
  if [[ -e /etc/default/dropbear ]]; then
    _ondrp=$(ss -tnp | grep dropbear | grep ESTAB | wc -l)
  else
    _ondrp="0"
  fi

  echo $((_ons + _onop + _ondrp))
}

count_ssh_expired() {
  local today
  today=$(date +%Y-%m-%d)
  if [[ ! -f "$USER_FILE" ]]; then
    echo 0
    return
  fi
  awk -F'|' -v today="$today" '$4 < today {count++} END {print count+0}' "$USER_FILE"
}

count_xray_expired() {
  local expiry_file="/etc/xray/users_expiry.list"
  local today=$(date +%Y-%m-%d)
  if [[ ! -f "$expiry_file" ]]; then
    echo 0
    return
  fi
  awk -F'|' -v today="$today" '$2 < today {count++} END {print count+0}' "$expiry_file"
}

get_main_ip() {
  local ip4
  ip4=$(ip -4 addr show scope global | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)
  if [[ -n "$ip4" ]]; then
    echo "$ip4"
    return
  fi
  local ip6
  ip6=$(ip -6 addr show scope global | awk '/inet6 /{print $2}' | cut -d/ -f1 | head -n1)
  if [[ -n "$ip6" ]]; then
    echo "$ip6"
    return
  fi
  echo "N/A"
}

while true; do
    clear

    OS_INFO=$(if [ -f /etc/os-release ]; then . /etc/os-release; echo "$NAME $VERSION_ID"; else uname -s; fi)
    IP=$(get_main_ip)

    TOTAL_RAM_RAW=$(free -m | awk 'NR==2{print $2}')
    RAM_GB=$(echo "scale=2; $TOTAL_RAM_RAW/1024" | bc)
    RAM_GB_ARR=$(echo "$RAM_GB" | awk '{printf "%d\n", ($1 == int($1)) ? $1 : int($1)+1}')

    CPU_CORES=$(nproc)
    RAM_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2}')
    CPU_USAGE=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.2f%%", usage}')

    total_connected=$(count_connected_devices)
    SSH_USERS_COUNT=$(count_ssh_users)

    XRAY_USERS_FILE="/etc/xray/users.json"
    if [[ -f "$XRAY_USERS_FILE" ]]; then
      vmess_count=$(jq '.vmess // [] | length' "$XRAY_USERS_FILE" 2>/dev/null || echo 0)
      vless_count=$(jq '.vless // [] | length' "$XRAY_USERS_FILE" 2>/dev/null || echo 0)
      trojan_count=$(jq '.trojan // [] | length' "$XRAY_USERS_FILE" 2>/dev/null || echo 0)
      XRAY_USERS_COUNT=$((vmess_count + vless_count + trojan_count))
    else
      vmess_count=0; vless_count=0; trojan_count=0; XRAY_USERS_COUNT=0
    fi

    SSH_EXPIRED=$(count_ssh_expired)
    XRAY_EXPIRED=$(count_xray_expired)
    TOTAL_EXPIRED=$(( SSH_EXPIRED + XRAY_EXPIRED ))

    mapfile -t NET_INTERFACES < <(detect_interfaces)
    DEBUG "Interfaces détectées : ${NET_INTERFACES[*]}"

    DATA_DAY_GB=0
    DATA_MONTH_GB=0

    for iface in "${NET_INTERFACES[@]}"; do
      ONELINE=$(vnstat -i "$iface" --oneline 2>/dev/null)
      DAY_RAW=$(echo "$ONELINE"   | cut -d';' -f6  2>/dev/null)
      MONTH_RAW=$(echo "$ONELINE" | cut -d';' -f15 2>/dev/null)
      day_gb=$(convert_to_gb "$DAY_RAW")
      month_gb=$(convert_to_gb "$MONTH_RAW")
      DATA_DAY_GB=$(echo "$DATA_DAY_GB + $day_gb"     | bc 2>/dev/null || echo 0)
      DATA_MONTH_GB=$(echo "$DATA_MONTH_GB + $month_gb" | bc 2>/dev/null || echo 0)
    done

    # ── Affichage header ─────────────────────────────────────────
    echo -e "${CYAN}+============================${WHITE_BOLD}[❖]${RESET}============================+${RESET}"

    cols=$(tput cols)
    title="🚀 KIGHMU MANAGER 🇨🇲 🚀"
    TEXT_COLOR="\e[34m"
    BG_BLUE="\e[44m"
    BG_YELLOW="\e[103m"
    RESET="\e[0m"
    padding_blue=10
    padding_yellow=2
    blue_total=$(( ${#title} + padding_blue*2 + padding_yellow*2 ))
    left_space=$(( (cols - blue_total) / 2 - 8 ))

    printf "%*s" "$left_space" ""
    printf "${BG_BLUE}"
    for ((i=0; i<blue_total; i++)); do
        if (( i >= padding_blue && i < blue_total - padding_blue )); then
            printf "${BG_YELLOW}${TEXT_COLOR}%s${BG_BLUE}" "${title:i-padding_blue-padding_yellow:1}"
        else
            printf " "
        fi
    done
    printf "${RESET}\n"

    echo -e "${CYAN}+============================${WHITE_BOLD}[❖]${RESET}============================+${RESET}"

    printf " ${WHITE_BOLD}OS:${RESET} ${YELLOW}%-20s${RESET} | ${WHITE_BOLD}IP:${RESET} ${RED}%-15s${RESET}\n" "$OS_INFO" "$IP"
    printf " ${WHITE_BOLD}Taille RAM totale:${RESET} ${GREEN}%-6s${RESET} Go | ${WHITE_BOLD}Cœurs CPU:${RESET} ${YELLOW}%-6s${RESET}\n" "$RAM_GB_ARR" "$CPU_CORES"
    printf " ${WHITE_BOLD}RAM utilisée:${RESET} ${GREEN}%-10s${RESET} | ${WHITE_BOLD}CPU utilisé:${RESET} ${YELLOW}%-6s${RESET}\n" "$RAM_USAGE" "$CPU_USAGE"

    echo -e "${CYAN}+===========================================================+${RESET}"

    printf " ${WHITE_BOLD}Consommation aujourd'hui:${RESET} ${MAGENTA_VIF}%.2f Go${RESET} | ${WHITE_BOLD}Ce mois-ci:${RESET} ${CYAN_VIF}%.2f Go${RESET}\n" "$DATA_DAY_GB" "$DATA_MONTH_GB"
    printf " ${WHITE_BOLD}Utilisateurs SSH:${RESET} ${BLUE}%-4d${RESET} | ${WHITE_BOLD}Utilisateurs Xray:${RESET} ${MAGENTA}%-4d${RESET}\n" "$SSH_USERS_COUNT" "$XRAY_USERS_COUNT"
    printf " ${WHITE_BOLD}Appareils connectés:${RESET} ${MAGENTA}%-4d${RESET} | ${WHITE_BOLD}Utilisateurs expirés:${RESET} ${RED}%-4d${RESET}\n" "$total_connected" "$TOTAL_EXPIRED"

    echo -e "${CYAN}+===========================================================+${RESET}"
    echo -e "${BOLD}${YELLOW}|                     MENU PRINCIPAL:                       |${RESET}"
    echo -e "${CYAN}+===========================================================+${RESET}"
    echo -e "${GREEN}${BOLD}[01]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Créer un utilisateur SSH${RESET}"
    echo -e "${GREEN}${BOLD}[02]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Créer un test utilisateur${RESET}"
    echo -e "${GREEN}${BOLD}[03]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Voir les utilisateurs en ligne${RESET}"
    echo -e "${GREEN}${BOLD}[04]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Modifier durée / mot de passe utilisateur${RESET}"
    echo -e "${GREEN}${BOLD}[05]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Supprimer un utilisateur${RESET}"
    echo -e "${GREEN}${BOLD}[06]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Message du serveur${RESET}"
    echo -e "${GREEN}${BOLD}[07]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Installation de mode${RESET}"
    echo -e "${GREEN}${BOLD}[08]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}V2ray Fastdns mode${RESET}"
    echo -e "${GREEN}${BOLD}[09]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Xray All mode${RESET}"
    echo -e "${GREEN}${BOLD}[10]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Désinstaller le script${RESET}"
    echo -e "${GREEN}${BOLD}[11]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Blocage de torrents${RESET}"
    echo -e "${GREEN}${BOLD}[12]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}ZIVPN TUNNEL${RESET}"
    echo -e "${GREEN}${BOLD}[13]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}HYSTERIA TUNNEL${RESET}"
    echo -e "${RED}[00] ➜ Quitter${RESET}"
    echo -e "${CYAN}+==========================================================+${RESET}"

    echo -ne "${BOLD}${YELLOW} Entrez votre choix [1-13]: ${RESET}"
    read -r choix
    echo -e "${CYAN}+----------------------------------------------------------+${RESET}"

    case $choix in
      1)  bash "$SCRIPT_DIR/menu1.sh" ;;
      2)  bash "$SCRIPT_DIR/menu2.sh" ;;
      3)  bash "$SCRIPT_DIR/menu3.sh" ;;
      4)  bash "$SCRIPT_DIR/menu_4.sh" ;;
      5)  bash "$SCRIPT_DIR/menu4.sh" ;;
      6)  bash "$SCRIPT_DIR/menu4_2.sh" ;;
      7)  bash "$SCRIPT_DIR/menu5.sh" ;;
      8)  bash "$SCRIPT_DIR/menu_5.sh" ;;
      9)  bash "$SCRIPT_DIR/menu_6.sh" ;;
      10)
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
      11) bash "$SCRIPT_DIR/menu7.sh" ;;
      12) bash "$SCRIPT_DIR/sirust.sh" ;;
      13) bash "$SCRIPT_DIR/Hysteria1.sh" ;;
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
