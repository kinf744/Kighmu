#!/bin/bash
# ==============================================
# menu3.sh - Utilisateurs en ligne
# ==============================================

setup_colors() {
  RED=""; GREEN=""; YELLOW=""; BLUE=""
  MAGENTA=""; MAGENTA_VIF=""; CYAN=""; CYAN_VIF=""
  WHITE=""; WHITE_BOLD=""; BOLD=""; RESET=""
  if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"; MAGENTA="$(tput setaf 5)"
    MAGENTA_VIF="$(tput setaf 5; tput bold)"
    CYAN="$(tput setaf 6)"; CYAN_VIF="$(tput setaf 6; tput bold)"
    WHITE="$(tput setaf 7)"; WHITE_BOLD="$(tput setaf 7; tput bold)"
    BOLD="$(tput bold)"; RESET="$(tput sgr0)"
  fi
}
setup_colors

USER_FILE="/etc/kighmu/users.list"

clear
echo -e "${CYAN}+============================================================+${RESET}"
echo -e "${BOLD}${MAGENTA_VIF}|         GESTION DES UTILISATEURS EN LIGNE                  |${RESET}"
echo -e "${CYAN}+============================================================+${RESET}"

if [ ! -f "$USER_FILE" ] || [ ! -s "$USER_FILE" ]; then
  echo -e "${YELLOW}Aucun utilisateur enregistré.${RESET}"
  read -rp "Appuyez sur Entrée pour revenir au menu..."
  exit 0
fi

# ── Comptage appareils connectés par user via PIDs sshd ──────
# Méthode fiable : lit les PIDs des processus sshd sur port 22
# et remonte le user propriétaire du processus (fonctionne avec
# SSH-SSL, SSH-WS, SSH-SlowDNS, SSH-Direct, Dropbear, etc.)
declare -A USER_DEVICES
while read -r pid; do
  user=$(ps -o user= -p "$pid" 2>/dev/null | tr -d ' ')
  if [[ -n "$user" && "$user" != "root" && "$user" != "sshd" ]]; then
    USER_DEVICES["$user"]=$(( ${USER_DEVICES["$user"]:-0} + 1 ))
  fi
done < <(ss -tnp | grep ':22 ' | grep ESTAB | grep -oP 'pid=\K[0-9]+' | sort -u)

# ── En-tête tableau ──────────────────────────────────────────
printf "\n${BOLD}${WHITE_BOLD}%-4s  %-20s %-12s %-12s %-12s${RESET}\n" \
  "N°" "UTILISATEUR" "EXPIRE" "LIMITE(j)" "APPAREILS"
echo -e "${CYAN}------------------------------------------------------------${RESET}"

# ── Affichage de tous les utilisateurs du fichier ────────────
TODAY=$(date +%Y-%m-%d)
index=0
total_devices=0
total_users=0
online_users=0

while IFS="|" read -r username password limite expire_date hostip domain slowdns_ns; do
  [[ -z "$username" ]] && continue
  index=$(( index + 1 ))
  total_users=$(( total_users + 1 ))

  devices=${USER_DEVICES["$username"]:-0}
  total_devices=$(( total_devices + devices ))

  # Statut expiration
  if [[ "$expire_date" < "$TODAY" ]]; then
    status="${RED}[EXPIRÉ]${RESET}"
  else
    status="${GREEN}[ACTIF]${RESET}"
  fi

  # Couleur appareils
  if (( devices > 0 )); then
    online_users=$(( online_users + 1 ))
    dev_color="${GREEN}${devices}${RESET}"
  else
    dev_color="${YELLOW}0${RESET}"
  fi

  printf "${BOLD}%-4s${RESET}  ${CYAN_VIF}%-20s${RESET} %-12s %-12s " \
    "[$index]" "$username" "$expire_date" "$limite"
  echo -e "${dev_color}  ${status}"

done < "$USER_FILE"

echo -e "${CYAN}------------------------------------------------------------${RESET}"
echo -e " ${WHITE_BOLD}Total utilisateurs :${RESET} ${GREEN}${total_users}${RESET}  |  ${WHITE_BOLD}En ligne :${RESET} ${GREEN}${online_users}${RESET}  |  ${WHITE_BOLD}Appareils connectés :${RESET} ${MAGENTA_VIF}${total_devices}${RESET}"
echo -e "${CYAN}+============================================================+${RESET}"

read -rp "Appuyez sur Entrée pour revenir au menu..."
