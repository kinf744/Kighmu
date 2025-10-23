#!/bin/bash

CONFIG_FILE="/etc/xray/config.json"
USERS_FILE="/etc/xray/users.json"
DOMAIN=""

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

print_header() {
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${CYAN}       ${BOLD}${MAGENTA}Xray – Gestion des Tunnels Actifs${RESET}${CYAN}${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

afficher_xray_actifs() {
  if ! systemctl is-active --quiet xray; then
    echo -e "${RED}Service Xray non actif.${RESET}"
    return
  fi
  local ports_tls ports_ntls protos
  ports_tls=$(jq -r '.inbounds[] | select(.streamSettings.security=="tls") | .port' "$CONFIG_FILE" | sort -u | paste -sd ", ")
  ports_ntls=$(jq -r '.inbounds[] | select(.streamSettings.security=="none") | .port' "$CONFIG_FILE" | sort -u | paste -sd ", ")
  protos=$(jq -r '.inbounds[].protocol' "$CONFIG_FILE" | sort -u | paste -sd ", ")
  echo -e "${BOLD}Tunnels actifs :${RESET}"
  [[ -n "$ports_tls" ]] && echo -e " ${GREEN}•${RESET} Port(s) TLS : ${YELLOW}$ports_tls${RESET} – Protocoles [${MAGENTA}$protos${RESET}]"
  [[ -n "$ports_ntls" ]] && echo -e " ${GREEN}•${RESET} Port(s) Non-TLS : ${YELLOW}$ports_ntls${RESET} – Protocoles [${MAGENTA}$protos${RESET}]"
}

show_menu() {
  echo -e "${CYAN}──────────────────────────────────────────────────────────${RESET}"
  echo -e "${BOLD}${YELLOW}[01]${RESET} Installer Xray"
  echo -e "${BOLD}${YELLOW}[02]${RESET} Créer utilisateur VMess"
  echo -e "${BOLD}${YELLOW}[03]${RESET} Créer utilisateur VLESS"
  echo -e "${BOLD}${YELLOW}[04]${RESET} Créer utilisateur Trojan"
  echo -e "${BOLD}${YELLOW}[05]${RESET} Supprimer utilisateur Xray"
  echo -e "${BOLD}${YELLOW}[06]${RESET} Désinstallation complète Xray"
  echo -e "${BOLD}${RED}[00]${RESET} Quitter"
  echo -e "${CYAN}──────────────────────────────────────────────────────────${RESET}"
  echo -ne "${BOLD}${YELLOW}Choix → ${RESET}"
  read -r choice
}

load_user_data() {
  if [[ -f "$USERS_FILE" ]]; then
    VMESS_TLS=$(jq -r '.vmess_tls // empty' "$USERS_FILE")
    VMESS_NTLS=$(jq -r '.vmess_ntls // empty' "$USERS_FILE")
    VLESS_TLS=$(jq -r '.vless_tls // empty' "$USERS_FILE")
    VLESS_NTLS=$(jq -r '.vless_ntls // empty' "$USERS_FILE")
    TROJAN_PASS=$(jq -r '.trojan_pass // empty' "$USERS_FILE")
    TROJAN_NTLS_PASS=$(jq -r '.trojan_ntls_pass // empty' "$USERS_FILE")
  fi
}

# Compte total des utilisateurs multi-protocole
count_users() {
  local total=0
  local keys=("vmess_tls" "vmess_ntls" "vless_tls" "vless_ntls" "trojan_tls" "trojan_ntls")
  for key in "${keys[@]}"; do
    local count
    count=$(jq --arg k "$key" '.[$k] | length // 0' "$USERS_FILE")
    total=$(( total + count ))
  done
  echo "$total"
}

create_config() {
  local proto=$1 name=$2 days=$3
  [[ -z "$DOMAIN" ]] && { echo -e "${RED}⚠️ Domaine non défini, installe Xray d'abord.${RESET}"; return; }
  local new_uuid link_tls link_ntls path_ws port_tls port_ntls
  port_tls=8443
  port_ntls=80

  new_uuid=$(cat /proc/sys/kernel/random/uuid)

  case "$proto" in
    vmess)
      path_ws_tls="/vmess-tls"
      path_ws_ntls="/vmess-ntls"
      if jq -e '.vmess_tls // empty' "$USERS_FILE" > /dev/null; then
        jq --arg id "$new_uuid" '.vmess_tls += [$id]' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
      else
        jq --arg id "$new_uuid" '. + {vmess_tls: [$id]}' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
      fi
      jq --arg id "$new_uuid" --arg proto "vmess" \
        '(.inbounds[] | select(.protocol == $proto and .streamSettings.security == "tls") | .settings.clients) += [{"id": $id,"alterId":0}]' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

      link_tls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_tls\",\"id\":\"$new_uuid\",\"aid\":0,\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"$path_ws_tls\",\"tls\":\"tls\"}" | base64 -w0)"
      link_ntls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_ntls\",\"id\":\"$new_uuid\",\"aid\":0,\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"$path_ws_ntls\",\"tls\":\"\"}" | base64 -w0)"
      ;;
    vless)
      path_ws_tls="/vless-tls"
      path_ws_ntls="/vless-ntls"
      if jq -e '.vless_tls // empty' "$USERS_FILE" > /dev/null; then
        jq --arg id "$new_uuid" '.vless_tls += [$id]' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
      else
        jq --arg id "$new_uuid" '. + {vless_tls: [$id]}' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
      fi
      jq --arg id "$new_uuid" --arg proto "vless" \
        '(.inbounds[] | select(.protocol == $proto and .streamSettings.security == "tls") | .settings.clients) += [{"id": $id}]' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

      link_tls="vless://$new_uuid@$DOMAIN:$port_tls?path=$path_ws_tls&security=tls&encryption=none&type=ws#$name"
      link_ntls="vless://$new_uuid@$DOMAIN:$port_ntls?path=$path_ws_ntls&encryption=none&type=ws#$name"
      ;;
    trojan)
      path_ws_tls="/trojan-tls"
      path_ws_ntls="/trojan-ntls"
      local uuid_tls=$(cat /proc/sys/kernel/random/uuid)
      local uuid_ntls=$(cat /proc/sys/kernel/random/uuid)

      if jq -e '.trojan_tls // empty' "$USERS_FILE" > /dev/null; then
        jq --arg id "$uuid_tls" '.trojan_tls += [$id]' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
      else
        jq --arg id "$uuid_tls" '. + {trojan_tls: [$id]}' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
      fi
      if jq -e '.trojan_ntls // empty' "$USERS_FILE" > /dev/null; then
        jq --arg id "$uuid_ntls" '.trojan_ntls += [$id]' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
      else
        jq --arg id "$uuid_ntls" '. + {trojan_ntls: [$id]}' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
      fi

      jq --arg idtls "$uuid_tls" --arg idntls "$uuid_ntls" \
         '(.inbounds[] | select(.protocol=="trojan" and .streamSettings.security=="tls") | .settings.clients)+=[{"password": $idtls}] |
          (.inbounds[] | select(.protocol=="trojan" and .streamSettings.security=="none") | .settings.clients)+=[{"password": $idntls}]' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

      link_tls="trojan://$uuid_tls@$DOMAIN:$port_tls?security=tls&type=ws&path=$path_ws_tls#$name"
      link_ntls="trojan://$uuid_ntls@$DOMAIN:$port_ntls?type=ws&path=$path_ws_ntls#$name"
      ;;
    *)
      echo -e "${RED}Protocole inconnu.${RESET}"
      return 1
      ;;
  esac

  local exp_date_iso=$(date -d "+$days days" +"%Y-%m-%d")
  local expiry_date=$(date -d "+$days days" +"%d/%m/%Y")
  touch /etc/xray/users_expiry.list && chmod 600 /etc/xray/users_expiry.list
  echo "$new_uuid|$exp_date_iso" >> /etc/xray/users_expiry.list

  local total_users
  total_users=$(count_users)

  echo
  echo "=============================="
  echo -e "🧩 ${proto^^}"
  echo "=============================="
  echo -e "📄 Configuration générée pour : $name"
  echo "--------------------------------------------------"
  echo -e "➤ UUID/Mot de passe TLS :"

  # Affichage TLS par protocole
  echo "  TLS:"
  if [[ -n "$vmess_tls_list" ]]; then
    echo "    VMess TLS :"
    while IFS= read -r id; do [[ -n "$id" ]] && echo "      - $id"; done <<< "$vmess_tls_list"
  else
    echo "      VMess TLS : (aucun)"
  fi

  if [[ -n "$vless_tls_list" ]]; then
    echo "    VLess TLS :"
    while IFS= read -r id; do [[ -n "$id" ]] && echo "      - $id"; done <<< "$vless_tls_list"
  else
    echo "      VLess TLS : (aucun)"
  fi

  if [[ -n "$trojan_tls_list" ]]; then
    echo "    Trojan TLS :"
    while IFS= read -r id; do [[ -n "$id" ]] && echo "      - $id"; done <<< "$trojan_tls_list"
  else
    echo "      Trojan TLS : (aucun)"
  fi

  # NTLS
  echo -e "  NTLS:"
  if [[ -n "$vmess_ntls_list" ]]; then
    echo "    VMess NTLS :"
    while IFS= read -r id; do [[ -n "$id" ]] && echo "      - $id"; done <<< "$vmess_ntls_list"
  else
    echo "    VMess NTLS : (vide)"
  fi

  if [[ -n "$vless_ntls_list" ]]; then
    echo "    VLess NTLS :"
    while IFS= read -r id; do [[ -n "$id" ]] && echo "      - $id"; done <<< "$vless_ntls_list"
  else
    echo "    VLess NTLS : (vide)"
  fi

  if [[ -n "$trojan_ntls_list" ]]; then
    echo "    Trojan NTLS :"
    while IFS= read -r id; do [[ -n "$id" ]] && echo "      - $id"; done <<< "$trojan_ntls_list"
  else
    echo "    Trojan NTLS : (vide)"
  fi

  # Affichage des chemins TLS/NTLS
  echo -e "  Paths TLS/NTLS :"
  echo "    TLS path VMess/VLess/Trojan : $path_ws_tls"
  echo "    NTLS path VMess/VLess/Trojan : $path_ws_ntls"

  echo -e "➤ Validité : $days jours (expire le $expiry_date)"
  echo -e "➤ Nombre total d'utilisateurs : $total_users"
  echo
  echo -e "●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●"
  echo -e "┃ TLS  : $link_tls"
  echo -e ""
  echo -e "┃ Non-TLS : $link_ntls"
  echo -e "●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●"
  echo

  systemctl restart xray
}

delete_user_by_number() {
  if [[ ! -f "$USERS_FILE" ]]; then
    echo -e "${RED}Fichier $USERS_FILE introuvable.${RESET}"
    return
  fi

  # Map protocole -> protocole Xray et TLS/NTLS
  local -A protocol_map=(["vmess_tls"]="vmess" ["vmess_ntls"]="vmess" ["vless_tls"]="vless" ["vless_ntls"]="vless" ["trojan_tls"]="trojan" ["trojan_ntls"]="trojan")
  local -A key_to_stream=(["vmess_tls"]="tls" ["vmess_ntls"]="none" ["vless_tls"]="tls" ["vless_ntls"]="none" ["trojan_tls"]="tls" ["trojan_ntls"]="none")

  # Construire la liste d'utilisateurs au format key:id
  local users=() keys=() count=0
  for key in "${!protocol_map[@]}"; do
    local proto="${protocol_map[$key]}"
    local stream="${key_to_stream[$key]}"
    local uuids
    uuids=$(jq -r --arg k "$key" '.[$k][]?' "$USERS_FILE")
    while IFS= read -r id; do
      [[ -n "$id" ]] && { users+=("$key:$id"); keys+=("$key"); ((count++)); }
    done <<< "$uuids"
  done

  echo -e "${GREEN}Liste des utilisateurs Xray :${RESET}"
  for ((i=0; i<count; i++)); do
    local proto="${users[$i]%%:*}"
    local id="${users[$i]#*:}"
    echo -e "[$((i+1))] Protocole : ${YELLOW}$proto${RESET} - ID/Pass : ${CYAN}$id${RESET}"
  done
  ((count == 0)) && { echo -e "${RED}Aucun utilisateur à supprimer.${RESET}"; return; }

  read -rp "Numéro à supprimer (0 pour annuler) : " num
  [[ ! $num =~ ^[0-9]+$ || num -lt 0 || num -gt $count ]] && { echo -e "${RED}Numéro invalide.${RESET}"; return; }
  ((num == 0)) && { echo "Suppression annulée."; return; }

  local selected_index=$((num - 1))
  local sel_key="${keys[$selected_index]}"
  local sel_id="${users[$selected_index]#*:}"
  local sel_proto="${protocol_map[$sel_key]}"
  local sel_stream="${key_to_stream[$sel_key]}"

  # Suppression du UUID de la liste dans users.json
  jq --arg k "$sel_key" --arg id "$sel_id" \
    '(.[$k]) |= map(select(. != $id))' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"

  # Suppression dans config.json du client ciblé
  if [[ "$sel_proto" == "vmess" || "$sel_proto" == "vless" ]]; then
    jq --arg proto "$sel_proto" --arg stream "$sel_stream" --arg id "$sel_id" \
      '(.inbounds[] | select(.protocol == $proto and .streamSettings.security == $stream) | .settings.clients) |= map(select(.id != $id))' \
      "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
  elif [[ "$sel_proto" == "trojan" ]]; then
    jq --arg stream "$sel_stream" --arg id "$sel_id" \
      '(.inbounds[] | select(.protocol == "trojan" and .streamSettings.security == $stream) | .settings.clients) |= map(select(.password != $id))' \
      "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
  fi

  # Suppression de l’entrée d’expiration
  [[ -f /etc/xray/users_expiry.list ]] && grep -v "^$sel_id|" /etc/xray/users_expiry.list > /tmp/expiry.tmp && mv /tmp/expiry.tmp /etc/xray/users_expiry.list

  systemctl restart xray
  echo -e "${GREEN}Utilisateur supprimé : $sel_key / $sel_proto ($sel_id)${RESET}"
}

choice=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f /tmp/.xray_domain ]] && DOMAIN=$(cat /tmp/.xray_domain)
load_user_data

while true; do
  clear
  print_header
  afficher_xray_actifs
  show_menu
  case $choice in
    1)
      bash "$SCRIPT_DIR/xray_installe.sh"
      [[ -f /tmp/.xray_domain ]] && DOMAIN=$(cat /tmp/.xray_domain)
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
      for port in 80 8443; do lsof -i tcp:$port -t | xargs -r kill -9; lsof -i udp:$port -t | xargs -r kill -9; done
      rm -rf /etc/xray /var/log/xray /usr/local/bin/xray /etc/systemd/system/xray.service
      rm -rf /etc/trojan-go /var/log/trojan-go /usr/local/bin/trojan-go /etc/systemd/system/trojan-go.service
      rm -f /tmp/.xray_domain /etc/xray/users_expiry.list /etc/xray/users.json /etc/xray/config.json
      systemctl daemon-reload
      echo -e "${GREEN}Désinstallation terminée.${RESET}"
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    0)
      echo -e "${RED}Quitter...${RESET}"
      # rm -f /tmp/.xray_domain
      break
      ;;
    *)
      echo -e "${RED}Choix invalide.${RESET}"
      sleep 2
      ;;
  esac
done
