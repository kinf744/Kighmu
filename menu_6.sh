#!/bin/bash

CONFIG_FILE="/etc/xray/config.json"
USERS_FILE="/etc/xray/users.json"
DOMAIN=""

RED="\u001B[31m"
GREEN="\u001B[32m"
YELLOW="\u001B[33m"
MAGENTA="\u001B[35m"
CYAN="\u001B[36m"
BOLD="\u001B[1m"
RESET="\u001B[0m"

print_header() {
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${CYAN}       ${BOLD}${MAGENTA}Xray – Gestion des Tunnels Actifs${RESET}${CYAN}${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

afficher_utilisateurs_xray() {
  if [[ -f "$USERS_FILE" ]]; then
    vmess_tls_count=$(jq '.vmess_tls | length' "$USERS_FILE" 2>/dev/null || echo 0)
    vmess_ntls_count=$(jq '.vmess_ntls | length' "$USERS_FILE" 2>/dev/null || echo 0)
    vless_tls_count=$(jq '.vless_tls | length' "$USERS_FILE" 2>/dev/null || echo 0)
    vless_ntls_count=$(jq '.vless_ntls | length' "$USERS_FILE" 2>/dev/null || echo 0)
    trojan_tls_count=$(jq '.trojan_tls | length' "$USERS_FILE" 2>/dev/null || echo 0)
    trojan_ntls_count=$(jq '.trojan_ntls | length' "$USERS_FILE" 2>/dev/null || echo 0)
    vmess_count=$((vmess_tls_count + vmess_ntls_count))
    vless_count=$((vless_tls_count + vless_ntls_count))
    trojan_count=$((trojan_tls_count + trojan_ntls_count))
    echo -e "${BOLD}Utilisateur Xray :${RESET}"
    echo -e "  • VMess: [${YELLOW}${vmess_count}${RESET}] • VLESS: [${YELLOW}${vless_count}${RESET}] • Trojan: [${YELLOW}${trojan_count}${RESET}]"
  else
    echo -e "${RED}Fichier des utilisateurs introuvable.${RESET}"
  fi
}

afficher_appareils_connectes() {
  if [[ -f "$USERS_FILE" ]]; then
    vmess_tls_count=$(jq '.vmess_tls | length' "$USERS_FILE" 2>/dev/null || echo 0)
    vmess_ntls_count=$(jq '.vmess_ntls | length' "$USERS_FILE" 2>/dev/null || echo 0)
    vless_tls_count=$(jq '.vless_tls | length' "$USERS_FILE" 2>/dev/null || echo 0)
    vless_ntls_count=$(jq '.vless_ntls | length' "$USERS_FILE" 2>/dev/null || echo 0)
    trojan_tls_count=$(jq '.trojan_tls | length' "$USERS_FILE" 2>/dev/null || echo 0)
    trojan_ntls_count=$(jq '.trojan_ntls | length' "$USERS_FILE" 2>/dev/null || echo 0)

    vmess_total=$((vmess_tls_count + vmess_ntls_count))
    vless_total=$((vless_tls_count + vless_ntls_count))
    trojan_total=$((trojan_tls_count + trojan_ntls_count))

    echo -e "${BOLD}Appareils connectés :${RESET}"
    echo -e "  • VMess: [${YELLOW}${vmess_total}${RESET}]"
    echo -e "  • VLess: [${YELLOW}${vless_total}${RESET}]"
    echo -e "  • Trojan: [${YELLOW}${trojan_total}${RESET}]"
  else
    echo -e "${RED}Fichier des utilisateurs introuvable.${RESET}"
  fi
}

print_consommation_xray() {
  VN_INTERFACE="eth0"

  today_bytes=$(vnstat -i "$VN_INTERFACE" --json | jq '.interfaces[0].traffic.day[0].rx + .interfaces[0].traffic.day[0].tx')
  month_bytes=$(vnstat -i "$VN_INTERFACE" --json | jq '.interfaces[0].traffic.month[0].rx + .interfaces[0].traffic.month[0].tx')

  today_gb=$(awk -v b="$today_bytes" 'BEGIN {printf "%.2f", b / 1073741824}')
  month_gb=$(awk -v b="$month_bytes" 'BEGIN {printf "%.2f", b / 1073741824}')

  echo -e "${BOLD}Consommation Xray :${RESET}"
  echo -e "  • Aujourd’hui : [${GREEN}${today_gb} Go${RESET}]"
  echo -e "  • Ce mois : [${GREEN}${month_gb} Go${RESET}]"
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
  [[ -n "$ports_tls" ]] && echo -e " ${GREEN}•${RESET} Port(s) TLS : [${YELLOW}${ports_tls}${RESET}] – Protocoles [${MAGENTA}${protos}${RESET}]"
  [[ -n "$ports_ntls" ]] && echo -e " ${GREEN}•${RESET} Port(s) Non-TLS : [${YELLOW}${ports_ntls}${RESET}] – Protocoles [${MAGENTA}${protos}${RESET}]"
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
  local proto=$1 name=$2 days=$3 limit=$4
  [[ -z "$DOMAIN" ]] && { echo -e "${RED}⚠️ Domaine non défini.${RESET}"; return; }

  local port_tls=8443
  local port_ntls=80
  local path_ws_tls path_ws_ntls
  local link_tls link_ntls
  local uuid_tls uuid_ntls

  case "$proto" in
    vmess)
      path_ws_tls="/vmess-tls"
      path_ws_ntls="/vmess-ntls"
      uuid_tls=$(cat /proc/sys/kernel/random/uuid)
      uuid_ntls=$(cat /proc/sys/kernel/random/uuid)

      # Enregistrer UUID + limit dans users.json
      jq --arg id "$uuid_tls" --argjson lim "$limit" '.vmess_tls += [{"uuid": $id, "limit": $lim}]' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
      jq --arg id "$uuid_ntls" --argjson lim "$limit" '.vmess_ntls += [{"uuid": $id, "limit": $lim}]' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"

      # Mise à jour config.json
      jq --arg id "$uuid_tls" --arg proto "vmess" \
        '(.inbounds[] | select(.protocol == $proto and .streamSettings.security == "tls") | .settings.clients) += [{"id": $id,"alterId":0}]' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
      jq --arg id "$uuid_ntls" --arg proto "vmess" \
        '(.inbounds[] | select(.protocol == $proto and .streamSettings.security == "none") | .settings.clients) += [{"id": $id,"alterId":0}]' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

      # Génération liens
      link_tls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_tls\",\"id\":\"$uuid_tls\",\"aid\":0,\"net\":\"ws\",\"type\":\"none\",\"host\":\"$DOMAIN\",\"path\":\"$path_ws_tls\",\"tls\":\"tls\",\"sni\":\"$DOMAIN\"}" | base64 -w0)"
      link_ntls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_ntls\",\"id\":\"$uuid_ntls\",\"aid\":0,\"net\":\"ws\",\"type\":\"none\",\"host\":\"$DOMAIN\",\"path\":\"$path_ws_ntls\",\"tls\":\"none\",\"sni\":\"$DOMAIN\"}" | base64 -w0)"
      ;;
    vless)
      path_ws_tls="/vless-tls"
      path_ws_ntls="/vless-ntls"
      uuid_tls=$(cat /proc/sys/kernel/random/uuid)
      uuid_ntls=$(cat /proc/sys/kernel/random/uuid)

      jq --arg id "$uuid_tls" --argjson lim "$limit" '.vless_tls += [{"uuid": $id, "limit": $lim}]' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
      jq --arg id "$uuid_ntls" --argjson lim "$limit" '.vless_ntls += [{"uuid": $id, "limit": $lim}]' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"

      jq --arg id "$uuid_tls" --arg proto "vless" \
        '(.inbounds[] | select(.protocol == $proto and .streamSettings.security == "tls") | .settings.clients) += [{"id": $id}]' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
      jq --arg id "$uuid_ntls" --arg proto "vless" \
        '(.inbounds[] | select(.protocol == $proto and .streamSettings.security == "none") | .settings.clients) += [{"id": $id}]' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

      link_tls="vless://$uuid_tls@$DOMAIN:$port_tls?security=tls&type=ws&host=$DOMAIN&path=$path_ws_tls&encryption=none&sni=$DOMAIN#$name"
      link_ntls="vless://$uuid_ntls@$DOMAIN:$port_ntls?security=none&type=ws&host=$DOMAIN&path=$path_ws_ntls&encryption=none#$name"
      ;;
    trojan)
      path_ws_tls="/trojan-tls"
      path_ws_ntls="/trojan-ntls"
      uuid_tls=$(cat /proc/sys/kernel/random/uuid)
      uuid_ntls=$(cat /proc/sys/kernel/random/uuid)

      jq --arg id "$uuid_tls" --argjson lim "$limit" '.trojan_tls += [{"uuid": $id, "limit": $lim}]' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
      jq --arg id "$uuid_ntls" --argjson lim "$limit" '.trojan_ntls += [{"uuid": $id, "limit": $lim}]' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"

      jq --arg idtls "$uuid_tls" --arg idntls "$uuid_ntls" \
         '(.inbounds[] | select(.protocol=="trojan" and .streamSettings.security=="tls") | .settings.clients)+=[{"password": $idtls}] |
          (.inbounds[] | select(.protocol=="trojan" and .streamSettings.security=="none") | .settings.clients)+=[{"password": $idntls}]' \
          "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

      link_tls="trojan://$uuid_tls@$DOMAIN:$port_tls?security=tls&type=ws&path=$path_ws_tls#$name"
      link_ntls="trojan://$uuid_ntls@$DOMAIN:$port_ntls?type=ws&path=$path_ws_ntls#$name"
      ;;
    *)
      echo -e "${RED}Protocole inconnu.${RESET}"
      return 1
      ;;
  esac

  local exp_date_iso=$(date -d "+$days days" +"%Y-%m-%d")
  echo "$uuid_tls|$exp_date_iso" >> /etc/xray/users_expiry.list
  echo "$uuid_ntls|$exp_date_iso" >> /etc/xray/users_expiry.list

  local total_users=$(count_users)

echo
echo -e "${CYAN}==============================${RESET}"
echo -e "${BOLD}🧩 ${proto^^}${RESET}"
echo -e "${CYAN}==============================${RESET}"
echo -e "${YELLOW}📄 Configuration générée pour :${RESET} $name"
echo "--------------------------------------------------"
echo -e "➤ DOMAINE : ${YELLOW}$DOMAIN${RESET}"
echo -e "${GREEN}➤ PORTs :${RESET}"
echo -e "   TLS   : ${MAGENTA}$port_tls${RESET}"
echo -e "   NTLS  : ${MAGENTA}$port_ntls${RESET}"
echo -e "${GREEN}➤ UUIDs générés :${RESET}"
echo -e "   TLS   : ${MAGENTA}$uuid_tls${RESET}"
echo -e "   NTLS  : ${MAGENTA}$uuid_ntls${RESET}"
echo -e "➤ Paths :"
echo -e "   TLS   : ${MAGENTA}$path_ws_tls${RESET}"
echo -e "   NTLS  : ${MAGENTA}$path_ws_ntls${RESET}"
echo -e "➤ Validité : ${YELLOW}$days jours${RESET} (expire le $(date -d "+$days days" +"%d/%m/%Y"))"
echo -e "➤ Nombre total d'utilisateurs : ${BOLD}$limit${RESET}"
echo
echo -e "${CYAN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${RESET}"
echo -e "${CYAN}┃ TLS     : ${GREEN}$link_tls${RESET}"
echo
echo -e "${CYAN}┃ Non‑TLS : ${GREEN}$link_ntls${RESET}"
echo -e "${CYAN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${RESET}"
echo

  systemctl restart xray
}

delete_user_by_number() {
  if [[ ! -f "$USERS_FILE" ]]; then
    echo -e "${RED}Fichier $USERS_FILE introuvable.${RESET}"
    return 1
  fi

  # Map des clés vers les protocoles
  declare -A protocol_map=(
    [vmess_tls]="vmess"
    [vmess_ntls]="vmess"
    [vless_tls]="vless"
    [vless_ntls]="vless"
    [trojan_tls]="trojan"
    [trojan_ntls]="trojan"
  )

  users=()
  keys=()
  count=0

  # Construire liste des utilisateurs avec leur clé et uuid
  for key in "${!protocol_map[@]}"; do
    uuids=$(jq -r --arg k "$key" '.[$k] // [] | .[]?.uuid' "$USERS_FILE" 2>/dev/null)
    while IFS= read -r uuid; do
      [[ -n "$uuid" ]] && { users+=("$key:$uuid"); keys+=("$key"); ((count++)); }
    done <<< "$uuids"
  done

  if (( count == 0 )); then
    echo -e "${RED}Aucun utilisateur à supprimer.${RESET}"
    return 0
  fi

  echo -e "${GREEN}Liste des utilisateurs Xray :${RESET}"
  for ((i=0; i<count; i++)); do
    proto="${users[$i]%%:*}"
    uuid="${users[$i]#*:}"
    echo -e "[$((i+1))] Protocole : ${YELLOW}${proto%%_*}${RESET} - UUID : ${CYAN}$uuid${RESET}"
  done

  read -rp "Numéro à supprimer (0 pour annuler) : " num
  if ! [[ "$num" =~ ^[0-9]+$ ]] || (( num < 0 )) || (( num > count )); then
    echo -e "${RED}Numéro invalide.${RESET}"
    return 1
  fi

  (( num == 0 )) && { echo "Suppression annulée."; return 0; }

  idx=$((num - 1))
  sel_key="${keys[$idx]}"
  sel_uuid="${users[$idx]#*:}"
  sel_proto="${protocol_map[$sel_key]}"
  tls_key="${sel_proto}_tls"
  ntls_key="${sel_proto}_ntls"

  # Sauvegarde avant modification
  cp "$USERS_FILE" "${USERS_FILE}.bak"
  cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

  # Suppression dans les deux tableaux TLS et NTLS pour le même protocole
  jq --arg tls "$tls_key" --arg ntls "$ntls_key" --arg u "$sel_uuid" '
    .[$tls] |= map(select(.uuid != $u)) |
    .[$ntls] |= map(select(.uuid != $u))
  ' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"

  if [[ $? -ne 0 ]]; then
    echo -e "${RED}Erreur lors de la modification de $USERS_FILE. Restauration du fichier.${RESET}"
    mv "${USERS_FILE}.bak" "$USERS_FILE"
    return 1
  fi

  if [[ "$sel_proto" == "vmess" || "$sel_proto" == "vless" ]]; then
    jq --arg proto "$sel_proto" --arg id "$sel_uuid" --arg stream "tls" '
      (.inbounds[] | select(.protocol == $proto and .streamSettings.security == "tls") | .settings.clients) |= map(select(.id != $id))
    ' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

    jq --arg proto "$sel_proto" --arg id "$sel_uuid" --arg stream "none" '
      (.inbounds[] | select(.protocol == $proto and .streamSettings.security == "none") | .settings.clients) |= map(select(.id != $id))
    ' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
  else
    # Trojan
    jq --arg id "$sel_uuid" '
      (.inbounds[] | select(.protocol == "trojan") | .settings.clients) |= map(select(.password != $id))
    ' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
  fi

  if [[ $? -ne 0 ]]; then
    echo -e "${RED}Erreur lors de la modification de $CONFIG_FILE. Restauration du fichier.${RESET}"
    mv "${CONFIG_FILE}.bak" "$CONFIG_FILE"
    return 1
  fi

  # Nettoyer le fichier d’expiration si besoin
  [[ -f /etc/xray/users_expiry.list ]] && grep -v "^${sel_uuid}|" /etc/xray/users_expiry.list > /tmp/expiry.tmp && mv /tmp/expiry.tmp /etc/xray/users_expiry.list

  # Redémarrage du service
  systemctl restart xray

  echo -e "${GREEN}Utilisateur supprimé : $sel_proto / UUID: $sel_uuid${RESET}"
}

choice=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f /tmp/.xray_domain ]] && DOMAIN=$(cat /tmp/.xray_domain)
load_user_data

while true; do
  clear
  print_header
  afficher_utilisateurs_xray
  afficher_appareils_connectes
  print_consommation_xray
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
      read -rp "Limite totale d'utilisateurs (devices) : " limit
      [[ -n "$conf_name" && -n "$days" && -n "$limit" ]] && create_config "vmess" "$conf_name" "$days" "$limit"
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    3)
      read -rp "Nom de l'utilisateur VLESS : " conf_name
      read -rp "Durée (jours) : " days
      read -rp "Limite totale d'utilisateurs (devices) : " limit
      [[ -n "$conf_name" && -n "$days" && -n "$limit" ]] && create_config "vless" "$conf_name" "$days" "$limit"
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    4)
      read -rp "Nom de l'utilisateur TROJAN : " conf_name
      read -rp "Durée (jours) : " days
      read -rp "Limite totale d'utilisateurs (devices) : " limit
      [[ -n "$conf_name" && -n "$days" && -n "$limit" ]] && create_config "trojan" "$conf_name" "$days" "$limit"
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    5)
      delete_user_by_number
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    6)
      echo -e "${YELLOW}Désinstallation complète de Xray et Trojan en cours...${RESET}"

read -rp "Es-tu sûr de vouloir désinstaller Xray et Trojan-Go ? (o/n) : " confirm
case "$confirm" in
  [oO]|[yY]|[yY][eE][sS])
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
     ;;
   *)
    echo "Désinstallation annulée."
     ;;
esac

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
