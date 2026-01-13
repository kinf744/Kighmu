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
    # Comptage des UUID uniques pour chaque protocole
    vmess_count=$(jq '[.vmess_tls[], .vmess_ntls[]] | map(.uuid) | unique | length' "$USERS_FILE" 2>/dev/null || echo 0)
    vless_count=$(jq '[.vless_tls[], .vless_ntls[]] | map(.uuid) | unique | length' "$USERS_FILE" 2>/dev/null || echo 0)
    trojan_count=$(jq '[.trojan_tls[], .trojan_ntls[]] | map(.uuid) | unique | length' "$USERS_FILE" 2>/dev/null || echo 0)

    echo -e "${BOLD}Utilisateur Xray :${RESET}"
    echo -e "  • VMess: [${YELLOW}${vmess_count}${RESET}] • VLESS: [${YELLOW}${vless_count}${RESET}] • Trojan: [${YELLOW}${trojan_count}${RESET}]"
  else
    echo -e "${RED}Fichier des utilisateurs introuvable.${RESET}"
  fi
}

afficher_appareils_connectes() {
  declare -A connexions=( ["vmess"]=0 ["vless"]=0 ["trojan"]=0 )

  # Ports par protocole
  declare -A ports_tls=( ["vmess"]=8443 ["vless"]=8443 ["trojan"]=8443 )
  declare -A ports_ntls=( ["vmess"]=8880 ["vless"]=8880 ["trojan"]=8880 )

  for proto in "${!connexions[@]}"; do
    # TLS
    port=${ports_tls[$proto]}
    if [[ -n "$port" ]]; then
      tls_count=$(ss -tn state established "( sport = :$port )" 2>/dev/null | tail -n +2 | wc -l)
      connexions[$proto]=$((connexions[$proto] + tls_count))
    fi
    # Non-TLS
    port=${ports_ntls[$proto]}
    if [[ -n "$port" ]]; then
      ntls_count=$(ss -tn state established "( sport = :$port )" 2>/dev/null | tail -n +2 | wc -l)
      connexions[$proto]=$((connexions[$proto] + ntls_count))
    fi
  done

  echo -e "${BOLD}Appareils connectés :${RESET}"
  echo -e "  • Vmess: [${YELLOW}${connexions["vmess"]}${RESET}]  • Vless: [${YELLOW}${connexions["vless"]}${RESET}]  • Trojan: [${YELLOW}${connexions["trojan"]}${RESET}]"
}

print_consommation_xray() {
  VN_INTERFACE=$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1);exit}}}')
  
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

  # 🔹 Lecture automatique du domaine si vide
  if [[ -z "$DOMAIN" ]]; then
      if [[ -f /etc/xray/domain ]]; then
          DOMAIN=$(cat /etc/xray/domain)
      else
          echo -e "${RED}⚠️ Domaine non défini.${RESET}"
          return
      fi
  fi

  local port_tls=8443
  local port_ntls=8880
  local path_ws_tls path_ws_ntls
  local link_tls link_ntls
  local uuid

  # 🔹 UUID unique
  uuid=$(cat /proc/sys/kernel/random/uuid)

  case "$proto" in
    vmess)
      path_ws_tls="/vmess-tls"
      path_ws_ntls="/vmess-ntls"

      jq --arg id "$uuid" --argjson lim "$limit" \
        '.vmess_tls += [{"uuid": $id, "limit": $lim}] |
         .vmess_ntls += [{"uuid": $id, "limit": $lim}]' \
        "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"

      jq --arg id "$uuid" '
        (.inbounds[] | select(.streamSettings.security=="tls") | .settings.clients)
          += [{"id": $id,"alterId":0}] |
        (.inbounds[] | select(.streamSettings.security=="none") | .settings.clients)
          += [{"id": $id,"alterId":0}]
      ' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

      link_tls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_tls\",\"id\":\"$uuid\",\"aid\":0,\"net\":\"ws\",\"type\":\"none\",\"host\":\"$DOMAIN\",\"path\":\"$path_ws_tls\",\"tls\":\"tls\",\"sni\":\"$DOMAIN\"}" | base64 -w0)"
      link_ntls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_ntls\",\"id\":\"$uuid\",\"aid\":0,\"net\":\"ws\",\"type\":\"none\",\"host\":\"$DOMAIN\",\"path\":\"$path_ws_ntls\",\"tls\":\"none\"}" | base64 -w0)"
      ;;
      
    vless)
      path_ws_tls="/vless-tls"
      path_ws_ntls="/vless-ntls"

      jq --arg id "$uuid" --argjson lim "$limit" \
        '.vless_tls += [{"uuid": $id, "limit": $lim}] |
         .vless_ntls += [{"uuid": $id, "limit": $lim}]' \
        "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"

      jq --arg id "$uuid" '
        (.inbounds[] | select(.streamSettings.security=="tls") | .settings.clients)
          += [{"id": $id}] |
        (.inbounds[] | select(.streamSettings.security=="none") | .settings.clients)
          += [{"id": $id}]
      ' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

      link_tls="vless://$uuid@$DOMAIN:$port_tls?security=tls&type=ws&host=$DOMAIN&path=$path_ws_tls&encryption=none&sni=$DOMAIN#$name"
      link_ntls="vless://$uuid@$DOMAIN:$port_ntls?security=none&type=ws&host=$DOMAIN&path=$path_ws_ntls&encryption=none#$name"
      ;;
      
    trojan)
      path_ws_tls="/trojan-tls"
      path_ws_ntls="/trojan-ntls"

      jq --arg id "$uuid" --argjson lim "$limit" \
        '.trojan_tls += [{"uuid": $id, "limit": $lim}] |
         .trojan_ntls += [{"uuid": $id, "limit": $lim}]' \
        "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"

      jq --arg id "$uuid" '
        (.inbounds[] | select(.streamSettings.security=="tls") | .settings.clients)
          += [{"password": $id}] |
        (.inbounds[] | select(.streamSettings.security=="none") | .settings.clients)
          += [{"password": $id}]
      ' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

      link_tls="trojan://$uuid@$DOMAIN:$port_tls?security=tls&type=ws&path=$path_ws_tls&host=$DOMAIN&sni=$DOMAIN#$name"
      link_ntls="trojan://$uuid@$DOMAIN:$port_ntls?type=ws&path=$path_ws_ntls&host=$DOMAIN#$name"
      ;;
      
    *)
      echo -e "${RED}Protocole inconnu.${RESET}"
      return 1
      ;;
  esac

  local exp_date_iso=$(date -d "+$days days" +"%Y-%m-%d")
  echo "$uuid|$exp_date_iso" >> /etc/xray/users_expiry.list

  # 🔹 Affichage simplifié (reste inchangé)
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
  echo -e "${GREEN}➤ UUID généré :${RESET} ${MAGENTA}$uuid${RESET}"
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
  
  systemctl reload xray 2>/dev/null ||
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

    # Construire liste des utilisateurs TLS + Non-TLS
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

    # Filtrer les UUID uniques pour l'affichage
    declare -A seen
    unique_users=()
    unique_keys=()
    for i in "${!users[@]}"; do
        uuid_only="${users[$i]#*:}"
        if [[ -z "${seen[$uuid_only]}" ]]; then
            unique_users+=("${users[$i]}")
            unique_keys+=("${keys[$i]}")
            seen[$uuid_only]=1
        fi
    done

    users=("${unique_users[@]}")
    keys=("${unique_keys[@]}")
    count=${#users[@]}

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

    # Suppression dans TLS et Non-TLS
    jq --arg tls "$tls_key" --arg ntls "$ntls_key" --arg u "$sel_uuid" '
        .[$tls] |= map(select(.uuid != $u)) |
        .[$ntls] |= map(select(.uuid != $u))
    ' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"

    # Suppression dans config.json
    if [[ "$sel_proto" == "vmess" || "$sel_proto" == "vless" ]]; then
        jq --arg id "$sel_uuid" '
            (.inbounds[] | select(.settings.clients? != null) | .settings.clients) |= map(select(.id != $id))
        ' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
    else
        jq --arg id "$sel_uuid" '
            (.inbounds[] | select(.protocol=="trojan") | .settings.clients) |= map(select(.password != $id))
        ' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
    fi

    # Nettoyer le fichier d’expiration
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

read -rp "Es-tu sûr de vouloir désinstaller Xray, Trojan-Go et X-UI ? (o/n) : " confirm
case "$confirm" in
  [oO]|[yY]|[yY][eE][sS])
    echo -e "${GREEN}Arrêt des services...${NC}"
    systemctl stop xray trojan-go x-ui 2>/dev/null || true
    systemctl disable xray trojan-go x-ui 2>/dev/null || true

    echo -e "${GREEN}Fermeture des ports utilisés...${NC}"
    for port in 8880 8443 2087 2083; do
      lsof -i tcp:$port -t | xargs -r kill -9
      lsof -i udp:$port -t | xargs -r kill -9
    done

    echo -e "${GREEN}Suppression des fichiers et dossiers...${NC}"
    # Xray
    rm -rf /etc/xray /var/log/xray /usr/local/bin/xray /etc/systemd/system/xray.service
    # Trojan-Go
    rm -rf /etc/trojan-go /var/log/trojan-go /usr/local/bin/trojan-go /etc/systemd/system/trojan-go.service
    # X-UI
    rm -rf /usr/local/bin/x-ui /usr/local/x-ui-bin /etc/x-ui /etc/systemd/system/x-ui.service
    # Fichiers temporaires et configs
    rm -f /tmp/.xray_domain /etc/xray/users_expiry.list /etc/xray/users.json /etc/xray/config.json

    echo -e "${GREEN}Reload des services systemd...${NC}"
    systemctl daemon-reload

    echo -e "${GREEN}✅ Désinstallation complète terminée : Xray, Trojan-Go et X-UI ont été supprimés.${NC}"
      ;;
    *)
      echo -e "${YELLOW}Annulé.${NC}"
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
