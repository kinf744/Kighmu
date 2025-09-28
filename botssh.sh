#!/bin/bash
# KIGHMU Telegram VPS Bot Manager complet avec menu interactif

BLUE_BG="\e[44m"
RESET="\e[0m"
WHITE="\e[97m"

API_TOKEN=""
ADMIN_ID=""
KIGHMU_DIR="$HOME/Kighmu"

install_shellbot() {
  if [ ! -f /etc/kighmu/ShellBot.sh ]; then
    sudo mkdir -p /etc/kighmu
    sudo wget -qO /etc/kighmu/ShellBot.sh https://raw.githubusercontent.com/kinf744/Kighmu/main/ShellBot.sh
    sudo chmod +x /etc/kighmu/ShellBot.sh
  fi
}

check_sudo() {
  if ! sudo -v &>/dev/null; then
    echo "Run 'sudo -v' before running this script."
    exit 1
  fi
}

print_header() {
  echo -e "${BLUE_BG}${WHITE}====================================================${RESET}"
  echo -e "${BLUE_BG}${WHITE}   KIGHMU Telegram VPS Bot Manager - Menu Principal  ${RESET}"
  echo -e "${BLUE_BG}${WHITE}====================================================${RESET}"
}

ask_credentials() {
  echo -n "Entrez le API_TOKEN de votre bot Telegram : "
  read -r API_TOKEN
  echo -n "Entrez l'ADMIN_TELEGRAM_ID (ID administrateur Telegram) : "
  read -r ADMIN_ID
  echo ""
}

send_message() {
  ShellBot.sendMessage --chat_id "$1" --text "$2" --parse_mode html
}

send_user_creation_summary() {
  local chat_id=$1 domain=$2 host_ip=$3 username=$4 password=$5 limite=$6 expire_date=$7 slowdns_key=$8 slowdns_ns=$9
  local msg="<b>+=================================================================+</b>
<b>*NOUVEAU UTILISATEUR CRÉÉ*</b>
<b>━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━</b>
∘ SSH: 22                  ∘ System-DNS: 53
∘ SOCKS/PYTHON: 8080       ∘ WEB-NGINX: 81
∘ DROPBEAR: 90             ∘ SSL: 443
∘ BadVPN: 7200             ∘ BadVPN: 7300
∘ SlowDNS: 5300            ∘ UDP-Custom: 1-65535
∘ Hysteria: 22000          ∘ Proxy WS: 80
<b>━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━</b>
<b>DOMAIN         :</b> $domain
<b>Host/IP-Address:</b> $host_ip
<b>UTILISATEUR    :</b> $username
<b>MOT DE PASSE   :</b> $password
<b>LIMITE         :</b> $limite
<b>DATE EXPIRÉE   :</b> $expire_date
<b>━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━</b>
En APPS comme HTTP Injector, CUSTOM, SOCKSIP TUNNEL, SSC, etc.
🙍 HTTP-Direct     : <code>$host_ip:8080@$username:$password</code>
🙍 SSL/TLS(SNI)    : <code>$host_ip:444@$username:$password</code>
🙍 Proxy(WS)       : <code>$domain:80@$username:$password</code>
🙍 SSH UDP         : <code>$host_ip:1-65535@$username:$password</code>
🙍 Hysteria (UDP)  : <code>$domain:22000@$username:$password</code>
<b>━━━━━━━━━━━  CONFIGS SLOWDNS PORT 5300 ━━━━━━━━━━━</b>
<b>Pub KEY :</b>
<pre>$slowdns_key</pre>
<b>NameServer (NS) :</b> $slowdns_ns
<b>━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━</b>
<b>Compte créé avec succès</b>"
  send_message "$chat_id" "$msg"
}

send_user_test_creation_summary() {
  local chat_id=$1 domain=$2 host_ip=$3 username=$4 password=$5 limite=$6 expire_date=$7 slowdns_key=$8 slowdns_ns=$9
  local msg="<b>+==================================================+</b>
<b>*NOUVEAU UTILISATEUR TEST CRÉÉ*</b>
<b>──────────────────────────────────────────────────</b>
<b>DOMAIN        :</b> $domain
<b>Adresse IP    :</b> $host_ip
<b>Utilisateur   :</b> $username
<b>Mot de passe  :</b> $password
<b>Limite        :</b> $limite
<b>Date d'expire :</b> $expire_date
<b>──────────────────────────────────────────────────</b>
En APPS comme HTTP Injector, Netmod, SSC, etc.
🙍 HTTP-Direct  : <code>$host_ip:90@$username:$password</code>
🙍 SSL/TLS(SNI) : <code>$host_ip:443@$username:$password</code>
🙍 Proxy(WS)    : <code>$domain:8080@$username:$password</code>
🙍 SSH UDP      : <code>$host_ip:1-65535@$username:$password</code>
🙍 Hysteria (UDP): <code>$domain:22000@$username:$password</code>
<b>───────────── CONFIG SLOWDNS 5300 ───────────────</b>
<b>Pub Key :</b>
<pre>$slowdns_key</pre>
<b>NameServer (NS) :</b> $slowdns_ns
<b>──────────────────────────────────────────────────</b>
<b>Le compte sera supprimé automatiquement après $limite minutes.</b>
<b>Compte créé avec succès</b>"
  send_message "$chat_id" "$msg"
}

send_connected_devices() {
  local chat_id=$1
  local output=$(bash <<'EOF'
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"
USER_FILE="/etc/kighmu/users.list"
AUTH_LOG="/var/log/auth.log"
if [ ! -f "$USER_FILE" ]; then
    echo -e "${RED}Fichier utilisateur introuvable.${RESET}"
    exit 1
fi
declare -A user_counts
while read -r pid user cmd; do
  if [[ "$cmd" == *sshd* && "$user" != "root" ]]; then
    ((user_counts[$user]++))
  fi
done < <(ps -eo pid,user,comm)
if [[ -f $AUTH_LOG ]]; then
  drop_pids=$(ps aux | grep '[d]ropbear' | awk '{print $2}')
  for pid in $drop_pids; do
    user=$(grep -a "sshd.*$pid" $AUTH_LOG | tail -1 | awk '{print $10}')
    if [[ -n "$user" ]]; then
      ((user_counts[$user]++))
    fi
  done
fi
if [[ -f /etc/openvpn/openvpn-status.log ]]; then
  while read -r line; do
    user=$(echo "$line" | cut -d',' -f2)
    ((user_counts[$user]++))
  done < <(grep CLIENT_LIST /etc/openvpn/openvpn-status.log)
fi
printf "${BOLD}%-20s %-15s\n${RESET}" "UTILISATEUR" "CONNECTÉS"
echo -e "${CYAN}-----------------------------------------${RESET}"
for username in "${!user_counts[@]}"; do
  printf "%-20s %-15d\n" "$username" "${user_counts[$username]}"
done
EOF
)
  send_message "$chat_id" "<pre>$output</pre>"
}

create_user() {
  local chat_id=$1 username=$2 password=$3 limite=$4 days=$5
  bash "$KIGHMU_DIR/menu1.sh" "$username" "$password" "$limite" "$days"
  if [ $? -eq 0 ]; then
    local host_ip=$(curl -s https://api.ipify.org)
    local expire_date=$(date -d "+$days days" '+%Y-%m-%d')
    local slowdns_key=$(sed ':a;N;$!ba;s/\n/\\n/g' /etc/slowdns/server.pub 2>/dev/null || echo "N/A")
    local slowdns_ns=$(cat /etc/slowdns/ns.conf 2>/dev/null || echo "N/A")
    send_user_creation_summary "$chat_id" "$DOMAIN" "$host_ip" "$username" "$password" "$limite" "$expire_date" "$slowdns_key" "$slowdns_ns"
  else
    send_message "$chat_id" "<b>Erreur lors de la création utilisateur $username.</b>"
  fi
}

create_user_test() {
  local chat_id=$1 username=$2 password=$3 limite=$4 minutes=$5
  bash "$KIGHMU_DIR/menu2.sh" "$username" "$password" "$limite" "$minutes"
  if [ $? -eq 0 ]; then
    local host_ip=$(curl -s https://api.ipify.org)
    local expire_date=$(date -d "+$minutes minutes" '+%Y-%m-%d %H:%M:%S')
    local slowdns_key=$(sed ':a;N;$!ba;s/\n/\\n/g' /etc/slowdns/server.pub 2>/dev/null || echo "N/A")
    local slowdns_ns=$(cat /etc/slowdns/ns.conf 2>/dev/null || echo "N/A")
    send_user_test_creation_summary "$chat_id" "$DOMAIN" "$host_ip" "$username" "$password" "$limite" "$expire_date" "$slowdns_key" "$slowdns_ns"
  else
    send_message "$chat_id" "<b>Erreur lors de création utilisateur test.</b>"
  fi
}

edit_user() {
  local chat_id=$1 username=$2 new_password=$3 new_days=$4
  local USER_FILE="/etc/kighmu/users.list"
  user_line=$(grep "^$username|" "$USER_FILE")
  if [ -z "$user_line" ]; then
    send_message "$chat_id" "<b>Erreur :</b> Utilisateur $username introuvable."
    return
  fi
  IFS='|' read -r user pass limite expire_date hostip domain slowdns_ns <<< "$user_line"
  if [[ -n "$new_days" && "$new_days" =~ ^[0-9]+$ ]]; then
    if [ "$new_days" -eq 0 ]; then
      new_expire="none"
    else
      new_expire=$(date -d "+$new_days days" +%Y-%m-%d)
    fi
    limite=$new_days
    expire_date=$new_expire
  fi
  if [[ -n "$new_password" && "$new_password" != "skip" ]]; then
    pass=$new_password
    echo -e "$new_password\n$new_password" | sudo passwd "$username" >/dev/null 2>&1
  fi
  new_line="${user}|${pass}|${limite}|${expire_date}|${hostip}|${domain}|${slowdns_ns}"
  sed -i "s/^$user|.*/$new_line/" "$USER_FILE"
  send_message "$chat_id" "<b>Utilisateur $username modifié avec succès ✅</b>"
}

delete_user() {
  local chat_id=$1 username=$2
  local USER_FILE="/etc/kighmu/users.list"
  if ! grep -q "^$username|" "$USER_FILE"; then
    send_message "$chat_id" "<b>❌ Utilisateur '$username' introuvable dans la liste.</b>"
    return 1
  fi
  if id "$username" &>/dev/null; then
    if sudo userdel -r "$username" &>/dev/null; then
      send_message "$chat_id" "<b>✅ Utilisateur système '$username' supprimé avec succès.</b>"
    else
      send_message "$chat_id" "<b>❌ Erreur lors de la suppression de l'utilisateur système '$username'.</b>"
      return 1
    fi
  else
    send_message "$chat_id" "<b>⚠️ Utilisateur système '$username' introuvable ou déjà supprimé.</b>"
  fi
  if grep -v "^$username|" "$USER_FILE" > "${USER_FILE}.tmp" && sudo mv "${USER_FILE}.tmp" "$USER_FILE"; then
    send_message "$chat_id" "<b>✅ Utilisateur '$username' supprimé de la liste utilisateurs.</b>"
  else
    send_message "$chat_id" "<b>❌ Erreur lors de la mise à jour de la liste des utilisateurs.</b>"
    return 1
  fi
  return 0
}

start_bot() {
  install_shellbot
  check_sudo
  source /etc/kighmu/ShellBot.sh
  if [ -f ~/.kighmu_info ]; then
    source ~/.kighmu_info
  else
    echo "⚠️ ~/.kighmu_info introuvable."
  fi
  ShellBot.init --token "$API_TOKEN" --monitor --return map --flush
  ShellBot.username
  local offset=0
  while true; do
    ShellBot.getUpdates --limit 100 --offset "$offset" --timeout 0
    for id in "${!message_text[@]}"; do
      handle_command "${message_chat_id[$id]}" "${message_from_username[$id]}" "${message_text[$id]}"
    done
    process_callbacks
    process_forcereply
    if [ "${#update_update_id[@]}" -gt 0 ]; then
      local max=0
      for id in "${!update_update_id[@]}"; do
        if (( update_update_id[id] > max )); then
          max=${update_update_id[id]}
        fi
      done
      offset=$((max + 1))
    fi
  done
}

main_menu() {
  print_header
  echo -e "${BLUE_BG}${WHITE} 1) Démarrer le bot                            ${RESET}"
  echo -e "${BLUE_BG}${WHITE} 2) Entrer / modifier API_TOKEN et ADMIN_ID  ${RESET}"
  echo -e "${BLUE_BG}${WHITE} 3) Quitter                                  ${RESET}"
  echo -e "${BLUE_BG}${WHITE}==================================================${RESET}"
  echo -n "Choisissez une option [1-3] : "
  read -r choice
  case "$choice" in
    1)
      if [ -z "$API_TOKEN" ] || [ -z "$ADMIN_ID" ]; then
        echo "⚠️ Veuillez saisir d'abord le API_TOKEN et l'ADMIN_ID."
        ask_credentials
      fi
      start_bot
      ;;
    2)
      ask_credentials
      main_menu
      ;;
    3)
      echo "Au revoir!"
      exit 0
      ;;
    *)
      echo "Choix invalide."
      main_menu
      ;;
  esac
}

main_menu
