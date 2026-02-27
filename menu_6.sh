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
WHITE_BOLD="\u001B[1;37m"
RESET="\u001B[0m"

print_header() {
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${CYAN}       ${BOLD}${MAGENTA}Xray – Gestion des Tunnels Actifs${RESET}${CYAN}${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

afficher_utilisateurs_xray() {
    if [[ ! -f "$USERS_FILE" ]]; then
        echo -e "${RED}Fichier des utilisateurs introuvable.${RESET}"
        return 1
    fi

    # Comptage des utilisateurs uniques par protocole
    vmess_count=$(jq '[.vmess[]?.uuid] | unique | length' "$USERS_FILE" 2>/dev/null || echo 0)
    vless_count=$(jq '[.vless[]?.uuid] | unique | length' "$USERS_FILE" 2>/dev/null || echo 0)
    trojan_count=$(jq '[.trojan[]?.password] | unique | length' "$USERS_FILE" 2>/dev/null || echo 0)

    # Affichage aligné avec espaces réguliers
    echo -e "${WHITE_BOLD}Utilisateurs Xray :${RESET}"
    echo -e "  • VMess  [${YELLOW}${vmess_count}${RESET}] • VLESS  [${YELLOW}${vless_count}${RESET}] • Trojan [${YELLOW}${trojan_count}${RESET}]"
}

afficher_appareils_connectes() {
  declare -A connexions=( ["vmess"]=0 ["vless"]=0 ["trojan"]=0 )

  # Ports par protocole
  declare -A ports_tls=( ["vmess"]=8443 ["vless"]=8443 ["trojan"]=8443 )
  declare -A ports_ntls=( ["vmess"]=8880 ["vless"]=8880 ["trojan"]=8880 )

  for proto in "${!connexions[@]}"; do
    ips=()

    # TLS
    port=${ports_tls[$proto]}
    if [[ -n "$port" ]]; then
      mapfile -t tls_ips < <(ss -tn state established "( sport = :$port )" 2>/dev/null | awk 'NR>1 {print $5}' | cut -d: -f1)
      ips+=("${tls_ips[@]}")
    fi

    # Non-TLS
    port=${ports_ntls[$proto]}
    if [[ -n "$port" ]]; then
      mapfile -t ntls_ips < <(ss -tn state established "( sport = :$port )" 2>/dev/null | awk 'NR>1 {print $5}' | cut -d: -f1)
      ips+=("${ntls_ips[@]}")
    fi

    # Compter les IP uniques
    uniq_count=$(printf "%s\n" "${ips[@]}" | sort -u | wc -l)
    connexions[$proto]=$uniq_count
  done

  echo -e "${WHITE_BOLD}Appareils connectés :${RESET}"
  echo -e "  • Vmess: [${YELLOW}${connexions["vmess"]}${RESET}]  • Vless: [${YELLOW}${connexions["vless"]}${RESET}]  • Trojan: [${YELLOW}${connexions["trojan"]}${RESET}]"
}

print_consommation_xray() {
  VN_INTERFACE=$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1);exit}}}')
  
  today_bytes=$(vnstat -i "$VN_INTERFACE" --json | jq '.interfaces[0].traffic.day[0].rx + .interfaces[0].traffic.day[0].tx')
  month_bytes=$(vnstat -i "$VN_INTERFACE" --json | jq '.interfaces[0].traffic.month[0].rx + .interfaces[0].traffic.month[0].tx')

  today_gb=$(awk -v b="$today_bytes" 'BEGIN {printf "%.2f", b / 1073741824}')
  month_gb=$(awk -v b="$month_bytes" 'BEGIN {printf "%.2f", b / 1073741824}')

  echo -e "${WHITE_BOLD}Consommation Xray :${RESET}"
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
  echo -e "${WHITE_BOLD}Tunnels actifs :${RESET}"
  [[ -n "$ports_tls" ]] && echo -e " ${GREEN}•${RESET} Port(s) TLS : [${YELLOW}${ports_tls}${RESET}] – Protocoles [${MAGENTA}${protos}${RESET}]"
  [[ -n "$ports_ntls" ]] && echo -e " ${GREEN}•${RESET} Port(s) Non-TLS : [${YELLOW}${ports_ntls}${RESET}] – Protocoles [${MAGENTA}${protos}${RESET}]"
}

show_menu() {
  echo -e "${CYAN}──────────────────────────────────────────────────────────${RESET}"
  echo -e "${BOLD}${YELLOW}[01]${RESET} Installer Xray"
  echo -e "${BOLD}${YELLOW}[02]${RESET} Créer utilisateur VMess"
  echo -e "${BOLD}${YELLOW}[03]${RESET} Créer utilisateur VLESS"
  echo -e "${BOLD}${YELLOW}[04]${RESET} Créer utilisateur Trojan"
  echo -e "${BOLD}${YELLOW}[05]${RESET} Consommation Xray en Go"
  echo -e "${BOLD}${YELLOW}[06]${RESET} Supprimer utilisateur Xray"
  echo -e "${BOLD}${YELLOW}[07]${RESET} Désinstallation complète Xray"
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
  local proto=$1
  local name=$2
  local days=$3
  local limit=$4   # quota en Go

  # 🔹 Lecture automatique du domaine si vide
  if [[ -z "$DOMAIN" ]]; then
      if [[ -f /etc/xray/domain ]]; then
          DOMAIN=$(cat /etc/xray/domain)
      else
          echo -e "${RED}⚠️ Domaine non défini.${RESET}"
          return 1
      fi
  fi

  # 🔹 Ports standards
  local port_tls=8443
  local port_ntls=8880
  local port_grpc_tls=8443

  # 🔹 Paths par protocole
  local path_ws_tls path_ws_ntls path_grpc
  case "$proto" in
    vmess)          path_ws_tls="/vmess"; path_ws_ntls="/vmess"; path_grpc="vmess-grpc" ;;
    vless)          path_ws_tls="/vless"; path_ws_ntls="/vless"; path_grpc="vless-grpc" ;;
    trojan)         path_ws_tls="/trojan-ws"; path_ws_ntls="/trojan-ws"; path_grpc="trojan-grpc" ;;
    shadowsocks)    path_ws_tls="/ss-ws"; path_ws_ntls="/ss-ws"; path_grpc="" ;;
    *) echo -e "${RED}Protocole inconnu : $proto${RESET}"; return 1 ;;
  esac

  # 🔹 UUID ou mot de passe
  local uuid tag
  uuid=$(cat /proc/sys/kernel/random/uuid)
  tag="${proto}_${name}_${uuid:0:8}"

  # 🔹 Date d’expiration
  local exp_date_iso
  exp_date_iso=$(date -d "+$days days" +"%Y-%m-%d")

  # 🔹 Mise à jour users.json
  case "$proto" in
    vmess|vless)
      jq --arg id "$uuid" --arg name "$name" --arg tag "$tag" --arg exp "$exp_date_iso" --argjson lim "$limit" \
         ".${proto} += [{\"uuid\": \"$uuid\", \"name\": \"$name\", \"tag\": \"$tag\", \"limit_gb\": $limit, \"used_gb\":0, \"expire\": \"$exp_date_iso\"}]" \
         "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
      ;;
    trojan)
      jq --arg pw "$uuid" --arg name "$name" --arg tag "$tag" --arg exp "$exp_date_iso" --argjson lim "$limit" \
         '.trojan += [{"password": $pw, "name": $name, "tag": $tag, "limit_gb": $lim, "used_gb":0,"expire": $exp}]' \
         "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
      ;;
    shadowsocks)
      jq --arg pw "$uuid" --arg name "$name" --arg tag "$tag" --arg exp "$exp_date_iso" --argjson lim "$limit" \
         '.shadowsocks += [{"password": $pw,"method":"aes-128-gcm","name":$name,"tag":$tag,"limit_gb":$lim,"used_gb":0,"expire":$exp}]' \
         "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
      ;;
  esac

  # 🔹 Mise à jour config.json
  case "$proto" in
    vmess)
      jq --arg id "$uuid" --arg tag "$tag" \
         '(.inbounds[] | select(.protocol=="vmess") | .settings.clients //= []) += [{"id":$id,"alterId":0,"email":$tag}]' \
         "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
      ;;
    vless)
      jq --arg id "$uuid" --arg tag "$tag" \
         '(.inbounds[] | select(.protocol=="vless") | .settings.clients) += [{"id":$id,"email":$tag}]' \
         "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
      ;;
    trojan)
      jq --arg pw "$uuid" --arg tag "$tag" \
         '(.inbounds[] | select(.protocol=="trojan") | .settings.clients) += [{"password":$pw,"email":$tag}]' \
         "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
      ;;
    shadowsocks)
      jq --arg pw "$uuid" --arg tag "$tag" \
         '(.inbounds[] | select(.protocol=="shadowsocks") | .settings.clients) += [{"password":$pw,"method":"aes-128-gcm","email":$tag}]' \
         "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
      ;;
  esac

  # 🔹 Génération des liens
  local link_tls link_ntls link_grpc link_ss_tls link_ss_ntls

  # Fonction interne pour encoder SS
  encode_ss() { echo -n "aes-128-gcm:$1" | base64 -w0; }

  case "$proto" in
    vmess)
      local vmess_json
      vmess_json=$(jq -n \
        --arg v "2" --arg ps "$name" --arg add "$DOMAIN" --arg port "$port_tls" --arg id "$uuid" \
        --arg aid "0" --arg net "ws" --arg type "none" --arg host "$DOMAIN" --arg path "$path_ws_tls" --arg tls "tls" \
        '{
          v: $v, ps: $ps, add: $add, port: $port, id: $id, aid: ($aid|tonumber), net: $net, type: $type, host: $host, path: $path, tls: $tls
        }')
      # TLS WS
      link_tls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_tls\",\"id\":\"$uuid\",\"aid\":0,\"net\":\"ws\",\"type\":\"none\",\"host\":\"$DOMAIN\",\"path\":\"$path_ws_tls\",\"tls\":\"tls\",\"sni\":\"$DOMAIN\"}" | base64 -w0)"
      link_ntls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_ntls\",\"id\":\"$uuid\",\"aid\":0,\"net\":\"ws\",\"type\":\"none\",\"host\":\"$DOMAIN\",\"path\":\"$path_ws_ntls\",\"tls\":\"none\"}" | base64 -w0)"
      link_grpc="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_tls\",\"id\":\"$uuid\",\"aid\":0,\"net\":\"grpc\",\"type\":\"none\",\"host\":\"$DOMAIN\",\"path\":\"vmess-grpc\",\"tls\":\"tls\",\"sni\":\"$DOMAIN\"}" | base64 -w0)"
      link_tcp_tls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name-TCP\",\"add\":\"$DOMAIN\",\"port\":\"$port_tcp_tls\",\"id\":\"$uuid\",\"aid\":0,\"net\":\"tcp\",\"type\":\"http\",\"host\":\"$DOMAIN\",\"path\":\"/vmess-tcp\",\"tls\":\"tls\",\"sni\":\"$DOMAIN\"}" | base64 -w0)"
      ;;
    vless|trojan)
      link_tls="${proto}://$uuid@$DOMAIN:$port_tls?security=tls&type=ws&path=$path_ws_tls&host=$DOMAIN&sni=$DOMAIN#$name"
      link_ntls="${proto}://$uuid@$DOMAIN:$port_ntls?security=none&type=ws&path=$path_ws_ntls&host=$DOMAIN#$name"
      link_grpc="${proto}://$uuid@$DOMAIN:$port_grpc_tls?security=tls&type=grpc&serviceName=$path_grpc&sni=$DOMAIN#$name"
      link_tls_tcp="${proto}://$uuid_tls@$DOMAIN:$port_tls?security=tls&type=tcp&encryption=none&sni=$DOMAIN#$name-TCP"
      ;;
    shadowsocks)
      local ss_b64
      ss_b64=$(echo -n "aes-128-gcm:$uuid" | base64 -w0)
      link_ss_tls="ss://${ss_b64}@${DOMAIN}:${port_tls}?path=${path_ws_tls}&security=tls&host=${DOMAIN}&type=ws&sni=${DOMAIN}#${name}"
      link_ss_ntls="ss://${ss_b64}@${DOMAIN}:${port_ntls}?path=${path_ws_ntls}&security=none&host=${DOMAIN}&type=ws&sni=${DOMAIN}#${name}"
      ;;
  esac

  # 🔹 Sauvegarde expiration
  echo "$uuid|$exp_date_iso" >> /etc/xray/users_expiry.list

  # 🔹 Affichage complet après création
  echo
  echo -e "${CYAN}==============================${RESET}"
  echo -e "${BOLD}🧩 ${proto^^} – $name${RESET}"
  echo -e "${CYAN}==============================${RESET}"
  echo -e "${YELLOW}📄 Utilisateur :${RESET} $name"
  echo -e "${GREEN}➤ Ports :${RESET} TLS [$port_tls] | Non-TLS [$port_ntls] | gRPC [$port_grpc_tls]"
  echo -e "${GREEN}➤ UUID / Password :${RESET} $uuid"
  echo -e "${GREEN}➤ Paths WS :${RESET} TLS [$path_ws_tls] | Non-TLS [$path_ws_ntls]"
  [[ -n "$path_grpc" ]] && echo -e "${GREEN}➤ gRPC ServiceName :${RESET} $path_grpc"
  echo -e "${GREEN}➤ Domaine :${RESET} $DOMAIN"
  echo -e "${GREEN}➤ Limite Go :${RESET} $limit Go"
  echo -e "${GREEN}➤ Expiration :${RESET} $exp_date_iso"
  echo
  echo -e "${CYAN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${RESET}"
  [[ -n "$link_tls" ]] && echo -e "${CYAN}┃ TLS WS      : ${GREEN}$link_tls${RESET}"
  [[ -n "$link_ntls" ]] && echo -e "${CYAN}┃ Non-TLS WS  : ${GREEN}$link_ntls${RESET}"
  [[ -n "$link_grpc" ]] && echo -e "${CYAN}┃ gRPC TLS    : ${GREEN}$link_grpc${RESET}"
  [[ -n "$link_grpc" ]] && echo -e "${CYAN}┃ TCP TLS    : ${GREEN}$link_tcp_tls${RESET}"
  [[ -n "$link_ss_tls" ]] && echo -e "${CYAN}┃ SS TLS WS   : ${GREEN}$link_ss_tls${RESET}"
  [[ -n "$link_ss_ntls" ]] && echo -e "${CYAN}┃ SS Non-TLS  : ${GREEN}$link_ss_ntls${RESET}"
  echo -e "${CYAN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${RESET}"
  echo

  # 🔹 Redémarrage sécurisé de Xray
  systemctl reload xray 2>/dev/null || systemctl restart xray
}

delete_user_by_number() {
    [[ ! -f "$USERS_FILE" ]] && {
        echo -e "${RED}Fichier users.json introuvable.${NC}"
        return 1
    }

    # Tableaux locaux propres
    local users=()
    local protos=()

    # VMess
    while read -r u; do
        users+=("$u")
        protos+=("vmess")
    done < <(jq -r '.vmess[]?.uuid' "$USERS_FILE")

    # VLESS
    while read -r u; do
        users+=("$u")
        protos+=("vless")
    done < <(jq -r '.vless[]?.uuid' "$USERS_FILE")

    # Trojan
    while read -r u; do
        users+=("$u")
        protos+=("trojan")
    done < <(jq -r '.trojan[]?.password' "$USERS_FILE")

    # Aucun utilisateur
    if (( ${#users[@]} == 0 )); then
        echo -e "${RED}Aucun utilisateur Xray à supprimer.${NC}"
        return 0
    fi

    # Affichage propre et numéroté
    echo
    echo -e "${YELLOW}Liste des utilisateurs Xray :${NC}"
    for i in "${!users[@]}"; do
        echo "[$((i+1))] ${protos[$i]} → ${users[$i]}"
    done
    echo

    # Sélection
    read -rp "Numéro à supprimer (0 pour annuler) : " num
    if ! [[ "$num" =~ ^[0-9]+$ ]] || (( num < 0 || num > ${#users[@]} )); then
        echo -e "${RED}Numéro invalide.${NC}"
        return 1
    fi
    (( num == 0 )) && { echo "Suppression annulée."; return 0; }

    local idx=$((num - 1))
    local sel_uuid="${users[$idx]}"
    local sel_proto="${protos[$idx]}"

    # Sauvegardes
    cp "$USERS_FILE" "${USERS_FILE}.bak"
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

    # Suppression users.json
    if [[ "$sel_proto" == "trojan" ]]; then
        jq --arg p "$sel_uuid" \
          '.trojan |= map(select(.password != $p))' \
          "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
    else
        jq --arg u "$sel_uuid" --arg proto "$sel_proto" \
          '.[$proto] |= map(select(.uuid != $u))' \
          "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
    fi

    # Suppression config.json
    if [[ "$sel_proto" == "trojan" ]]; then
        jq --arg p "$sel_uuid" \
          '(.inbounds[] | select(.protocol=="trojan") | .settings.clients)
           |= map(select(.password != $p))' \
          "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
    else
        jq --arg u "$sel_uuid" \
          '(.inbounds[] | select(.protocol=="vmess" or .protocol=="vless") | .settings.clients)
           |= map(select(.id != $u))' \
          "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
    fi

    # Nettoyage expiration
    [[ -f /etc/xray/users_expiry.list ]] &&
      sed -i "/^$sel_uuid|/d" /etc/xray/users_expiry.list

    systemctl restart xray

    echo -e "${GREEN}✅ Utilisateur supprimé : $sel_proto / $sel_uuid${NC}"
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
      read -rp "Limite totale de Go : " limit
      [[ -n "$conf_name" && -n "$days" && -n "$limit" ]] && create_config "vmess" "$conf_name" "$days" "$limit"
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    3)
      read -rp "Nom de l'utilisateur VLESS : " conf_name
      read -rp "Durée (jours) : " days
      read -rp "Limite totale de Go : " limit
      [[ -n "$conf_name" && -n "$days" && -n "$limit" ]] && create_config "vless" "$conf_name" "$days" "$limit"
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    4)
      read -rp "Nom de l'utilisateur TROJAN : " conf_name
      read -rp "Durée (jours) : " days
      read -rp "Limite totale de Go : " limit
      [[ -n "$conf_name" && -n "$days" && -n "$limit" ]] && create_config "trojan" "$conf_name" "$days" "$limit"
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    5)
  chmod +x $HOME/Kighmu/xray-quota-panel.sh  # → une seule fois suffit avant le premier lancement
  bash $HOME/Kighmu/xray-quota-panel.sh
  read -p "Appuyez sur Entrée pour revenir..."
      ;;
    6)
      delete_user_by_number
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    7)
      echo -e "${YELLOW}Désinstallation complète de Xray et Trojan en cours...${RESET}"

read -rp "Es-tu sûr de vouloir désinstaller Xray, Trojan-Go et X-UI ? (o/n) : " confirm
case "$confirm" in
  [oO]|[yY]|[yY][eE][sS])
    echo -e "${GREEN}Arrêt des services...${NC}"
    systemctl stop xray nginx trojan-go x-ui 2>/dev/null || true
    systemctl disable xray nginx trojan-go x-ui 2>/dev/null || true

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
