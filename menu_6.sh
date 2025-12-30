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
    vmess_tls_count=$(jq '.vmess.ws_tls | length' "$USERS_FILE" 2>/dev/null || echo 0)
    vmess_ntls_count=$(jq '.vmess.ws_ntls | length' "$USERS_FILE" 2>/dev/null || echo 0)
    vmess_tcp_count=$(jq '.vmess.tcp_tls | length' "$USERS_FILE" 2>/dev/null || echo 0)
    vmess_grpc_count=$(jq '.vmess.grpc_tls | length' "$USERS_FILE" 2>/dev/null || echo 0)

    vless_tls_count=$(jq '.vless.ws_tls | length' "$USERS_FILE" 2>/dev/null || echo 0)
    vless_ntls_count=$(jq '.vless.ws_ntls | length' "$USERS_FILE" 2>/dev/null || echo 0)
    vless_tcp_count=$(jq '.vless.tcp_tls | length' "$USERS_FILE" 2>/dev/null || echo 0)
    vless_grpc_count=$(jq '.vless.grpc_tls | length' "$USERS_FILE" 2>/dev/null || echo 0)

    trojan_tls_count=$(jq '.trojan.ws_tls | length' "$USERS_FILE" 2>/dev/null || echo 0)
    trojan_ntls_count=$(jq '.trojan.ws_ntls | length' "$USERS_FILE" 2>/dev/null || echo 0)
    trojan_tcp_count=$(jq '.trojan.tcp_tls | length' "$USERS_FILE" 2>/dev/null || echo 0)
    trojan_grpc_count=$(jq '.trojan.grpc_tls | length' "$USERS_FILE" 2>/dev/null || echo 0)

    vmess_count=$((vmess_tls_count + vmess_ntls_count + vmess_tcp_count + vmess_grpc_count))
    vless_count=$((vless_tls_count + vless_ntls_count + vless_tcp_count + vless_grpc_count))
    trojan_count=$((trojan_tls_count + trojan_ntls_count + trojan_tcp_count + trojan_grpc_count))

    echo -e "${BOLD}Utilisateur Xray :${RESET}"
    echo -e "  • VMess: [${YELLOW}${vmess_count}${RESET}] • VLESS: [${YELLOW}${vless_count}${RESET}] • Trojan: [${YELLOW}${trojan_count}${RESET}]"
  else
    echo -e "${RED}Fichier des utilisateurs introuvable.${RESET}"
  fi
}

afficher_appareils_connectes() {
  # Définir tous les ports utilisés (WS TLS, NTLS, TCP TLS, gRPC TLS)
  ports_tls=(8443)       # 8443=WS TLS, 8443=TCP TLS, 8443=gRPC TLS (exemple)
  ports_ntls=(80)                 # WS Non-TLS

  declare -A connexions=( ["vmess"]=0 ["vless"]=0 ["trojan"]=0 )

  # Comptage par port
  for port in "${ports_tls[@]}"; do
    total_conns=$(ss -tn state established "( sport = :$port )" 2>/dev/null | tail -n +2 | wc -l)
    # On suppose que chaque port TLS peut servir les 3 protocoles → ajuster si nécessaire
    for proto in "${!connexions[@]}"; do
      connexions[$proto]=$((connexions[$proto] + total_conns))
    done
  done

  for port in "${ports_ntls[@]}"; do
    total_conns=$(ss -tn state established "( sport = :$port )" 2>/dev/null | tail -n +2 | wc -l)
    for proto in "${!connexions[@]}"; do
      connexions[$proto]=$((connexions[$proto] + total_conns))
    done
  done

  echo -e "${BOLD}Appareils connectés :${RESET}"
  echo -e "  • Vmess: [${YELLOW}${connexions["vmess"]}${RESET}]  • Vless: [${YELLOW}${connexions["vless"]}${RESET}]  • Trojan: [${YELLOW}${connexions["trojan"]}${RESET}]"
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
    VMESS_WS_TLS=$(jq -r '.vmess.ws_tls // empty' "$USERS_FILE")
    VMESS_TCP_TLS=$(jq -r '.vmess.tcp_tls // empty' "$USERS_FILE")
    VMESS_GRPC_TLS=$(jq -r '.vmess.grpc_tls // empty' "$USERS_FILE")
    VMESS_NTLS=$(jq -r '.vmess.ws_ntls // empty' "$USERS_FILE")

    VLESS_WS_TLS=$(jq -r '.vless.ws_tls // empty' "$USERS_FILE")
    VLESS_TCP_TLS=$(jq -r '.vless.tcp_tls // empty' "$USERS_FILE")
    VLESS_GRPC_TLS=$(jq -r '.vless.grpc_tls // empty' "$USERS_FILE")
    VLESS_NTLS=$(jq -r '.vless.ws_ntls // empty' "$USERS_FILE")

    TROJAN_WS_TLS=$(jq -r '.trojan.ws_tls // empty' "$USERS_FILE")
    TROJAN_TCP_TLS=$(jq -r '.trojan.tcp_tls // empty' "$USERS_FILE")
    TROJAN_GRPC_TLS=$(jq -r '.trojan.grpc_tls // empty' "$USERS_FILE")
    TROJAN_NTLS=$(jq -r '.trojan.ws_ntls // empty' "$USERS_FILE")
  fi
}

# Compte total des utilisateurs multi-protocole
count_users() {
  local total=0
  local keys=("vmess.ws_tls" "vmess.ws_ntls" "vmess.tcp_tls" "vmess.grpc_tls" \
              "vless.ws_tls" "vless.ws_ntls" "vless.tcp_tls" "vless.grpc_tls" \
              "trojan.ws_tls" "trojan.ws_ntls" "trojan.tcp_tls" "trojan.grpc_tls")

  for key in "${keys[@]}"; do
    local count
    count=$(jq --arg k "$key" 'getpath($k | split(".")) | length // 0' "$USERS_FILE")
    total=$(( total + count ))
  done

  echo "$total"
}

create_config() {
  local proto="$1" name="$2" days="$3" limit="$4"
  [[ -z "$DOMAIN" ]] && { echo "Domaine non défini"; return; }

  local port_tls=8443
  local port_ntls=80
  local uuid
  uuid=$(cat /proc/sys/kernel/random/uuid)

  local path_ws_tls path_ws_ntls service_grpc

  case "$proto" in
    vmess)
      path_ws_tls="/vmess-tls"
      path_ws_ntls="/vmess-ntls"
      service_grpc="vmess-grpc"

      # users.json
      jq --arg id "$uuid" --argjson lim "$limit" \
        '.vmess.ws_tls += [{"uuid":$id,"limit":$lim}] |
         .vmess.ws_ntls += [{"uuid":$id,"limit":$lim}] |
         .vmess.tcp_tls += [{"uuid":$id,"limit":$lim}] |
         .vmess.grpc_tls += [{"uuid":$id,"limit":$lim}]' \
        "$USERS_FILE" > /tmp/u && mv /tmp/u "$USERS_FILE"

      # config.json
      jq --arg id "$uuid" '
        (.inbounds[] | select(.tag=="vmess_ws_tls")   | .settings.clients)+=[{"id":$id,"alterId":0}] |
        (.inbounds[] | select(.tag=="vmess_ws_ntls") | .settings.clients)+=[{"id":$id,"alterId":0}] |
        (.inbounds[] | select(.tag=="vmess_tcp_tls") | .settings.clients)+=[{"id":$id,"alterId":0}] |
        (.inbounds[] | select(.tag=="vmess_grpc_tls")| .settings.clients)+=[{"id":$id,"alterId":0}]
      ' "$CONFIG_FILE" > /tmp/c && mv /tmp/c "$CONFIG_FILE"

      link_ws_tls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_tls\",\"id\":\"$uuid\",\"aid\":0,\"net\":\"ws\",\"path\":\"$path_ws_tls\",\"host\":\"$DOMAIN\",\"tls\":\"tls\",\"sni\":\"$DOMAIN\"}" | base64 -w0)"
      link_ws_ntls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_ntls\",\"id\":\"$uuid\",\"aid\":0,\"net\":\"ws\",\"path\":\"$path_ws_ntls\",\"host\":\"$DOMAIN\",\"tls\":\"none\"}" | base64 -w0)"
      link_tcp="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_tls\",\"id\":\"$uuid\",\"aid\":0,\"net\":\"tcp\",\"tls\":\"tls\",\"sni\":\"$DOMAIN\"}" | base64 -w0)"
      link_grpc="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_tls\",\"id\":\"$uuid\",\"aid\":0,\"net\":\"grpc\",\"serviceName\":\"$service_grpc\",\"tls\":\"tls\",\"sni\":\"$DOMAIN\"}" | base64 -w0)"
      ;;
      
    vless)
      path_ws_tls="/vless-tls"
      path_ws_ntls="/vless-ntls"
      service_grpc="vless-grpc"

      jq --arg id "$uuid" --argjson lim "$limit" \
        '.vless.ws_tls += [{"uuid":$id,"limit":$lim}] |
         .vless.ws_ntls += [{"uuid":$id,"limit":$lim}] |
         .vless.tcp_tls += [{"uuid":$id,"limit":$lim}] |
         .vless.grpc_tls += [{"uuid":$id,"limit":$lim}]' \
        "$USERS_FILE" > /tmp/u && mv /tmp/u "$USERS_FILE"

      jq --arg id "$uuid" '
        (.inbounds[] | select(.tag=="vless_ws_tls")   | .settings.clients)+=[{"id":$id}] |
        (.inbounds[] | select(.tag=="vless_ws_ntls") | .settings.clients)+=[{"id":$id}] |
        (.inbounds[] | select(.tag=="vless_tcp_tls") | .settings.clients)+=[{"id":$id}] |
        (.inbounds[] | select(.tag=="vless_grpc_tls")| .settings.clients)+=[{"id":$id}]
      ' "$CONFIG_FILE" > /tmp/c && mv /tmp/c "$CONFIG_FILE"

      link_ws_tls="vless://$uuid@$DOMAIN:$port_tls?security=tls&type=ws&path=$path_ws_tls&host=$DOMAIN&sni=$DOMAIN#$name"
      link_ws_ntls="vless://$uuid@$DOMAIN:$port_ntls?security=none&type=ws&path=$path_ws_ntls&host=$DOMAIN#$name"
      link_tcp="vless://$uuid@$DOMAIN:$port_tls?security=tls&type=tcp&sni=$DOMAIN#$name"
      link_grpc="vless://$uuid@$DOMAIN:$port_tls?security=tls&type=grpc&serviceName=$service_grpc&sni=$DOMAIN#$name"
      ;;
  esac

  local exp=$(date -d "+$days days" +"%Y-%m-%d")
  echo "$uuid|$exp" >> /etc/xray/users_expiry.list

  systemctl restart xray

  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Utilisateur $proto créé : $name"
  echo "UUID : $uuid"
  echo "WS TLS  : $link_ws_tls"
  echo "WS NTLS : $link_ws_ntls"
  echo "TCP TLS : $link_tcp"
  echo "gRPC TLS: $link_grpc"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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
      bash "$HOME/Kighmu/Delete_user_xray.sh"
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
