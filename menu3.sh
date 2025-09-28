#!/bin/bash

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

USER_FILE="/etc/kighmu/users.list"
AUTH_LOG="/var/log/auth.log"

clear
echo -e "${CYAN}+==============================================+${RESET}"
echo -e "|            GESTION DES UTILISATEURS EN LIGNE        |"
echo -e "${CYAN}+==============================================+${RESET}"

if [ ! -f "$USER_FILE" ]; then
    echo -e "${RED}Fichier utilisateur introuvable.${RESET}"
    exit 1
fi

printf "${BOLD}%-20s %-10s %-15s\n${RESET}" "UTILISATEUR" "LIMITÉ" "APPAREILS CONNECTÉS"
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

while IFS="|" read -r username password limite expire_date hostip domain slowdns_ns; do
    # Nombre d'appareils connecté
    app_connecte=${user_counts[$username]:-0}

    printf "%-20s %-10s %-15d\n" "$username" "$limite" "$app_connecte"
done < "$USER_FILE"

echo -e "${CYAN}+==============================================+${RESET}"
read -p "Appuyez sur Entrée pour revenir au menu..."
