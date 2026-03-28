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

# Ports TCP TLS directs (dans Xray, sans Nginx)
PORT_TCP_TLS_VMESS=14430
PORT_TCP_TLS_VLESS=14431
PORT_TCP_TLS_TROJAN=14432

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

    vmess_count=$(jq '[.vmess[]?.uuid] | unique | length' "$USERS_FILE" 2>/dev/null || echo 0)
    vless_count=$(jq '[.vless[]?.uuid] | unique | length' "$USERS_FILE" 2>/dev/null || echo 0)
    trojan_count=$(jq '[.trojan[]?.password] | unique | length' "$USERS_FILE" 2>/dev/null || echo 0)

    echo -e "${WHITE_BOLD}Utilisateurs Xray :${RESET}"
    echo -e "  • VMess  [${YELLOW}${vmess_count}${RESET}] • VLESS  [${YELLOW}${vless_count}${RESET}] • Trojan [${YELLOW}${trojan_count}${RESET}]"
}

afficher_appareils_connectes() {
  declare -A connexions=( ["vmess"]=0 ["vless"]=0 ["trojan"]=0 )

  declare -A ports_tls=( ["vmess"]=8443 ["vless"]=8443 ["trojan"]=8443 )
  declare -A ports_ntls=( ["vmess"]=8880 ["vless"]=8880 ["trojan"]=8880 )
  declare -A ports_tcp=( ["vmess"]=14430 ["vless"]=14431 ["trojan"]=14432 )

  for proto in "${!connexions[@]}"; do
    ips=()

    port=${ports_tls[$proto]}
    mapfile -t tls_ips < <(ss -tn state established "( sport = :$port )" 2>/dev/null | awk 'NR>1 {print $5}' | cut -d: -f1)
    ips+=("${tls_ips[@]}")

    port=${ports_ntls[$proto]}
    mapfile -t ntls_ips < <(ss -tn state established "( sport = :$port )" 2>/dev/null | awk 'NR>1 {print $5}' | cut -d: -f1)
    ips+=("${ntls_ips[@]}")

    port=${ports_tcp[$proto]}
    mapfile -t tcp_ips < <(ss -tn state established "( sport = :$port )" 2>/dev/null | awk 'NR>1 {print $5}' | cut -d: -f1)
    ips+=("${tcp_ips[@]}")

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
  echo -e "  • Aujourd'hui : [${GREEN}${today_gb} Go${RESET}]"
  echo -e "  • Ce mois : [${GREEN}${month_gb} Go${RESET}]"
}

afficher_xray_actifs() {
  if ! systemctl is-active --quiet xray; then
    echo -e "${RED}Service Xray non actif.${RESET}"
    return
  fi
  local ports_tls ports_ntls protos
  ports_tls=$(jq -r '.inbounds[] | select(.streamSettings.security=="tls") | .port' "$CONFIG_FILE" | sort -u | paste -sd ", ")
  ports_ntls=$(jq -r '.inbounds[] | select(.streamSettings.security=="none" or (.streamSettings.security == null and .listen == "127.0.0.1")) | .port' "$CONFIG_FILE" | sort -u | paste -sd ", ")
  protos=$(jq -r '.inbounds[].protocol' "$CONFIG_FILE" | sort -u | paste -sd ", ")
  echo -e "${WHITE_BOLD}Tunnels actifs :${RESET}"
  [[ -n "$ports_tls" ]] && echo -e " ${GREEN}•${RESET} Port(s) TLS direct : [${YELLOW}${ports_tls}${RESET}] – Protocoles [${MAGENTA}${protos}${RESET}]"
  echo -e " ${GREEN}•${RESET} Nginx TLS 8443 | NTLS 8880"
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

count_users() {
  local vmess_count vless_count trojan_count total
  vmess_count=$(jq '.vmess | length // 0' "$USERS_FILE" 2>/dev/null || echo 0)
  vless_count=$(jq '.vless | length // 0' "$USERS_FILE" 2>/dev/null || echo 0)
  trojan_count=$(jq '.trojan | length // 0' "$USERS_FILE" 2>/dev/null || echo 0)
  total=$(( vmess_count + vless_count + trojan_count ))
  echo "$total"
}

create_config() {
  local proto=$1
  local name=$2
  local days=$3
  local limit=$4

  # Lecture du domaine
  if [[ -z "$DOMAIN" ]]; then
    if [[ -f /tmp/.xray_domain ]]; then
      DOMAIN=$(cat /tmp/.xray_domain)
    elif [[ -f /etc/xray/domain ]]; then
      DOMAIN=$(cat /etc/xray/domain)
    else
      echo -e "${RED}⚠️ Domaine non défini.${RESET}"
      return 1
    fi
  fi

  local port_tls=8443
  local port_ntls=8880
  local port_grpc_tls=8443
  local uuid tag
  local path_ws_tls path_ws_ntls path_grpc
  local port_tcp_tls
  local link_ws_tls link_ws_ntls link_grpc_tls link_tcp_tls

  uuid=$(cat /proc/sys/kernel/random/uuid)
  tag="${proto}_${name}_${uuid:0:8}"
  local exp_date_iso
  exp_date_iso=$(date -d "+$days days" +"%Y-%m-%d")

  case "$proto" in
    vmess)
      path_ws_tls="/vmess"
      path_ws_ntls="/vmess"
      path_grpc="vmess-grpc"
      port_tcp_tls=$PORT_TCP_TLS_VMESS

      jq --arg id "$uuid" --arg name "$name" --arg tag "$tag" --arg exp "$exp_date_iso" --argjson lim "$limit" \
         '.vmess += [{"uuid":$id,"email":$tag,"name":$name,"tag":$tag,"limit_gb":$lim,"used_gb":0,"expire":$exp}]' \
         "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"

      jq --arg id "$uuid" --arg tag "$tag" \
         '(.inbounds[] | select(.protocol=="vmess") | .settings.clients //= []) += [{"id":$id,"alterId":0,"email":$tag}]' \
         "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

      link_ws_tls="vmess://$(echo -n '{"ps":"'"${name}"'-WS-TLS","add":"'"$DOMAIN"'","port":"'"$port_tls"'","id":"'"$uuid"'","aid":0,"net":"ws","type":"none","host":"'"$DOMAIN"'","path":"'"$path_ws_tls"'","tls":"tls","sni":"'"$DOMAIN"'"}' | base64 -w0)"
      link_ws_ntls="vmess://$(echo -n '{"ps":"'"${name}"'-WS-NTLS","add":"'"$DOMAIN"'","port":"'"$port_ntls"'","id":"'"$uuid"'","aid":0,"net":"ws","type":"none","host":"'"$DOMAIN"'","path":"'"$path_ws_ntls"'","tls":"none"}' | base64 -w0)"
      link_grpc_tls="vmess://$(echo -n '{"ps":"'"${name}"'-gRPC-TLS","add":"'"$DOMAIN"'","port":"'"$port_grpc_tls"'","id":"'"$uuid"'","aid":0,"net":"grpc","type":"none","host":"'"$DOMAIN"'","path":"'"$path_grpc"'","tls":"tls","sni":"'"$DOMAIN"'"}' | base64 -w0)"
      link_tcp_tls="vmess://$(echo -n '{"ps":"'"${name}"'-TCP-TLS","add":"'"$DOMAIN"'","port":"'"$port_tcp_tls"'","id":"'"$uuid"'","aid":0,"net":"tcp","type":"none","host":"'"$DOMAIN"'","path":"","tls":"tls","sni":"'"$DOMAIN"'"}' | base64 -w0)"
      ;;

    vless)
      path_ws_tls="/vless"
      path_ws_ntls="/vless"
      path_grpc="vless-grpc"
      port_tcp_tls=$PORT_TCP_TLS_VLESS

      jq --arg id "$uuid" --arg name "$name" --arg tag "$tag" --arg exp "$exp_date_iso" --argjson lim "$limit" \
         '.vless += [{"uuid":$id,"email":$tag,"name":$name,"tag":$tag,"limit_gb":$lim,"used_gb":0,"expire":$exp}]' \
         "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"

      jq --arg id "$uuid" --arg tag "$tag" \
         '(.inbounds[] | select(.protocol=="vless") | .settings.clients) += [{"id":$id,"email":$tag}]' \
         "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

      link_ws_tls="vless://$uuid@$DOMAIN:$port_tls?security=tls&type=ws&host=$DOMAIN&path=$path_ws_tls&encryption=none&sni=$DOMAIN#${name}-WS-TLS"
      link_ws_ntls="vless://$uuid@$DOMAIN:$port_ntls?security=none&type=ws&host=$DOMAIN&path=$path_ws_ntls&encryption=none#${name}-WS-NTLS"
      link_grpc_tls="vless://$uuid@$DOMAIN:$port_grpc_tls?security=tls&type=grpc&serviceName=$path_grpc&encryption=none&sni=$DOMAIN#${name}-gRPC-TLS"
      link_tcp_tls="vless://$uuid@$DOMAIN:$port_tcp_tls?security=tls&type=tcp&encryption=none&sni=$DOMAIN#${name}-TCP-TLS"
      ;;

    trojan)
      path_ws_tls="/trojan-ws"
      path_ws_ntls="/trojan-ws"
      path_grpc="trojan-grpc"
      port_tcp_tls=$PORT_TCP_TLS_TROJAN

      jq --arg pw "$uuid" --arg name "$name" --arg tag "$tag" --arg exp "$exp_date_iso" --argjson lim "$limit" \
         '.trojan += [{"password":$pw,"email":$tag,"name":$name,"tag":$tag,"limit_gb":$lim,"used_gb":0,"expire":$exp}]' \
         "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"

      jq --arg pw "$uuid" --arg tag "$tag" \
         '(.inbounds[] | select(.protocol=="trojan") | .settings.clients) += [{"password":$pw,"email":$tag}]' \
         "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

      link_ws_tls="trojan://$uuid@$DOMAIN:$port_tls?security=tls&type=ws&path=$path_ws_tls&host=$DOMAIN&sni=$DOMAIN#${name}-WS-TLS"
      link_ws_ntls="trojan://$uuid@$DOMAIN:$port_ntls?security=none&type=ws&path=$path_ws_ntls&host=$DOMAIN#${name}-WS-NTLS"
      link_grpc_tls="trojan://$uuid@$DOMAIN:$port_grpc_tls?security=tls&type=grpc&serviceName=$path_grpc&sni=$DOMAIN#${name}-gRPC-TLS"
      link_tcp_tls="trojan://$uuid@$DOMAIN:$port_tcp_tls?security=tls&type=tcp&sni=$DOMAIN#${name}-TCP-TLS"
      ;;

    *)
      echo -e "${RED}Protocole inconnu : $proto${RESET}"
      return 1
      ;;
  esac

  # Sauvegarde expiration
  echo "$uuid|$exp_date_iso" >> /etc/xray/users_expiry.list

  # Redémarrage sécurisé de Xray
  systemctl reload xray 2>/dev/null || systemctl restart xray

  # Affichage
  echo
  echo -e "${CYAN}==============================${RESET}"
  echo -e "${BOLD}🧩 ${proto^^} – $name${RESET}"
  echo -e "${CYAN}==============================${RESET}"
  echo -e "${YELLOW}📄 Utilisateur :${RESET} $name"
  echo -e "${GREEN}➤ Domaine :${RESET} $DOMAIN"
  echo -e "${GREEN}➤ UUID / Password :${RESET} $uuid"
  echo -e "${GREEN}➤ Limite Go :${RESET} $limit Go"
  echo -e "${GREEN}➤ Expiration :${RESET} $exp_date_iso"
  echo
  echo -e "${CYAN}🔗 LIENS TLS — port 8443 (via Nginx)${RESET}"
  echo -e "${GREEN}┃ WS  TLS  :${RESET} $link_ws_tls"
  echo -e "${GREEN}┃ gRPC TLS :${RESET} $link_grpc_tls"
  echo -e "${CYAN}🔗 LIEN TCP TLS — port $port_tcp_tls (direct Xray)${RESET}"
  echo -e "${GREEN}┃ TCP TLS  :${RESET} $link_tcp_tls"
  echo -e "${CYAN}🔗 LIEN NTLS — port 8880 (via Nginx)${RESET}"
  echo -e "${GREEN}┃ WS NTLS  :${RESET} $link_ws_ntls"
  echo -e "${CYAN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${RESET}"
  echo
}

delete_user_by_number() {
  [[ ! -f "$USERS_FILE" ]] && {
    echo -e "${RED}Fichier users.json introuvable.${RESET}"
    return 1
  }

  local users=()
  local protos=()

  while read -r u; do
    users+=("$u"); protos+=("vmess")
  done < <(jq -r '.vmess[]?.uuid' "$USERS_FILE" 2>/dev/null)

  while read -r u; do
    users+=("$u"); protos+=("vless")
  done < <(jq -r '.vless[]?.uuid' "$USERS_FILE" 2>/dev/null)

  while read -r u; do
    users+=("$u"); protos+=("trojan")
  done < <(jq -r '.trojan[]?.password' "$USERS_FILE" 2>/dev/null)

  if (( ${#users[@]} == 0 )); then
    echo -e "${RED}Aucun utilisateur Xray à supprimer.${RESET}"
    return 0
  fi

  echo
  echo -e "${YELLOW}Liste des utilisateurs Xray :${RESET}"
  for i in "${!users[@]}"; do
    local nm
    nm=$(jq -r --arg proto "${protos[$i]}" --arg u "${users[$i]}" \
      'if $proto == "trojan" then .trojan[]? | select(.password==$u) | .name // "—"
       else .[$proto][]? | select(.uuid==$u) | .name // "—" end' \
      "$USERS_FILE" 2>/dev/null)
    echo "[$((i+1))] ${protos[$i]}  →  $nm  (${users[$i]})"
  done
  echo

  read -rp "Numéro à supprimer (0 pour annuler) : " num
  if ! [[ "$num" =~ ^[0-9]+$ ]] || (( num < 0 || num > ${#users[@]} )); then
    echo -e "${RED}Numéro invalide.${RESET}"
    return 1
  fi
  (( num == 0 )) && { echo "Suppression annulée."; return 0; }

  local idx=$((num - 1))
  local sel_uuid="${users[$idx]}"
  local sel_proto="${protos[$idx]}"

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
       '(.inbounds[] | select(.protocol=="trojan") | .settings.clients) |= map(select(.password != $p))' \
       "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
  else
    jq --arg u "$sel_uuid" \
       '(.inbounds[] | select(.protocol=="vmess" or .protocol=="vless") | .settings.clients) |= map(select(.id != $u))' \
       "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
  fi

  # Nettoyage expiry list
  [[ -f /etc/xray/users_expiry.list ]] && \
    sed -i "/^${sel_uuid}|/d" /etc/xray/users_expiry.list

  systemctl restart xray

  echo -e "${GREEN}✅ Utilisateur supprimé : $sel_proto / $sel_uuid${RESET}"
}

choice=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f /tmp/.xray_domain ]] && DOMAIN=$(cat /tmp/.xray_domain)
[[ -z "$DOMAIN" && -f /etc/xray/domain ]] && DOMAIN=$(cat /etc/xray/domain)
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
      [[ -z "$DOMAIN" && -f /etc/xray/domain ]] && DOMAIN=$(cat /etc/xray/domain)
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
      chmod +x $HOME/Kighmu/xray-quota-panel.sh
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
          echo -e "${GREEN}Arrêt des services...${RESET}"
          systemctl stop xray nginx trojan-go x-ui 2>/dev/null || true
          systemctl disable xray nginx trojan-go x-ui 2>/dev/null || true

          echo -e "${GREEN}Fermeture des ports utilisés...${RESET}"
          for port in 8880 8443 2087 2083 14430 14431 14432; do
            lsof -i tcp:$port -t | xargs -r kill -9
            lsof -i udp:$port -t | xargs -r kill -9
          done

          echo -e "${GREEN}Suppression des fichiers et dossiers...${RESET}"
          rm -rf /etc/xray /var/log/xray /usr/local/bin/xray /etc/systemd/system/xray.service
          rm -rf /etc/trojan-go /var/log/trojan-go /usr/local/bin/trojan-go /etc/systemd/system/trojan-go.service
          rm -rf /usr/local/bin/x-ui /usr/local/x-ui-bin /etc/x-ui /etc/systemd/system/x-ui.service
          rm -f /tmp/.xray_domain /etc/xray/users_expiry.list

          systemctl daemon-reload
          echo -e "${GREEN}✅ Désinstallation complète terminée.${RESET}"
          ;;
        *)
          echo -e "${YELLOW}Annulé.${RESET}"
          ;;
      esac
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    0)
      echo -e "${RED}Quitter...${RESET}"
      break
      ;;
    *)
      echo -e "${RED}Choix invalide.${RESET}"
      sleep 2
      ;;
  esac
done
