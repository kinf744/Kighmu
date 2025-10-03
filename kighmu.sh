#!/bin/bash
# ==============================================
# Kighmu VPS Manager - Version Dynamique & SSH Fix + Mode Debug
# ==============================================

_DEBUG="off"  # mettre "on" pour activer le mode debug réseau

DEBUG() {
  if [ "$_DEBUG" = "on" ]; then
    printf "%b
" "${YELLOW}[DEBUG] $*${RESET}"
  fi
}

if [ "$(id -u)" -ne 0 ]; then
    printf "%b
" "e[31m[ERREUR]e[0m Veuillez exécuter ce script en root."
    exit 1
fi

# Couleurs
RED="e[31m"
GREEN="e[32m"
YELLOW="e[33m"
BLUE="e[34m"
MAGENTA="e[35m"
MAGENTA_VIF="e[1;35m"
CYAN="e[36m"
CYAN_VIF="e[1;36m"
BOLD="e[1m"
RESET="e[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_FILE="/etc/kighmu/users.list"
AUTH_LOG="/var/log/auth.log"

detect_interfaces() {
  ip -o link show up | awk -F': ' '{print $2}' | grep -v '^lo$' | grep -vE '^(docker|veth|br|virbr|wl|vmnet|vboxnet)'
}

convert_to_gb() {
    local size_str=$1
    local num=$(echo "$size_str" | awk '{print $1}')
    local unit=$(echo "$size_str" | awk '{print $2}')
    case $unit in
        KiB) echo "scale=4; $num/1024/1024" | bc ;;
        MiB) echo "scale=4; $num/1024" | bc ;;
        GiB) echo "scale=4; $num" | bc ;;
        *) echo "0" ;;
    esac
}

count_ssh_users() {
  awk -F: '($3 >= 1000) && ($7 ~ /^/(bin/bash|bin/sh|bin/false)$/) {print $1}' /etc/passwd | wc -l
}

count_connected_devices() {
  _ons=$(ps -x | grep sshd | grep -v root | grep priv | wc -l)
  [[ -e /etc/openvpn/openvpn-status.log ]] && _onop=$(grep -c "10.8.0" /etc/openvpn/openvpn-status.log) || _onop="0"
  if [[ -e /etc/default/dropbear ]]; then
    _drp=$(ps aux | grep dropbear | grep -v grep | wc -l)
    _ondrp=$(($_drp - 1))
  else
    _ondrp="0"
  fi
  echo $((_ons + _onop + _ondrp))
}

while true; do
    clear

    OS_INFO=$(if [ -f /etc/os-release ]; then . /etc/os-release; echo "$NAME $VERSION_ID"; else uname -s; fi)
    IP=$(hostname -I | awk '{print $1}')
    
    TOTAL_RAM_RAW=$(free -m | awk 'NR==2{print $2}')
    RAM_GB=$(echo "scale=2; $TOTAL_RAM_RAW/1024" | bc)
    RAM_GB_ARR=$(echo "$RAM_GB" | awk '{printf "%d
", ($1 == int($1)) ? $1 : int($1)+1}')
    
    CPU_CORES=$(nproc)
    RAM_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2}')
    CPU_USAGE=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.2f%%", usage}')

    total_connected=$(count_connected_devices)
    SSH_USERS_COUNT=$(count_ssh_users)

    mapfile -t NET_INTERFACES < <(detect_interfaces)
    DEBUG "Interfaces détectées : ${NET_INTERFACES[*]}"

    DATA_DAY_GB=0
    DATA_MONTH_GB=0

    for iface in "${NET_INTERFACES[@]}"; do
      day_raw=$(vnstat -i "$iface" --oneline 2>/dev/null | cut -d';' -f9)
      month_raw=$(vnstat -i "$iface" --oneline 2>/dev/null | cut -d';' -f15)
      day_gb=$(convert_to_gb "$day_raw")
      month_gb=$(convert_to_gb "$month_raw")
      DEBUG "Interface $iface - Jour: $day_raw ($day_gb Go), Mois: $month_raw ($month_gb Go)"
      DATA_DAY_GB=$(echo "$DATA_DAY_GB + $day_gb" | bc)
      DATA_MONTH_GB=$(echo "$DATA_MONTH_GB + $month_gb" | bc)
    done

  printf "%b
" "${CYAN}+======================================================+${RESET}"
  printf "%b
" "${BOLD}${MAGENTA}|                  🚀 KIGHMU MANAGER 🇨🇲 🚀             |${RESET}"
  printf "%b
" "${CYAN}+======================================================+${RESET}"

  printf " OS: %-20s | IP: %-15s
" "$OS_INFO" "$IP"
  printf " Taille RAM totale: ${GREEN}%-6s${RESET} | Nombre de cœurs CPU: ${YELLOW}%-6s${RESET}
" "$RAM_GB_ARR" "$CPU_CORES"
  printf " RAM utilisée: ${GREEN}%-6s${RESET} | CPU utilisé: ${YELLOW}%-6s${RESET}
" "$RAM_USAGE" "$CPU_USAGE"

  printf "%b
" "${CYAN}+======================================================+${RESET}"

  printf " Consommation aujourd'hui: ${MAGENTA_VIF}%.2f Go${RESET} | Ce mois-ci: ${CYAN_VIF}%.2f Go${RESET}
" "$DATA_DAY_GB" "$DATA_MONTH_GB"

  printf " Utilisateurs SSH: ${BLUE}%-4d${RESET} | Appareils connectés: ${MAGENTA}%-4d${RESET}
" "$SSH_USERS_COUNT" "$total_connected"

  printf "%b
" "${CYAN}+======================================================+${RESET}"

  printf "%b
" "${BOLD}${YELLOW}|                    MENU PRINCIPAL:                   |${RESET}"
  printf "%b
" "${CYAN}+======================================================+${RESET}"
  printf "${GREEN}${BOLD}[01]${RESET} ${YELLOW}Créer un utilisateur SSH${RESET}
"
  printf "${GREEN}${BOLD}[02]${RESET} ${YELLOW}Créer un test utilisateur${RESET}
"
  printf "${GREEN}${BOLD}[03]${RESET} ${YELLOW}Voir les utilisateurs en ligne${RESET}
"
  printf "${GREEN}${BOLD}[04]${RESET} ${YELLOW}Modifier durée / mot de passe utilisateur${RESET}
"
  printf "${GREEN}${BOLD}[05]${RESET} ${YELLOW}Supprimer un utilisateur${RESET}
"
  printf "${GREEN}${BOLD}[06]${RESET} ${YELLOW}Message du serveur${RESET}
"
  printf "${GREEN}${BOLD}[07]${RESET} ${YELLOW}Installation de mode${RESET}
"
  printf "${GREEN}${BOLD}[08]${RESET} ${YELLOW}V2ray slowdns mode${RESET}
"
  printf "${GREEN}${BOLD}[09]${RESET} ${YELLOW}Bot Telegram${RESET}
"
  printf "${GREEN}${BOLD}[10]${RESET} ${YELLOW}Désinstaller le script${RESET}
"
  printf "${GREEN}${BOLD}[11]${RESET} ${YELLOW}Blocage de torrents${RESET}
"
  printf "${RED}[00] Quitter${RESET}
"
  printf "%b
" "${CYAN}+======================================================+${RESET}"

  printf "%b" "${BOLD}${YELLOW} Entrez votre choix [1-11]: ${RESET}"
  read -r choix
  printf "%b
" "${CYAN}+------------------------------------------------------+${RESET}"

  case $choix in
    1) bash "$SCRIPT_DIR/menu1.sh" ;;
    2) bash "$SCRIPT_DIR/menu2.sh" ;;
    3) bash "$SCRIPT_DIR/menu3.sh" ;;
    4) bash "$SCRIPT_DIR/menu_4.sh" ;;
    5) bash "$SCRIPT_DIR/menu4.sh" ;;
    6) bash "$SCRIPT_DIR/menu4_2.sh" ;;
    7) bash "$SCRIPT_DIR/menu5.sh" ;;
    8) bash "$SCRIPT_DIR/menu_5.sh" ;;
    9) bash "$SCRIPT_DIR/botssh.sh" ;;
    10)
      printf "%b
" "${YELLOW}⚠️  Vous êtes sur le point de désinstaller le script.${RESET}"
      read -p "Voulez-vous vraiment continuer ? (o/N): " confirm
      if [[ "$confirm" =~ ^[Oo]$ ]]; then
        printf "%b
" "${RED}Désinstallation en cours...${RESET}"
        rm -rf "$SCRIPT_DIR"
        clear
        printf "%b
" "${RED}✅ Script désinstallé avec succès.${RESET}"
        printf "%b
" "${CYAN}Le panneau de contrôle est maintenant désactivé.${RESET}"
        exit 0
      else
        printf "%b
" "${GREEN}Opération annulée, retour au menu...${RESET}"
      fi
      ;;
    11) bash "$SCRIPT_DIR/menu7.sh" ;;
    00)
      clear
      printf "%b
" "${RED}Au revoir !${RESET}"
      exit 0
      ;;
    *)
      printf "%b
" "${RED}Choix invalide !${RESET}" ;;
  esac

  printf "
"
  read -p "Appuyez sur Entrée pour revenir au menu..."
done
