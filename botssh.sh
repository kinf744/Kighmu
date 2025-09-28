#!/bin/bash
# DarkSSH Enhanced Telegram Bot Manager with KIGHMU BOT Control Panel
# Usage: ./bot.sh <API_TOKEN> <ADMIN_TELEGRAM_ID>

install_shellbot() {
  if [[ ! -f /etc/DARKssh/ShellBot.sh ]]; then
    echo "ShellBot.sh not found, installing..."
    sudo mkdir -p /etc/DARKssh
    sudo wget -qO /etc/DARKssh/ShellBot.sh https://raw.githubusercontent.com/shellscriptx/shellbot/master/ShellBot.sh
    sudo chmod +x /etc/DARKssh/ShellBot.sh
    echo "ShellBot.sh installed successfully."
  fi
}

check_sudo() {
  if ! sudo -v >/dev/null 2>&1; then
    echo "This script requires sudo privileges."
    echo "Please run 'sudo -v' and then rerun this script."
    exit 1
  fi
}

install_shellbot
check_sudo
source /etc/DARKssh/ShellBot.sh

API_TOKEN=$1
ADMIN_ID=$2

ACTIVE_USERS="/etc/bot/lista_ativos"
SUSPENDED_USERS="/etc/bot/lista_suspensos"
USER_DB="/root/usuarios.db"
OPENVPN_EASYRSA="/etc/openvpn/easy-rsa"

if [[ -z "$API_TOKEN" || -z "$ADMIN_ID" ]]; then
  echo "Usage: $0 <API_TOKEN> <ADMIN_TELEGRAM_ID>"
  exit 1
fi

ShellBot.init --token "$API_TOKEN" --monitor --return map --flush
ShellBot.username

send_message() {
  local chat_id=$1
  local message=$2
  ShellBot.sendMessage --chat_id $chat_id --text "$message" --parse_mode html
}

check_access() {
  local user=$1
  if grep -qw "$user" "$SUSPENDED_USERS"; then return 1
  elif grep -qw "$user" "$ACTIVE_USERS"; then return 0
  else return 2
  fi
}

show_start_panel() {
  local chat_id=$1
  local title="❇️ <b>KIGHMU BOT</b> ❇️"
  local text="Bienvenue dans le panneau de contrôle. Cliquez sur ⏯️ Débuter pour lancer le bot."

  local keyboard=$(ShellBot.InlineKeyboard --button '⏯️ Débuter' start_deploy_callback)

  ShellBot.sendMessage --chat_id $chat_id --text "$title\n\n$text" --parse_mode html --reply_markup "$keyboard"
}

show_main_panel() {
  local chat_id=$1
  local title="❇️ <b>KIGHMU BOT</b> - Menu Principal ❇️"
  local text="Choisissez une option :"

  local keyboard=$(ShellBot.InlineKeyboard \
    --button '📂 Créer Utilisateur' create_user_callback \
    --button '🗑 Supprimer Utilisateur' delete_user_callback \
    --button '👥 Utilisateurs en ligne' online_users_callback \
    --button '🆘 Aide' help_callback \
  )

  ShellBot.sendMessage --chat_id $chat_id --text "$title\n\n$text" --parse_mode html --reply_markup "$keyboard"
}

create_user() {
  local username=$1
  local password=$2
  local expire_date=$3
  local quota=$4

  if id "$username" &>/dev/null; then
    send_message $CHAT_ID "<b>❌ L'utilisateur $username existe déjà !</b>"
    return
  fi

  local expire_formatted=$(date -d "$expire_date" +%Y-%m-%d)
  sudo useradd -M -N -s /bin/false -e "$expire_formatted" "$username"
  echo -e "$password\n$password" | sudo passwd "$username" >/dev/null 2>&1
  echo "$username $expire_formatted $quota" >> $USER_DB

  cd $OPENVPN_EASYRSA || return
  ./easyrsa build-client-full "$username" nopass >/dev/null 2>&1

  send_message $CHAT_ID "<b>✅ Utilisateur $username créé avec quota $quota et expiration $expire_formatted.</b>"
}

delete_user() {
  local username=$1
  if id "$username" &>/dev/null; then
    sudo pkill -u "$username" >/dev/null 2>&1
    sudo userdel --force "$username"
    sed -i "/^$username /d" $USER_DB
    send_message $CHAT_ID "<b>🗑 Utilisateur $username supprimé.</b>"
  else
    send_message $CHAT_ID "<b>❌ L'utilisateur $username n'existe pas !</b>"
  fi
}

list_online_users() {
  local online_users=$(who | awk '{print $1}' | sort | uniq)
  send_message $CHAT_ID "<b>👥 Utilisateurs en ligne :</b>\n$online_users"
}

show_help() {
  send_message $CHAT_ID "⚙️ <b>Commandes du bot :</b>\n\
/menu - Afficher le menu\n\
Créer Utilisateur - Créer un utilisateur SSH\n\
Supprimer Utilisateur - Supprimer un utilisateur SSH\n\
Utilisateurs en ligne - Liste des utilisateurs connectés\n\
Aide - Affiche ce message"
}

handle_command() {
  local chat_id=$1
  local user=$2
  local msg=$3
  CHAT_ID=$chat_id

  # Première invocation /start affiche le panneau d'accueil
  if [[ "$msg" == "/start" ]]; then
    show_start_panel "$chat_id"
    return
  fi

  # Commandes classiques
  if [[ "$msg" == "menu" || "$msg" == "/menu" ]]; then
    show_main_panel "$chat_id"
  else
    send_message "$chat_id" "<b>Commande inconnue. Utilisez /menu.</b>"
  fi
}

while :; do
  ShellBot.getUpdates --limit 100 --offset $(ShellBot.Offset) --timeout 0

  for id in "${!message_text[@]}"; do
    handle_command "${message_chat_id[$id]}" "${message_from_username[$id]}" "${message_text[$id]}"
  done

  for id in "${!callback_query_data[@]}"; do
    case "${callback_query_data[$id]}" in
      start_deploy_callback)
        ShellBot.answerCallbackQuery --callback_query_id "${callback_query_id[$id]}" --text "Démarrage du bot..."
        show_main_panel "${callback_query_message_chat_id[$id]}"
        ;;
      create_user_callback)
        ShellBot.answerCallbackQuery --callback_query_id "${callback_query_id[$id]}" --text "Création d'utilisateur sélectionnée"
        ShellBot.sendMessage --chat_id "${callback_query_message_chat_id[$id]}" --text "Envoyez les détails au format : username password yyyy-mm-dd quota" --reply_markup "$(ShellBot.ForceReply)"
        ;;
      delete_user_callback)
        ShellBot.answerCallbackQuery --callback_query_id "${callback_query_id[$id]}" --text "Suppression d'utilisateur sélectionnée"
        ShellBot.sendMessage --chat_id "${callback_query_message_chat_id[$id]}" --text "Envoyez le nom d'utilisateur à supprimer" --reply_markup "$(ShellBot.ForceReply)"
        ;;
      online_users_callback)
        ShellBot.answerCallbackQuery --callback_query_id "${callback_query_id[$id]}" --text "Utilisateurs en ligne"
        list_online_users "${callback_query_message_chat_id[$id]}"
        ;;
      help_callback)
        ShellBot.answerCallbackQuery --callback_query_id "${callback_query_id[$id]}" --text "Aide sélectionnée"
        show_help "${callback_query_message_chat_id[$id]}"
        ;;
      *)
        ShellBot.answerCallbackQuery --callback_query_id "${callback_query_id[$id]}" --text "Option inconnue"
        ;;
    esac
  done

  for id in "${!message_reply_to_message_text[@]}"; do
    local reply_text="${message_reply_to_message_text[$id]}"

    if [[ "$reply_text" =~ "Envoyez les détails au format" ]]; then
      IFS=' ' read -r u p e q <<< "${message_text[$id]}"
      CHAT_ID=${message_chat_id[$id]}
      create_user "$u" "$p" "$e" "$q"
    elif [[ "$reply_text" =~ "Envoyez le nom d'utilisateur" ]]; then
      CHAT_ID=${message_chat_id[$id]}
      delete_user "${message_text[$id]}"
    fi
  done

done

