#!/bin/bash
# KIGHMU Telegram VPS Bot - Interface complète avec boutons demandés

install_shellbot() {
  if [[ ! -f /etc/DARKssh/ShellBot.sh ]]; then
    sudo mkdir -p /etc/DARKssh
    sudo wget -qO /etc/DARKssh/ShellBot.sh https://raw.githubusercontent.com/shellscriptx/shellbot/master/ShellBot.sh
    sudo chmod +x /etc/DARKssh/ShellBot.sh
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
source /etc/DARKssh/ShellBot.sh

API_TOKEN=$1
ADMIN_ID=$2

if [[ -z "$API_TOKEN" || -z "$ADMIN_ID" ]]; then
  echo "Usage: $0 <API_TOKEN> <ADMIN_TELEGRAM_ID>"
  exit 1
fi

ShellBot.init --token "$API_TOKEN" --monitor --return map --flush
ShellBot.username

send_message() {
  ShellBot.sendMessage --chat_id "$1" --text "$2" --parse_mode html
}

show_main_menu() {
  local chat_id=$1
  local keyboard=$(ShellBot.InlineKeyboard \
    --button '👤 Création Utilisateur' create_user_callback \
    --button '🧪 Création Utilisateur Test' create_user_test_callback \
    --button '📶 Appareils Connectés' connected_devices_callback \
    --button '✏️ Modifier Utilisateur' modify_user_callback \
    --button '🗑 Supprimer Utilisateur' delete_user_callback \
    --button 'ℹ️ Infos Serveur VPS' info_vps_callback \
  )
  send_message "$chat_id" "<b>KIGHMU BOT - Menu Principal</b>\nChoisissez une option :"
  ShellBot.sendMessage --chat_id "$chat_id" --text "Options :" --reply_markup "$keyboard" --parse_mode html
}

handle_callback() {
  local id=$1
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
      # Ici appeler la fonction listing appareils connectés
      # Exemple simple:
      send_message "$chat_id" "Fonction 'Appareils connectés' en cours de développement."
      ;;
    modify_user_callback)
      ShellBot.answerCallbackQuery --callback_query_id "${callback_query_id[$id]}" --text "Modification utilisateur"
      ShellBot.sendMessage --chat_id "$chat_id" --text "Envoyez: username new_password" --reply_markup "$(ShellBot.ForceReply)"
      ;;
    delete_user_callback)
      ShellBot.answerCallbackQuery --callback_query_id "${callback_query_id[$id]}" --text "Suppression utilisateur"
      ShellBot.sendMessage --chat_id "$chat_id" --text "Envoyez le nom de l'utilisateur à supprimer" --reply_markup "$(ShellBot.ForceReply)"
      ;;
    info_vps_callback)
      ShellBot.answerCallbackQuery --callback_query_id "${callback_query_id[$id]}" --text "Infos VPS"
      # Exemple rapide de stats
      local info="Uptime: $(uptime -p)\nRAM libre: $(free -h | awk '/^Mem:/ { print $4 }')\nCPU load: $(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')%"
      send_message "$chat_id" "<b>Infos VPS :</b>\n$info"
      ;;
    *)
      ShellBot.answerCallbackQuery --callback_query_id "${callback_query_id[$id]}" --text "Option inconnue"
      ;;
  esac
}

process_forcereply() {
  for id in "${!message_reply_to_message_text[@]}"; do
    local replied_text=${message_reply_to_message_text[$id]}
    local chat_id=${message_chat_id[$id]}
    local text=${message_text[$id]}

    if [[ "$replied_text" =~ "Envoyez: username password limite days" ]]; then
      IFS=' ' read -r username password limite days <<< "$text"
      # Appeler votre script créé utilisateur ici avec ces valeurs
      create_user "$chat_id" "$username" "$password" "$limite" "$days"
    elif [[ "$replied_text" =~ "Envoyez: username password limite minutes" ]]; then
      IFS=' ' read -r username password limite minutes <<< "$text"
      # Appeler votre script création test utilisateur
      create_user_test "$chat_id" "$username" "$password" "$limite" "$minutes"
    elif [[ "$replied_text" =~ "Envoyez: username new_password" ]]; then
      IFS=' ' read -r username newpass <<< "$text"
      # Ajoutez fonction changement mot de passe utilisateur ici
      send_message "$chat_id" "<b>Fonction modifier utilisateur pas encore implémentée</b>"
    elif [[ "$replied_text" =~ "Envoyez le nom de l'utilisateur à supprimer" ]]; then
      # Appeler fonction suppression utilisateur
      delete_user "$chat_id" "$text"
    fi
  done
}

create_user() {
  local chat_id=$1
  local username=$2
  local password=$3
  local limite=$4
  local days=$5
  # Appel script menu1.sh pour création
  bash "$HOME/Kighmu/menu1.sh" "$username" "$password" "$limite" "$days"
  local status=$?
  if [[ $status -eq 0 ]]; then
    send_message "$chat_id" "<b>Utilisateur $username créé avec succès</b>"
  else
    send_message "$chat_id" "<b>Erreur création utilisateur</b>"
  fi
}

create_user_test() {
  local chat_id=$1
  local username=$2
  local password=$3
  local limite=$4
  local minutes=$5
  # Appel script menu_test.sh ou équivalent pour test utilisateur
  bash "$HOME/Kighmu/menu_test.sh" "$username" "$password" "$limite" "$minutes"
  local status=$?
  if [[ $status -eq 0 ]]; then
    send_message "$chat_id" "<b>Utilisateur test $username créé avec succès</b>"
  else
    send_message "$chat_id" "<b>Erreur création utilisateur test</b>"
  fi
}

delete_user() {
  local chat_id=$1
  local username=$2
  bash "$HOME/Kighmu/menu4.sh" "$username"
  local status=$?
  if [[ $status -eq 0 ]]; then
    send_message "$chat_id" "<b>Utilisateur $username supprimé avec succès</b>"
  else
    send_message "$chat_id" "<b>Erreur suppression utilisateur</b>"
  fi
}

while true; do
  ShellBot.getUpdates --limit 100 --offset $(ShellBot.Offset) --timeout 0

  for id in "${!message_text[@]}"; do
    handle_command "${message_chat_id[$id]}" "${message_from_username[$id]}" "${message_text[$id]}"
  done

  for id in "${!callback_query_data[@]}"; do
    handle_callback "$id"
  done

  process_forcereply
done
