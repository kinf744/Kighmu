#!/bin/bash

# ==============================================
# Monitoring VPS Manager - Version Dynamique & SSH Fix + Mode Debug
# ==============================================

_DEBUG="off"

DEBUG() {
  if [ "$_DEBUG" = "on" ]; then
    echo -e "${YELLOW}[DEBUG] $*${RESET}"
  fi
}

# Prérequis et variables globales
# Détection portable des couleurs
setup_colors() {
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  MAGENTA=""
  MAGENTA_VIF=""
  CYAN=""
  CYAN_VIF=""
  WHITE=""
  WHITE_BOLD=""
  BOLD=""
  RESET=""

  if [ -t 1 ]; then
    if [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
      RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"
      BLUE="$(tput setaf 4)"; MAGENTA="$(tput setaf 5)"; MAGENTA_VIF="$(tput setaf 5; tput bold)"
      CYAN="$(tput setaf 6)"; CYAN_VIF="$(tput setaf 6; tput bold)"
      WHITE="$(tput setaf 7)"; WHITE_BOLD="$(tput setaf 7; tput bold)"
      BOLD="$(tput bold)"; RESET="$(tput sgr0)"
    fi
  fi
  # Si non-interactif ou pas de couleur, laisser vides et tout sera en texte neutre
}

# Appel de la config couleur
setup_colors

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_FILE="/etc/kighmu/users.list"
AUTH_LOG="/var/log/auth.log"

clear
echo -e "${CYAN}+============================================================+${RESET}"
echo -e "${BOLD}${MAGENTA}|            GESTION DES UTILISATEURS EN LIGNE               |${RESET}"
echo -e "${CYAN}+============================================================+${RESET}"

if [ ! -f "$USER_FILE" ]; then
    echo -e "${RED}Fichier utilisateur introuvable.${RESET}"
    exit 1
fi

printf "${BOLD}%-20s %-10s %-15s %-15s${RESET}
" "${WHITE_BOLD}UTILISATEUR${RESET}" "  ${WHITE_BOLD}     LIMITÉ${RESET}" "  ${WHITE_BOLD}   CONNECTÉS${RESET}" "  ${WHITE_BOLD}    TRAFIC TOTAL${RESET}"
echo -e "${CYAN}--------------------------------------------------------------${RESET}"

# Fonction pour compter appareils connectés par utilisateur
count_devices_per_user() {
  declare -A user_counts

  # Comptage SSH sessions non-root (sshd)
  while read -r pid user cmd; do
    if [[ "$cmd" == *sshd* && "$user" != "root" ]]; then
      ((user_counts[$user]++))
    fi
  done < <(ps -eo pid,user,comm)

  # Comptage Dropbear sessions par clients connectés via logs auth.log
  if [[ -f $AUTH_LOG ]]; then
    drop_pids=$(ps aux | grep '[d]ropbear' | awk '{print $2}')
    for pid in $drop_pids; do
      user=$(grep -a "sshd.*$pid" $AUTH_LOG | tail -1 | awk '{print $10}')
      if [[ -n "$user" ]]; then
        ((user_counts[$user]++))
      fi
    done
  fi

  # Comptage OpenVPN sessions par utilisateurs dans openvpn-status.log
  if [[ -f /etc/openvpn/openvpn-status.log ]]; then
    while read -r line; do
      user=$(echo "$line" | cut -d',' -f2)
      ((user_counts[$user]++))
    done < <(grep CLIENT_LIST /etc/openvpn/openvpn-status.log)
  fi

  # Retourne tableau associatif avec compte par utilisateur
  echo "${user_counts[@]}"
  declare -p user_counts
}

# Récupération des comptes d'appareils par utilisateur
eval "$(count_devices_per_user | tail -n +2)"  # Cette ligne importe le tableau user_counts

# Helpers pour trafic per-interface et per-user
octets_to_go() {
  local bytes=$1
  printf "%.2f" "$(awk -v b="$bytes" 'BEGIN { printf (b/1024/1024/1024) }')"
}

read_proc_net_dev() {
  local -n rx_out=$1
  local -n tx_out=$2
  rx_out=()
  tx_out=()
  while read -r line; do
    if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9._-]+): ]]; then
      iface="${BASH_REMATCH[1]}"
      rx=$(echo "$line" | awk '{print $2}')
      tx=$(echo "$line" | awk '{print $10}')
      rx_out["$iface"]="$rx"
      tx_out["$iface"]="$tx"
    fi
  done < <(grep -E "^[[:space:]]*[a-zA-Z0-9._-]+:" /proc/net/dev)
}

# Calcul et affichage sur une seule ligne par utilisateur
display_all_users_with_traffic_on_one_line() {
  # Lire trafic par interface
  declare -A IF_RX IF_TX
  read_proc_net_dev IF_RX IF_TX

  # Préparer la liste des utilisateurs actifs (ordre tel que dans USER_FILE)
  local users_order=()
  for u in "${!user_counts[@]}"; do
    if [[ -n "${user_counts[$u]}" ]]; then
      users_order+=("$u")
    fi
  done

  # Déterminer le nombre d’utilisateurs actifs
  local n_users=${#users_order[@]}

  # Imprimer chaque utilisateur sur une ligne avec trafic total calculé
  while IFS="|" read -r username password limite expire_date hostip domain slowdns_ns; do
    app_connecte=${user_counts[$username]:-0}

    # Calcul trafic total estimé pour cet utilisateur
    local total_bytes=0
    for iface in "${!IF_RX[@]}"; do
      local iface_total=$(( IF_RX[$iface] + IF_TX[$iface] ))
      if (( n_users > 0 )); then
        total_bytes=$(( total_bytes + (iface_total / n_users) ))
      fi
    done
    local total_go
    total_go=$(octets_to_go "$total_bytes")

    printf "%-20s %-10s %-15d %-15s
" "$username" "$limite" "$app_connecte" "${total_go} Go total"
  done < "$USER_FILE"
}

# Exécution: ligne par ligne sur une seule commande imprimant tout
display_all_users_with_traffic_on_one_line

echo -e "${CYAN}+=============================================================+${RESET}"
read -p "Appuyez sur Entrée pour revenir au menu..."
