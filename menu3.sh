#!/bin/bash

# ==============================================
# Monitor VPS Manager - Version Dynamique & SSH Fix + Mode Debug
# ==============================================

# (restant du script inchangé, y compris les définitions et count_devices_per_user)

RED="e[31m"
GREEN="e[32m"
YELLOW="e[33m"
CYAN="e[36m"
BOLD="e[1m"
RESET="e[0m"

USER_FILE="/etc/kighmu/users.list"
AUTH_LOG="/var/log/auth.log"

clear
echo -e "${CYAN}+==============================================+${RESET}"
echo -e "|      GESTION DES UTILISATEURS EN LIGNE        |"
echo -e "${CYAN}+==============================================+${RESET}"

if [ ! -f "$USER_FILE" ]; then
    echo -e "${RED}Fichier utilisateur introuvable.${RESET}"
    exit 1
fi

printf "${BOLD}%-20s %-10s %-15s %-15s
${RESET}" "UTILISATEUR" "LIMITÉ" " CONNECTÉS" " TRAFIC TOTAL"
echo -e "${CYAN}--------------------------------------------------${RESET}"

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

# Helpers pour trafic per-interface
read_proc_net_dev() {
  declare -A IF_RX
  declare -A IF_TX
  while read -r line; do
    if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9._-]+): ]]; then
      iface="${BASH_REMATCH[1]}"
      rx=$(echo "$line" | awk '{print $2}')
      tx=$(echo "$line" | awk '{print $10}')
      IF_RX["$iface"]="$rx"
      IF_TX["$iface"]="$tx"
    fi
  done < <(grep -E "^[[:space:]]*[a-zA-Z0-9._-]+:" /proc/net/dev)
  # Export as global assoc arrays by echoing declare statements
  for k in "${!IF_RX[@]}"; do
    echo "IF_RX[$k]"=${IF_RX[$k]}""
  done
}

# Convertir octets en Go avec deux décimales
octets_to_go() {
  local bytes=$1
  printf "%.2f" "$(awk -v b="$bytes" 'BEGIN { printf (b/1024/1024/1024) }')"
}

# Calcul et affichage du trafic total par utilisateur sur la même ligne
display_traffic_total_on_same_line() {
  declare -A IF_RX
  declare -A IF_TX
  while read -r line; do
    if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9._-]+): ]]; then
      iface="${BASH_REMATCH[1]}"
      rx=$(echo "$line" | awk '{print $2}')
      tx=$(echo "$line" | awk '{print $10}')
      IF_RX["$iface"]="$rx"
      IF_TX["$iface"]="$tx"
    fi
  done < <(grep -E "^[[:space:]]*[a-zA-Z0-9._-]+:" /proc/net/dev)

  # Préparer liste des utilisateurs (ordre tel que dans USER_FILE)
  local users_order=()
  for u in "${!user_counts[@]}"; do
    if [[ -n "${user_counts[$u]}" ]]; then
      users_order+=("$u")
    fi
  done

  # Imprimer trafic total pour chaque utilisateur sur la même ligne dans le tableau
  while IFS="|" read -r username password limite expire_date hostip domain slowdns_ns; do
    app_connecte=${user_counts[$username]:-0}
    local total_bytes=0
    for iface in "${!IF_RX[@]}"; do
      local iface_total=$(( IF_RX[$iface] + IF_TX[$iface] ))
      # Répartition équitable entre les utilisateurs actifs
      local n=${#users_order[@]}
      if (( n > 0 )); then
        total_bytes=$(( total_bytes + (iface_total / n) ))
      fi
    done
    local total_go
    total_go=$(octets_to_go "$total_bytes")
    printf "%-20s %-10s %-15d %-15s
" "$username" "$limite" "$app_connecte" "$total_go Go total"
  done < "$USER_FILE"
}

# Impression initiale des utilisateurs et de leurs connexions
while IFS="|" read -r username password limite expire_date hostip domain slowdns_ns; do
    # Nombre d'appareils connecté
    app_connecte=${user_counts[$username]:-0}
    printf "%-20s %-10s %-15d %-15s
" "$username" "$limite" "$app_connecte" "-"
done < "$USER_FILE"

# Calcul et affichage du trafic total par utilisateur sur la même ligne
display_traffic_total_on_same_line

echo -e "${CYAN}+==============================================+${RESET}"
read -p "Appuyez sur Entrée pour revenir au menu..."
