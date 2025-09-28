#!/bin/bash
# KIGHMU Telegram VPS Bot Manager complet avec suppression utilisateur

install_shellbot() {
  if [[ ! -f /etc/kighmu/ShellBot.sh ]]; then
    sudo mkdir -p /etc/kighmu
    # Téléchargement depuis ton dépôt GitHub
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

install_shellbot
check_sudo
source /etc/kighmu/ShellBot.sh

API_TOKEN=$1
ADMIN_ID=$2

if [[ -z "$API_TOKEN" || -z "$ADMIN_ID" ]]; then
  echo "Usage: $0 <API_TOKEN> <ADMIN_TELEGRAM_ID>"
  exit 1
fi

# Charger variables globales install Kighmu
if [[ -f ~/.kighmu_info ]]; then
  source ~/.kighmu_info
else
  echo "⚠️ ~/.kighmu_info introuvable, variables globales manquantes."
fi

KIGHMU_DIR="$HOME/Kighmu"

ShellBot.init --token "$API_TOKEN" --monitor --return map --flush
ShellBot.username

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
  local output

  output=$(bash << 'EOF'
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
  if [[ $? -eq 0 ]]; then
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
  if [[ $? -eq 0 ]]; then
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

  IFS="|" read -r user pass limite expire_date hostip domain slowdns_ns <<< "$user_line"

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

# Nouvelle fonction pour supprimer utilisateur directement
delete_user() {
  local chat_id=$1
  local username=$2
  local USER_FILE="/etc/kighmu/users.list"

  # Vérifier que l'utilisateur existe dans la liste
  if ! grep -q "^$username|" "$USER_FILE"; then
    send_message "$chat_id" "<b>❌ Utilisateur '$username' introuvable dans la liste.</b>"
    return 1
  fi

  # Supprimer utilisateur système
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

  # Supprimer la ligne de la liste
  if grep -v "^$username|" "$USER_FILE" > "${USER_FILE}.tmp" && sudo mv "${USER_FILE}.tmp" "$USER_FILE"; then
    send_message "$chat_id" "<b>✅ Utilisateur '$username' supprimé de la liste utilisateurs.</b>"
  else
    send_message "$chat_id" "<b>❌ Erreur lors de la mise à jour de la liste des utilisateurs.</b>"
    return 1
  fi

  return 0
}

handle_command() {
  local chat_id=$1 user=$2 msg=$3
  if [[ "$msg" == "/start" || "$msg" == "/menu" ]]; then
    local keyboard=$(ShellBot.InlineKeyboard \
      --button '👤 Création Utilisateur' create_user_callback \
      --button '🧪 Création Utilisateur Test' create_user_test_callback \
      --button '📶 Appareils Connectés' connected_devices_callback \
      --button '✏️ Modifier Utilisateur' edit_user_callback \
      --button '❌ Supprimer Utilisateur' delete_user_callback \
      --button '🏢 Infos VPS' info_vps_callback)
    send_message "$chat_id" "<b>KIGHMU BOT</b> - Menu Principal"
    ShellBot.sendMessage --chat_id "$chat_id" --text "Choisissez une option :" --reply_markup "$keyboard" --parse_mode html
  else
    send_message "$chat_id" "<b>Commande inconnue. Utilisez /menu.</b>"
  fi
}

process_callbacks() {
  for id in "${!callback_query_data[@]}"; do
    local data=${callback_query_data[$id]}
    local chat_id=${callback_query_message_chat_id[$id]}

    case "$data" in
      create_user_callback)
        ShellBot.answerCallbackQuery --callback_query_id "${callback_query_id[$id]}" --text "Création utilisateur sélectionnée"
        ShellBot.sendMessage --chat_id "$chat_id" --text "Envoyez: username password limite days" --reply_markup "$(ShellBot.ForceReply)"
        ;;
      create_user_test_callback)
        ShellBot.answerCallbackQuery --callback_query_id "${callback_query_id[$id]}" --text "Création utilisateur test sélectionnée"
        ShellBot.sendMessage --chat_id "$chat_id" --text "Envoyez: username password limite minutes" --reply_markup "$(ShellBot.ForceReply)"
        ;;
      connected_devices_callback)
        ShellBot.answerCallbackQuery --callback_query_id "${callback_query_id[$id]}" --text "Appareils connectés"
        send_connected_devices "$chat_id"
        ;;
      edit_user_callback)
        ShellBot.answerCallbackQuery --callback_query_id "${callback_query_id[$id]}" --text "Modifier utilisateur"
        ShellBot.sendMessage --chat_id "$chat_id" --text "Envoyez: username new_password new_days" --reply_markup "$(ShellBot.ForceReply)"
        ;;
      delete_user_callback)
        ShellBot.answerCallbackQuery --callback_query_id "${callback_query_id[$id]}" --text "Suppression utilisateur sélectionnée"
        ShellBot.sendMessage --chat_id "$chat_id" --text "Envoyez le nom d’utilisateur à supprimer :" --reply_markup "$(ShellBot.ForceReply)"
        ;;
      info_vps_callback)
        ShellBot.answerCallbackQuery --callback_query_id "${callback_query_id[$id]}" --text "Infos VPS"
        local info="Uptime: $(uptime -p)\nRAM libre: $(free -h | awk '/^Mem:/ {print $4}')\nCPU load: $(top -bn1 | grep 'Cpu(s)' | awk '{print $2 + $4}')%"
        send_message "$chat_id" "<b>Infos VPS :</b>\n$info"
        ;;
      *)
        ShellBot.answerCallbackQuery --callback_query_id "${callback_query_id[$id]}" --text "Option inconnue"
        ;;
    esac
  done
}

process_forcereply() {
  for id in "${!message_reply_to_message_text[@]}"; do
    local replied_text=${message_reply_to_message_text[$id]}
    local chat_id=${message_chat_id[$id]}
    local text=${message_text[$id]}

    if [[ "$replied_text" =~ "Envoyez: username password limite days" ]]; then
      IFS=' ' read -r username password limite days <<< "$text"
      create_user "$chat_id" "$username" "$password" "$limite" "$days"
    elif [[ "$replied_text" =~ "Envoyez: username password limite minutes" ]]; then
      IFS=' ' read -r username password limite minutes <<< "$text"
      create_user_test "$chat_id" "$username" "$password" "$limite" "$minutes"
    elif [[ "$replied_text" =~ "Envoyez: username new_password new_days" ]]; then
      IFS=' ' read -r username new_password new_days <<< "$text"
      edit_user "$chat_id" "$username" "$new_password" "$new_days"
    elif [[ "$replied_text" =~ "Envoyez le nom d’utilisateur à supprimer" ]]; then
      local username=$text
      delete_user "$chat_id" "$username"
    fi
  done
}

while true; do
  ShellBot.getUpdates --limit 100 --offset $(ShellBot.Offset) --timeout 0

  for id in "${!message_text[@]}"; do
    handle_command "${message_chat_id[$id]}" "${message_from_username[$id]}" "${message_text[$id]}"
  done

  process_callbacks
  process_forcereply
done
