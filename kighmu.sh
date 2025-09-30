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

detect_interfaces() {
  ip -o link show up | awk -F': ' '{print $2}' | grep -v '^lo$' | grep -vE '^(docker|veth|br|virbr|wl|vmnet|vboxnet)'
}

bytes_to_gb() {
  echo "scale=2; $1/1024/1024/1024" | bc
}

count_ssh_users() {
  awk -F: '($3 >= 1000) && ($7 ~ /^\/(bin\/bash|bin\/sh|bin\/false)$/) {print $1}' /etc/passwd | wc -l
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
    RAM_GB_ARR=$(echo "$RAM_GB" | awk '{printf "%d\n", ($1 == int($1)) ? $1 : int($1)+1}')
    
    CPU_CORES=$(nproc)
    RAM_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2}')
    CPU_USAGE=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.2f%%", usage}')

    total_connected=$(count_connected_devices)
    SSH_USERS_COUNT=$(count_ssh_users)

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

  printf " OS: %-20s | IP: %-15s
" "$OS_INFO" "$IP"
  printf " Taille RAM totale: ${GREEN}%-6s${RESET} | Nombre de cœurs CPU: ${YELLOW}%-6s${RESET}
" "$RAM_GB_ARR" "$CPU_CORES"
  printf " RAM utilisée: ${GREEN}%-6s${RESET} | CPU utilisé: ${YELLOW}%-6s${RESET}
" "$RAM_USAGE" "$CPU_USAGE"

  echo -e "${CYAN}+======================================================+${RESET}"

  printf " Consommation aujourd'hui: ${MAGENTA_VIF}%.2f Go${RESET} | Ce mois-ci: ${CYAN_VIF}%.2f Go${RESET}
" "$DATA_DAY_GB" "$DATA_MONTH_GB"

  printf " Utilisateurs SSH: ${BLUE}%-4d${RESET} | Appareils connectés: ${MAGENTA}%-4d${RESET}
" "$SSH_USERS_COUNT" "$total_connected"

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
  echo -e "${GREEN}${BOLD}[09]${RESET} ${YELLOW}Bot Telegram${RESET}"
  echo -e "${GREEN}${BOLD}[10]${RESET} ${YELLOW}Désinstaller le script${RESET}"
  echo -e "${GREEN}${BOLD}[11]${RESET} ${YELLOW}Blocage de torrents${RESET}"
  echo -e "${RED}[00] Quitter${RESET}"
  echo -e "${CYAN}+======================================================+${RESET}"

  echo -ne "${BOLD}${YELLOW} Entrez votre choix [1-11]: ${RESET}"
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
    9) bash "$SCRIPT_DIR/botssh.sh" ;;
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
