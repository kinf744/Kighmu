#!/bin/bash

CONFIG_FILE="/etc/xray/config.json"
USERS_FILE="/etc/xray/users.json"
DOMAIN=""

# Couleurs
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

print_header() {
  local width=50
  local text="🚀 Xray CONFIG INSTALLER 🚀"
  local border="+--------------------------------------------------+"

  echo -e "${CYAN}$border${RESET}"
  local padding=$(( (width - ${#text}) / 2 ))
  printf "${CYAN}|%*s${BOLD}${MAGENTA}%s${RESET}${CYAN}%*s|\n${RESET}" $padding "" "$text" $padding ""
  echo -e "${CYAN}$border${RESET}"
}

show_menu() {
  echo -e "${CYAN}+--------------------------------------------------+${RESET}"
  echo -e "${BOLD}${YELLOW}|                  MENU Xray                        |${RESET}"
  echo -e "${CYAN}+--------------------------------------------------+${RESET}"
  echo -e "${GREEN}[01]${RESET} Installer le Xray"
  echo -e "${GREEN}[02]${RESET} VMESS"
  echo -e "${GREEN}[03]${RESET} VLESS"
  echo -e "${GREEN}[04]${RESET} TROJAN"
  echo -e "${GREEN}[05]${RESET} Supprimer un utilisateur Xray"
  echo -e "${RED}[06]${RESET} Désinstaller complètement Xray et Trojan-Go"
  echo -e "${RED}[07]${RESET} Quitter"
  echo -ne "${BOLD}${YELLOW}Votre choix [1-7] : ${RESET}"
  read -r choice
}

load_user_data() {
  if [[ -f "$USERS_FILE" ]]; then
    VMESS_TLS=$(jq -r '.vmess_tls' "$USERS_FILE")
    VMESS_NTLS=$(jq -r '.vmess_ntls' "$USERS_FILE")
    VLESS_TLS=$(jq -r '.vless_tls' "$USERS_FILE")
    VLESS_NTLS=$(jq -r '.vless_ntls' "$USERS_FILE")
    TROJAN_PASS=$(jq -r '.trojan_pass' "$USERS_FILE")
    TROJAN_NTLS_PASS=$(jq -r '.trojan_ntls_pass' "$USERS_FILE")
  else
    echo -e "${RED}Fichier $USERS_FILE introuvable.${RESET}"
  fi
}

count_xray_expired() {
  local today
  today=$(date +%Y-%m-%d)
  if [[ ! -f /etc/xray/users_expiry.list ]]; then
    echo 0
    return
  fi
  awk -F'|' -v today="$today" '$2 < today {count++} END {print count+0}' /etc/xray/users_expiry.list
}

afficher_xray_actifs() {
  if ! systemctl is-active --quiet xray; then
    return
  fi

  local ports_tls ports_ntls
  ports_tls=$(jq -r '.inbounds[] | select(.streamSettings.security=="tls") | .port' "$CONFIG_FILE" | sort -u)
  ports_ntls=$(jq -r '.inbounds[] | select(.streamSettings.security=="none") | .port' "$CONFIG_FILE" | sort -u)

  echo "+--------------------------------------------------+"
  echo "|            🚀 Xray CONFIG INSTALLER 🚀            |"
  echo "+--------------------------------------------------+"
  echo "Tunnels Xray actifs:"
  if [[ -n "$ports_tls" ]]; then
    echo "  - Port ${GREEN}$(echo "$ports_tls" | head -n1)${RESET} (TLS)"
  fi
  if [[ -n "$ports_ntls" ]]; then
    echo "  - Port ${YELLOW}$(echo "$ports_ntls" | head -n1)${RESET} (Non-TLS)"
  fi
  echo -n "  - Protocoles : "
  jq -r '.inbounds[].protocol' "$CONFIG_FILE" | sort -u | paste -sd "   • " - | awk '{print "• " $0 "."}'
  echo "+--------------------------------------------------+"
}

create_config() {
  local proto=$1
  local name=$2
  local days=$3

  if [[ -z "$DOMAIN" ]]; then
    echo -e "${RED}⚠️ Le nom de domaine n'est pas défini. Veuillez installer Xray d'abord.${RESET}"
    return
  fi

  local new_uuid
  local link_tls=""
  local link_ntls=""
  local path_ws=""
  local port_tls=8443
  local port_ntls=80

  case "$proto" in
    vmess)
      path_ws="/vmess"
      new_uuid=$(cat /proc/sys/kernel/random/uuid)
      jq --arg id "$new_uuid" --arg proto "vmess" '
        (.inbounds[] | select(.protocol==$proto and .streamSettings.security=="tls") | .settings.clients) += [{"id": $id, "alterId": 0}]
      ' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
      jq --arg id "$new_uuid" '.vmess_tls = $id' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
      link_tls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_tls\",\"id\":\"$new_uuid\",\"aid\":0,\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"$path_ws\",\"tls\":\"tls\"}" | base64 -w0)"
      link_ntls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_ntls\",\"id\":\"$new_uuid\",\"aid\":0,\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"$path_ws\",\"tls\":\"\"}" | base64 -w0)"
      ;;
    vless)
      path_ws="/vless"
      new_uuid=$(cat /proc/sys/kernel/random/uuid)
      jq --arg id "$new_uuid" --arg proto "vless" '
        (.inbounds[] | select(.protocol==$proto and .streamSettings.security=="tls") | .settings.clients) += [{"id": $id}]
      ' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
      jq --arg id "$new_uuid" '.vless_tls = $id' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
      link_tls="vless://$new_uuid@$DOMAIN:$port_tls?path=$path_ws&security=tls&encryption=none&type=ws#$name"
      link_ntls="vless://$new_uuid@$DOMAIN:$port_ntls?path=$path_ws&encryption=none&type=ws#$name"
      ;;
    trojan)
      local uuid_tls=$(cat /proc/sys/kernel/random/uuid)
      local uuid_ntls=$(cat /proc/sys/kernel/random/uuid)

      jq --arg idtls "$uuid_tls" '
        (.inbounds[] | select(.protocol=="trojan" and .streamSettings.security=="tls") | .settings.clients) += [{"password": $idtls}]
      ' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

      jq --arg idntls "$uuid_ntls" '
        (.inbounds[] | select(.protocol=="trojan" and .streamSettings.security=="none") | .settings.clients) += [{"password": $idntls}]
      ' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

      jq --arg idtls "$uuid_tls" --arg idntls "$uuid_ntls" \
        '.trojan_pass = $idtls | .trojan_ntls_pass = $idntls' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"

      link_tls="trojan://${uuid_tls}@${DOMAIN}:8443?security=tls&type=ws&path=/trojanws#${name}"
      link_ntls="trojan://${uuid_ntls}@${DOMAIN}:80?type=ws&path=/trojanws#${name}"
      ;;
    *)
      echo -e "${RED}Protocole inconnu.${RESET}"
      return 1
      ;;
  esac

  local exp_date_iso
  exp_date_iso=$(date -d "+$days days" +"%Y-%m-%d")
  touch /etc/xray/users_expiry.list
  chmod 600 /etc/xray/users_expiry.list
  echo "$new_uuid|$exp_date_iso" >> /etc/xray/users_expiry.list

  local expiry_date
  expiry_date=$(date -d "+$days days" +"%d/%m/%Y")

  echo
  echo "========================="
  echo -e "🧩 ${proto^^}"
  echo "========================="
  echo -e "📄 Configuration $proto générée pour l'utilisateur : $name"
  echo "--------------------------------------------------"
  echo -e "➤ UUID / Mot de passe :"
  if [[ "$proto" == "trojan" ]]; then
    echo -e "    Mot de passe TLS : $uuid_tls"
    echo -e "    Mot de passe Non-TLS : $uuid_ntls"
  else
    echo -e "    UUID : $new_uuid"
  fi
  echo -e "➤ Durée de validité : $days jours (expire le $expiry_date)"
  echo
  echo -e "●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●"
  echo -e "┃ TLS  :"
  echo -e "┃ $link_tls"
  echo -e "┃"
  echo -e "┃ Non-TLS :"
  echo -e "┃ $link_ntls"
  echo -e "●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●"
  echo

  systemctl restart xray
}

delete_user() {
  local proto=$1
  local id=$2
  local tmp_config="/tmp/config.tmp.json"
  local tmp_users="/tmp/users.tmp.json"
  local tmp_expiry="/tmp/expiry.tmp.list"

  if [[ -z "$proto" || -z "$id" ]]; then
    echo -e "${RED}Erreur : protocole et identifiant requis.${RESET}"
    return 1
  fi

  case "$proto" in
    vmess|vless)
      jq --arg id "$id" --arg proto "$proto" '
      (.inbounds[] | select(.protocol == $proto) | .settings.clients) |= map(select(.id != $id))
      ' "$CONFIG_FILE" > "$tmp_config" && mv "$tmp_config" "$CONFIG_FILE"
      ;;
    trojan)
      jq --arg id "$id" '
      (.inbounds[] | select(.protocol == "trojan") | .settings.clients) |= map(select(.password != $id))
      ' "$CONFIG_FILE" > "$tmp_config" && mv "$tmp_config" "$CONFIG_FILE"
      ;;
    *)
      echo -e "${RED}Protocole inconnu.${RESET}"
      return 1
      ;;
  esac

  case "$proto" in
    vmess)
      jq --arg id "$id" '
      if .vmess_tls == $id then .vmess_tls = "" else . end |
      if .vmess_ntls == $id then .vmess_ntls = "" else . end
      ' "$USERS_FILE" > "$tmp_users" && mv "$tmp_users" "$USERS_FILE"
      ;;
    vless)
      jq --arg id "$id" '
      if .vless_tls == $id then .vless_tls = "" else . end |
      if .vless_ntls == $id then .vless_ntls = "" else . end
      ' "$USERS_FILE" > "$tmp_users" && mv "$tmp_users" "$USERS_FILE"
      ;;
    trojan)
      jq --arg id "$id" '
      if .trojan_pass == $id then .trojan_pass = "" else . end |
      if .trojan_ntls_pass == $id then .trojan_ntls_pass = "" else . end
      ' "$USERS_FILE" > "$tmp_users" && mv "$tmp_users" "$USERS_FILE"
      ;;
  esac

  if [[ -f /etc/xray/users_expiry.list ]]; then
    grep -v "^$id|" /etc/xray/users_expiry.list > "$tmp_expiry" && mv "$tmp_expiry" /etc/xray/users_expiry.list
  fi

  systemctl restart xray
  echo -e "${GREEN}Utilisateur supprimé : protocole=$proto, ID=$id${RESET}"
}

# Supprimer un utilisateur via numéro affiché
delete_user_by_number() {
  if [[ ! -f "$USERS_FILE" ]]; then
    echo -e "${RED}Fichier $USERS_FILE introuvable.${RESET}"
    return
  fi

  local users=()
  local count=0

  mapfile -t users < <(jq -r 'to_entries[] | "\(.key):\(.value)"' "$USERS_FILE")

  echo -e "${GREEN}Liste des utilisateurs Xray :${RESET}"
  for u in "${users[@]}"; do
    ((count++))
    proto=$(echo "$u" | cut -d':' -f1)
    id=$(echo "$u" | cut -d':' -f2)
    echo -e "[$count] Protocole : ${YELLOW}$proto${RESET} - ID/Pass : ${CYAN}$id${RESET}"
  done

  if (( count == 0 )); then
    echo -e "${RED}Aucun utilisateur à supprimer.${RESET}"
    return
  fi

  read -rp "Entrez le numéro de l'utilisateur à supprimer (0 pour annuler) : " num

  if [[ ! $num =~ ^[0-9]+$ ]] || (( num < 0 )) || (( num > count )); then
    echo -e "${RED}Numéro invalide.${RESET}"
    return
  fi

  if (( num == 0 )); then
    echo "Suppression annulée."
    return
  fi

  local selected=${users[$((num-1))]}
  local sel_proto=$(echo "$selected" | cut -d':' -f1)
  local sel_id=$(echo "$selected" | cut -d':' -f2)

  echo -e "Suppression de l'utilisateur du protocole ${YELLOW}$sel_proto${RESET} avec ID/Pass ${CYAN}$sel_id${RESET}..."

  delete_user "$sel_proto" "$sel_id"
}

choice=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -f /tmp/.xray_domain ]] && DOMAIN=$(cat /tmp/.xray_domain)
load_user_data

while true; do
  clear
  afficher_xray_actifs
  print_header
  show_menu
  case $choice in
    1)
      bash "$SCRIPT_DIR/xray_installe.sh"
      if [[ -f /tmp/.xray_domain ]]; then
        DOMAIN=$(cat /tmp/.xray_domain)
        echo -e "${GREEN}Nom de domaine $DOMAIN chargé automatiquement.${RESET}"
      else
        DOMAIN=""
        echo -e "${RED}Aucun domaine enregistré. Veuillez installer Xray d’abord.${RESET}"
      fi
      load_user_data
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    2)
      read -rp "Nom de l'utilisateur VMESS : " conf_name
      read -rp "Durée (jours) : " days
      [[ -n "$conf_name" && -n "$days" ]] && create_config "vmess" "$conf_name" "$days"
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    3)
      read -rp "Nom de l'utilisateur VLESS : " conf_name
      read -rp "Durée (jours) : " days
      [[ -n "$conf_name" && -n "$days" ]] && create_config "vless" "$conf_name" "$days"
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    4)
      read -rp "Nom de l'utilisateur TROJAN : " conf_name
      read -rp "Durée (jours) : " days
      [[ -n "$conf_name" && -n "$days" ]] && create_config "trojan" "$conf_name" "$days"
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    5)
      delete_user_by_number
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    6)
      echo -e "${YELLOW}Désinstallation complète de Xray et Trojan-Go en cours...${RESET}"

      systemctl stop xray trojan-go 2>/dev/null || true
      systemctl disable xray trojan-go 2>/dev/null || true

      for port in 80 8443; do
        lsof -i tcp:$port -t | xargs -r kill -9
        lsof -i udp:$port -t | xargs -r kill -9
      done

      rm -rf /etc/xray /var/log/xray /usr/local/bin/xray /etc/systemd/system/xray.service
      rm -rf /etc/trojan-go /var/log/trojan-go /usr/local/bin/trojan-go /etc/systemd/system/trojan-go.service
      rm -f /tmp/.xray_domain /etc/xray/users_expiry.list /etc/xray/users.json /etc/xray/config.json

      systemctl daemon-reload

      echo -e "${GREEN}Désinstallation terminée.${RESET}"
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    7)
      echo -e "${RED}Quitter...${RESET}"
      rm -f /tmp/.xray_domain
      break
      ;;
    *)
      echo -e "${RED}Choix invalide.${RESET}"
      sleep 2
      ;;
  esac
done
