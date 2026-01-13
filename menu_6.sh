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
    if [[ ! -f "$USERS_FILE" ]]; then
        echo -e "${RED}Fichier des utilisateurs introuvable.${NC}"
        return 1
    fi

    users=()
    protos=()

    # VMess
    for u in $(jq -r '.vmess[]?.uuid' "$USERS_FILE"); do
        users+=("$u")
        protos+=("vmess")
    done

    # VLESS
    for u in $(jq -r '.vless[]?.uuid' "$USERS_FILE"); do
        users+=("$u")
        protos+=("vless")
    done

    # Trojan
    for u in $(jq -r '.trojan[]?.password' "$USERS_FILE"); do
        users+=("$u")
        protos+=("trojan")
    done

    if [[ ${#users[@]} -eq 0 ]]; then
        echo -e "${RED}Aucun utilisateur Xray trouvé.${NC}"
        return 0
    fi

    echo -e "${BOLD}Liste des utilisateurs Xray :${NC}"
    for i in "${!users[@]}"; do
        echo -e "[$((i+1))] Protocole: ${YELLOW}${protos[$i]}${NC} - UUID/Password: ${CYAN}${users[$i]}${NC}"
    done
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
    VMESS=$(jq -c '.vmess // []' "$USERS_FILE")
    VLESS=$(jq -c '.vless // []' "$USERS_FILE")
    TROJAN=$(jq -c '.trojan // []' "$USERS_FILE")
  else
    VMESS="[]"
    VLESS="[]"
    TROJAN="[]"
  fi
}

# Compte total des utilisateurs multi-protocole
count_users() {
    local vmess_count vless_count trojan_count total

    vmess_count=$(jq '.vmess | length // 0' "$USERS_FILE")
    vless_count=$(jq '.vless | length // 0' "$USERS_FILE")
    trojan_count=$(jq '.trojan | length // 0' "$USERS_FILE")

    total=$(( vmess_count + vless_count + trojan_count ))

    echo "$total"
}

create_config() {
  local proto=$1 name=$2 days=$3 limit=$4

  # 🔹 Lecture automatique du domaine si vide
  if [[ -z "$DOMAIN" ]]; then
      if [[ -f /etc/xray/domain ]]; then
          DOMAIN=$(cat /etc/xray/domain)
      else
          echo -e "${RED}⚠️ Domaine non défini.${NC}"
          return 1
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

      # Ajout dans users.json
      jq --arg id "$uuid" --argjson lim "$limit" \
        '.vmess += [{"uuid": $id, "limit": $lim}]' \
        "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"

      # Ajout dans config.json (TLS et non-TLS)
      jq --arg id "$uuid" '
        (.inbounds[] | select(.protocol=="vmess" and .streamSettings.security=="tls") | .settings.clients)
          += [{"id": $id,"alterId":0}] |
        (.inbounds[] | select(.protocol=="vmess" and .streamSettings.security=="none") | .settings.clients)
          += [{"id": $id,"alterId":0}]
      ' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

      # Génération des liens
      link_tls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_tls\",\"id\":\"$uuid\",\"aid\":0,\"net\":\"ws\",\"type\":\"none\",\"host\":\"$DOMAIN\",\"path\":\"$path_ws_tls\",\"tls\":\"tls\",\"sni\":\"$DOMAIN\"}" | base64 -w0)"
      link_ntls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_ntls\",\"id\":\"$uuid\",\"aid\":0,\"net\":\"ws\",\"type\":\"none\",\"host\":\"$DOMAIN\",\"path\":\"$path_ws_ntls\",\"tls\":\"none\"}" | base64 -w0)"
      ;;

    vless)
      path_ws_tls="/vless-tls"
      path_ws_ntls="/vless-ntls"

      jq --arg id "$uuid" --argjson lim "$limit" \
        '.vless += [{"uuid": $id, "limit": $lim}]' \
        "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"

      jq --arg id "$uuid" '
        (.inbounds[] | select(.protocol=="vless" and .streamSettings.security=="tls") | .settings.clients)
          += [{"id": $id}] |
        (.inbounds[] | select(.protocol=="vless" and .streamSettings.security=="none") | .settings.clients)
          += [{"id": $id}]
      ' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

      link_tls="vless://$uuid@$DOMAIN:$port_tls?security=tls&type=ws&host=$DOMAIN&path=$path_ws_tls&encryption=none&sni=$DOMAIN#$name"
      link_ntls="vless://$uuid@$DOMAIN:$port_ntls?security=none&type=ws&host=$DOMAIN&path=$path_ws_ntls&encryption=none#$name"
      ;;

    trojan)
      path_ws_tls="/trojan-tls"
      path_ws_ntls="/trojan-ntls"

      jq --arg pw "$uuid" --argjson lim "$limit" \
        '.trojan += [{"password": $pw, "limit": $lim}]' \
        "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"

      jq --arg pw "$uuid" '
        (.inbounds[] | select(.protocol=="trojan" and .streamSettings.security=="tls") | .settings.clients)
          += [{"password": $pw}] |
        (.inbounds[] | select(.protocol=="trojan" and .streamSettings.security=="none") | .settings.clients)
          += [{"password": $pw}]
      ' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

      link_tls="trojan://$uuid@$DOMAIN:$port_tls?security=tls&type=ws&path=$path_ws_tls&host=$DOMAIN&sni=$DOMAIN#$name"
      link_ntls="trojan://$uuid@$DOMAIN:$port_ntls?type=ws&path=$path_ws_ntls&host=$DOMAIN#$name"
      ;;

    *)
      echo -e "${RED}Protocole inconnu.${NC}"
      return 1
      ;;
  esac

  # 🔹 Gestion de la validité
  local exp_date_iso=$(date -d "+$days days" +"%Y-%m-%d")
  echo "$uuid|$exp_date_iso" >> /etc/xray/users_expiry.list

  # 🔹 Affichage résumé
  echo
  echo -e "${CYAN}==============================${NC}"
  echo -e "🧩 ${proto^^}"
  echo -e "${CYAN}==============================${NC}"
  echo -e "📄 Configuration générée pour : $name"
  echo "--------------------------------------------------"
  echo -e "➤ DOMAINE : $DOMAIN"
  echo -e "➤ PORTs : TLS=$port_tls / NTLS=$port_ntls"
  echo -e "➤ UUID / Password : $uuid"
  echo -e "➤ Paths : TLS=$path_ws_tls / NTLS=$path_ws_ntls"
  echo -e "➤ Validité : $days jours (expire le $(date -d "+$days days" +"%d/%m/%Y"))"
  echo -e "➤ Nombre total d'utilisateurs : $limit"
  echo
  echo -e "●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●"
  echo -e "TLS     : $link_tls"
  echo -e "Non-TLS : $link_ntls"
  echo -e "●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●"
  echo

  # 🔹 Redémarrage sécurisé de Xray
  systemctl reload xray 2>/dev/null || systemctl restart xray
}

delete_user_by_number() {
    # Affichage des utilisateurs existants
    afficher_utilisateurs_xray
    if [[ ! -f "$USERS_FILE" ]]; then return 1; fi

    # Demande de sélection
    read -rp "Numéro à supprimer (0 pour annuler) : " num
    if ! [[ "$num" =~ ^[0-9]+$ ]] || (( num < 0 )) || (( num > ${#users[@]} )); then
        echo -e "${RED}Numéro invalide.${NC}"
        return 1
    fi
    (( num == 0 )) && { echo "Suppression annulée."; return 0; }

    idx=$((num - 1))
    sel_uuid="${users[$idx]}"
    sel_proto="${protos[$idx]}"

    # Sauvegarde avant modification
    cp "$USERS_FILE" "${USERS_FILE}.bak"
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

    # Suppression dans users.json
    if [[ "$sel_proto" == "trojan" ]]; then
        jq --arg p "$sel_uuid" '.trojan |= map(select(.password != $p))' \
           "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
    else
        jq --arg u "$sel_uuid" --arg proto "$sel_proto" '.[$proto] |= map(select(.uuid != $u))' \
           "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
    fi

    # Suppression dans config.json
    if [[ "$sel_proto" == "trojan" ]]; then
        jq --arg p "$sel_uuid" '(.inbounds[] | select(.protocol=="trojan") | .settings.clients) |= map(select(.password != $p))' \
           "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
    else
        jq --arg u "$sel_uuid" '(.inbounds[] | select(.protocol=="vmess" or .protocol=="vless") | .settings.clients) |= map(select(.id != $u))' \
           "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
    fi

    # Nettoyage fichier d’expiration
    [[ -f /etc/xray/users_expiry.list ]] && grep -v "^${sel_uuid}|" /etc/xray/users_expiry.list > /tmp/expiry.tmp && mv /tmp/expiry.tmp /etc/xray/users_expiry.list

    # Redémarrage du service Xray
    systemctl restart xray

    echo -e "${GREEN}Utilisateur supprimé : $sel_proto / UUID/Password: $sel_uuid${NC}"
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
