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

    vmess_count=$(jq  '[.vmess[]?.uuid]  | unique | length' "$USERS_FILE" 2>/dev/null || echo 0)
    vless_count=$(jq  '[.vless[]?.uuid]  | unique | length' "$USERS_FILE" 2>/dev/null || echo 0)
    trojan_count=$(jq '[.trojan[]?.uuid] | unique | length' "$USERS_FILE" 2>/dev/null || echo 0)

    echo -e "${WHITE_BOLD}Utilisateurs Xray :${RESET}"
    echo -e "  • VMess [${YELLOW}${vmess_count}${RESET}]  • VLESS [${YELLOW}${vless_count}${RESET}]  • Trojan [${YELLOW}${trojan_count}${RESET}]"
}

afficher_appareils_connectes() {
  local vmess_count=0 vless_count=0 trojan_count=0

  # TLS port 8443 + NTLS port 8880
  for port in 8443 8880; do
    mapfile -t ips < <(ss -tn state established "( sport = :$port )" 2>/dev/null | awk 'NR>1 {print $5}' | cut -d: -f1)
    for ip in "${ips[@]}"; do
      [[ -n "$ip" ]] && (( vmess_count++ ))   # même port partagé — comptage global
    done
  done
  # NOTE : le port 8443/8880 est partagé entre vmess/vless/trojan via Nginx.
  # On affiche le nombre total de connexions actives sur ces ports.
  local total_conn
  total_conn=$(ss -tn state established '( sport = :8443 or sport = :8880 )' 2>/dev/null | awk 'NR>1 {print $5}' | cut -d: -f1 | sort -u | grep -c . 2>/dev/null || echo 0)

  echo -e "${WHITE_BOLD}Appareils connectés :${RESET}"
  echo -e "  • Connexions actives sur 8443/8880 : [${YELLOW}${total_conn}${RESET}]"
}

print_consommation_xray() {
  local VN_INTERFACE
  VN_INTERFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1);exit}}}')

  if [[ -z "$VN_INTERFACE" ]]; then
    echo -e "${WHITE_BOLD}Consommation Xray :${RESET}"
    echo -e "  ${RED}⚠️  Interface réseau introuvable.${RESET}"
    return
  fi

  local vnstat_json
  vnstat_json=$(vnstat -i "$VN_INTERFACE" --json 2>/dev/null)

  if [[ -z "$vnstat_json" ]] || ! echo "$vnstat_json" | jq . >/dev/null 2>&1; then
    echo -e "${WHITE_BOLD}Consommation Xray :${RESET}"
    echo -e "  ${RED}⚠️  vnstat indisponible ou pas encore de données pour ${VN_INTERFACE}.${RESET}"
    return
  fi

  # vnstat 2.x : rx/tx en KiB → *1024 pour obtenir des octets → /1073741824 pour Go
  local day_count month_count
  day_count=$(echo   "$vnstat_json" | jq '.interfaces[0].traffic.day   | length' 2>/dev/null || echo 0)
  month_count=$(echo "$vnstat_json" | jq '.interfaces[0].traffic.month | length' 2>/dev/null || echo 0)

  local today_gb="0.00" month_gb="0.00"

  if (( day_count > 0 )); then
    today_gb=$(echo "$vnstat_json" | jq -r '
      ( .interfaces[0].traffic.day[0].rx
      + .interfaces[0].traffic.day[0].tx ) * 1024
      | . / 1073741824
      | (. * 100 | round) / 100
    ' 2>/dev/null || echo "0.00")
  fi

  if (( month_count > 0 )); then
    month_gb=$(echo "$vnstat_json" | jq -r '
      ( .interfaces[0].traffic.month[0].rx
      + .interfaces[0].traffic.month[0].tx ) * 1024
      | . / 1073741824
      | (. * 100 | round) / 100
    ' 2>/dev/null || echo "0.00")
  fi

  echo -e "${WHITE_BOLD}Consommation Xray :${RESET}"
  echo -e "  • Aujourd'hui : [${GREEN}${today_gb} Go${RESET}]"
  echo -e "  • Ce mois     : [${GREEN}${month_gb} Go${RESET}]"
}

afficher_xray_actifs() {
  if ! systemctl is-active --quiet xray; then
    echo -e "${RED}Service Xray non actif.${RESET}"
    return
  fi
  local protos
  protos=$(jq -r '.inbounds[].protocol' "$CONFIG_FILE" 2>/dev/null | sort -u | paste -sd ", ")
  echo -e "${WHITE_BOLD}Tunnels actifs :${RESET}"
  echo -e " ${GREEN}•${RESET} Port(s) TLS     : [${YELLOW}8443${RESET}]  – Protocoles [${MAGENTA}${protos}${RESET}]"
  echo -e " ${GREEN}•${RESET} Port(s) Non-TLS : [${YELLOW}8880${RESET}]  – Protocoles [${MAGENTA}${protos}${RESET}]"
}

show_menu() {
  echo -e "${CYAN}──────────────────────────────────────────────────────────${RESET}"
  echo -e "${BOLD}${YELLOW}[01]${RESET} Installer Xray"
  echo -e "${BOLD}${YELLOW}[02]${RESET} Créer utilisateur VMess"
  echo -e "${BOLD}${YELLOW}[03]${RESET} Créer utilisateur VLESS"
  echo -e "${BOLD}${YELLOW}[04]${RESET} Créer utilisateur Trojan"
  echo -e "${BOLD}${YELLOW}[05]${RESET} Consommation Xray en Go (par utilisateur)"
  echo -e "${BOLD}${YELLOW}[06]${RESET} Supprimer utilisateur Xray"
  echo -e "${BOLD}${YELLOW}[07]${RESET} Désinstallation complète Xray"
  echo -e "${BOLD}${RED}[00]${RESET} Quitter"
  echo -e "${CYAN}──────────────────────────────────────────────────────────${RESET}"
  echo -ne "${BOLD}${YELLOW}Choix → ${RESET}"
  read -r choice
}

load_user_data() {
  if [[ -f "$USERS_FILE" ]]; then
    VMESS=$(jq  -c '.vmess  // []' "$USERS_FILE")
    VLESS=$(jq  -c '.vless  // []' "$USERS_FILE")
    TROJAN=$(jq -c '.trojan // []' "$USERS_FILE")
  else
    VMESS="[]"; VLESS="[]"; TROJAN="[]"
  fi
}

count_users() {
    local vmess_count vless_count trojan_count
    vmess_count=$(jq  '.vmess  | length // 0' "$USERS_FILE")
    vless_count=$(jq  '.vless  | length // 0' "$USERS_FILE")
    trojan_count=$(jq '.trojan | length // 0' "$USERS_FILE")
    echo $(( vmess_count + vless_count + trojan_count ))
}

safe_write() {
    local tmp_file="$1" dest_file="$2"
    if jq . "$tmp_file" > /dev/null 2>&1; then
        mv "$tmp_file" "$dest_file"
    else
        echo -e "${RED}❌ JSON invalide — abandon de l'écriture dans $dest_file.${RESET}"
        rm -f "$tmp_file"
        return 1
    fi
}

# ============================================================
# CRÉATION UTILISATEUR (vmess / vless / trojan)
# ============================================================
create_config() {
  local proto=$1 name=$2 days=$3 limit=$4

  if [[ -z "$DOMAIN" ]]; then
      if [[ -f /etc/xray/domain ]]; then
          DOMAIN=$(cat /etc/xray/domain)
      else
          echo -e "${RED}⚠️ Domaine non défini.${RESET}"
          return 1
      fi
  fi

  local port_tls=8443 port_ntls=8880 port_grpc_tls=8443
  local path_ws_tls path_ws_ntls path_grpc

  case "$proto" in
    vmess)  path_ws_tls="/vmess-tls";  path_ws_ntls="/vmess-ntls";  path_grpc="vmess-grpc"  ;;
    vless)  path_ws_tls="/vless-tls";  path_ws_ntls="/vless-ntls";  path_grpc="vless-grpc"  ;;
    trojan) path_ws_tls="/trojan-tls"; path_ws_ntls="/trojan-ntls"; path_grpc="trojan-grpc" ;;
    *) echo -e "${RED}Protocole inconnu : $proto${RESET}"; return 1 ;;
  esac

  local uuid tag exp_date_iso
  uuid=$(cat /proc/sys/kernel/random/uuid)
  tag="${proto}_${name}_${uuid:0:8}"
  exp_date_iso=$(date -d "+$days days" +"%Y-%m-%d")

  # ── users.json : s'assurer que la clé existe ────────────────────────────
  if ! jq -e ".${proto}" "$USERS_FILE" >/dev/null 2>&1; then
    local tmp_init
    tmp_init=$(mktemp /tmp/users.XXXXXX)
    jq ".${proto} = []" "$USERS_FILE" > "$tmp_init"
    safe_write "$tmp_init" "$USERS_FILE" || return 1
  fi

  local tmp_users
  tmp_users=$(mktemp /tmp/users.XXXXXX)
  jq --arg id   "$uuid"         \
     --arg name "$name"         \
     --arg tag  "$tag"          \
     --arg exp  "$exp_date_iso" \
     --argjson lim "$limit"     \
     ".${proto} += [{
        \"uuid\":     \$id,
        \"email\":    \$tag,
        \"name\":     \$name,
        \"tag\":      \$tag,
        \"limit_gb\": \$lim,
        \"used_gb\":  0,
        \"expire\":   \$exp
     }]" "$USERS_FILE" > "$tmp_users"
  safe_write "$tmp_users" "$USERS_FILE" || return 1

  # ── config.json ─────────────────────────────────────────────────────────
  local tmp_config
  tmp_config=$(mktemp /tmp/config.XXXXXX)
  case "$proto" in
    vmess)
      jq --arg id "$uuid" --arg tag "$tag" \
         '(.inbounds[] | select(.protocol=="vmess") | .settings.clients //= []) += [{"id":$id,"alterId":0,"email":$tag}]' \
         "$CONFIG_FILE" > "$tmp_config"
      ;;
    vless)
      jq --arg id "$uuid" --arg tag "$tag" \
         '(.inbounds[] | select(.protocol=="vless") | .settings.clients) += [{"id":$id,"email":$tag}]' \
         "$CONFIG_FILE" > "$tmp_config"
      ;;
    trojan)
      # Trojan : password = uuid (pratique standard), email = tag pour les stats
      jq --arg pw "$uuid" --arg tag "$tag" \
         '(.inbounds[] | select(.protocol=="trojan") | .settings.clients //= []) += [{"password":$pw,"email":$tag}]' \
         "$CONFIG_FILE" > "$tmp_config"
      ;;
  esac
  safe_write "$tmp_config" "$CONFIG_FILE" || return 1

  # ── Liens de connexion ───────────────────────────────────────────────────
  local link_tls link_ntls link_grpc

  case "$proto" in
    vmess)
      link_tls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_tls\",\"id\":\"$uuid\",\"aid\":0,\"net\":\"ws\",\"type\":\"none\",\"host\":\"$DOMAIN\",\"path\":\"$path_ws_tls\",\"tls\":\"tls\",\"sni\":\"$DOMAIN\"}" | base64 -w0)"
      link_ntls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_ntls\",\"id\":\"$uuid\",\"aid\":0,\"net\":\"ws\",\"type\":\"none\",\"host\":\"$DOMAIN\",\"path\":\"$path_ws_ntls\",\"tls\":\"none\"}" | base64 -w0)"
      link_grpc="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_tls\",\"id\":\"$uuid\",\"aid\":0,\"net\":\"grpc\",\"type\":\"none\",\"host\":\"$DOMAIN\",\"path\":\"vmess-grpc\",\"tls\":\"tls\",\"sni\":\"$DOMAIN\"}" | base64 -w0)"
      ;;
    vless)
      link_tls="vless://$uuid@$DOMAIN:$port_tls?security=tls&type=ws&path=$path_ws_tls&host=$DOMAIN&sni=$DOMAIN#$name"
      link_ntls="vless://$uuid@$DOMAIN:$port_ntls?security=none&type=ws&path=$path_ws_ntls&host=$DOMAIN#$name"
      link_grpc="vless://$uuid@$DOMAIN:$port_grpc_tls?mode=grpc&security=tls&serviceName=$path_grpc#$name"
      ;;
    trojan)
      # Trojan WS TLS  (port 8443)
      link_tls="trojan://${uuid}@${DOMAIN}:${port_tls}?security=tls&type=ws&path=${path_ws_tls}&host=${DOMAIN}&sni=${DOMAIN}#${name}-WS-TLS"
      # Trojan WS non-TLS (port 8880)
      link_ntls="trojan://${uuid}@${DOMAIN}:${port_ntls}?security=none&type=ws&path=${path_ws_ntls}&host=${DOMAIN}#${name}-WS-NTLS"
      # Trojan gRPC TLS (port 8443)
      link_grpc="trojan://${uuid}@${DOMAIN}:${port_grpc_tls}?security=tls&type=grpc&serviceName=${path_grpc}&sni=${DOMAIN}#${name}-gRPC-TLS"
      ;;
  esac

  echo "$uuid|$exp_date_iso" >> /etc/xray/users_expiry.list

  echo
  echo -e "${CYAN}==============================${RESET}"
  echo -e "${BOLD}🧩 ${proto^^} – $name${RESET}"
  echo -e "${CYAN}==============================${RESET}"
  echo -e "${YELLOW}📄 Utilisateur :${RESET} $name"
  echo -e "${GREEN}➤ Ports :${RESET} TLS [$port_tls] | Non-TLS [$port_ntls] | gRPC [$port_grpc_tls]"
  echo -e "${GREEN}➤ UUID / Password :${RESET} $uuid"
  echo -e "${GREEN}➤ Paths WS :${RESET} TLS [$path_ws_tls] | Non-TLS [$path_ws_ntls]"
  echo -e "${GREEN}➤ gRPC ServiceName :${RESET} $path_grpc"
  echo -e "${GREEN}➤ Domaine :${RESET} $DOMAIN"
  echo -e "${GREEN}➤ Limite Go :${RESET} $limit Go"
  echo -e "${GREEN}➤ Expiration :${RESET} $exp_date_iso"
  echo
  echo -e "${CYAN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${RESET}"
  [[ -n "$link_tls" ]]  && echo -e "${CYAN}┃ TLS WS      : ${GREEN}$link_tls${RESET}"
  [[ -n "$link_ntls" ]] && echo -e "${CYAN}┃ Non-TLS WS  : ${GREEN}$link_ntls${RESET}"
  [[ -n "$link_grpc" ]] && echo -e "${CYAN}┃ gRPC TLS    : ${GREEN}$link_grpc${RESET}"
  echo -e "${CYAN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${RESET}"
  echo

  systemctl restart xray
}

# ============================================================
# CONSOMMATION XRAY PAR UTILISATEUR — via API stats (port 10085)
# ============================================================
afficher_quota_par_utilisateur() {
  local api_addr="127.0.0.1:10085"
  local xray_bin="/usr/local/bin/xray"

  if ! systemctl is-active --quiet xray; then
    echo -e "${RED}❌ Service Xray non actif.${RESET}"
    return 1
  fi
  if [[ ! -x "$xray_bin" ]]; then
    echo -e "${RED}❌ Binaire Xray introuvable : $xray_bin${RESET}"
    return 1
  fi
  if [[ ! -f "$USERS_FILE" ]]; then
    echo -e "${RED}❌ Fichier users.json introuvable.${RESET}"
    return 1
  fi

  # Requête à l'API stats Xray
  # statsquery retourne du texte ligne par ligne :
  # stat: <  name: "user>>>tag>>>traffic>>>uplink"  value: 12345  >
  # On parse directement avec grep/awk pour éviter les dépendances jq sur ce format texte
  local raw_stats
  raw_stats=$("$xray_bin" api statsquery --server="$api_addr" --pattern="user>>>" 2>/dev/null)

  if [[ -z "$raw_stats" ]]; then
    # Tentative sans filtre si la version ne supporte pas --pattern
    raw_stats=$("$xray_bin" api statsquery --server="$api_addr" 2>/dev/null)
  fi

  echo
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "       ${BOLD}${MAGENTA}Consommation Xray par utilisateur${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

  local printed=0

  for proto in vmess vless trojan; do
    # Récupérer la liste JSON des utilisateurs du protocole
    local users_json
    users_json=$(jq -c ".${proto} // [] | .[]" "$USERS_FILE" 2>/dev/null)
    [[ -z "$users_json" ]] && continue

    local first_in_proto=1

    while IFS= read -r user_obj; do
      local tag name expire limit_gb
      tag=$(echo "$user_obj"    | jq -r '.tag    // .email // ""')
      name=$(echo "$user_obj"   | jq -r '.name   // ""')
      expire=$(echo "$user_obj" | jq -r '.expire // "N/A"')
      limit_gb=$(echo "$user_obj" | jq -r '.limit_gb // 0')

      [[ -z "$tag" ]] && continue
      [[ -z "$name" ]] && name="$tag"

      # ── Lecture uplink / downlink depuis l'API ─────────────────────────
      # Format texte retourné par xray api statsquery :
      #   stat: <
      #     name: "user>>>email@tag>>>traffic>>>uplink"
      #     value: 1234567
      #   >
      local up_bytes=0 down_bytes=0 tmp_val

      # Extraire la valeur après avoir trouvé la bonne ligne name
      # On lit bloc par bloc : dès qu'on voit le tag + uplink/downlink on prend la valeur suivante
      if [[ -n "$raw_stats" ]]; then
        # uplink
        tmp_val=$(echo "$raw_stats" | awk -v tag="user>>>$tag>>>traffic>>>uplink" '
          $0 ~ "name: \"" tag "\"" { found=1; next }
          found && /value:/ { gsub(/[^0-9]/, "", $2); print $2; found=0 }
        ')
        [[ "$tmp_val" =~ ^[0-9]+$ ]] && up_bytes="$tmp_val"

        # downlink
        tmp_val=$(echo "$raw_stats" | awk -v tag="user>>>$tag>>>traffic>>>downlink" '
          $0 ~ "name: \"" tag "\"" { found=1; next }
          found && /value:/ { gsub(/[^0-9]/, "", $2); print $2; found=0 }
        ')
        [[ "$tmp_val" =~ ^[0-9]+$ ]] && down_bytes="$tmp_val"
      fi

      # ── Conversion octets → Go ─────────────────────────────────────────
      local up_gb down_gb total_gb total_bytes
      total_bytes=$(( up_bytes + down_bytes ))
      up_gb=$(awk    -v b="$up_bytes"    'BEGIN {printf "%.3f", b / 1073741824}')
      down_gb=$(awk  -v b="$down_bytes"  'BEGIN {printf "%.3f", b / 1073741824}')
      total_gb=$(awk -v b="$total_bytes" 'BEGIN {printf "%.3f", b / 1073741824}')

      # ── Barre de progression quota ─────────────────────────────────────
      local bar_str
      if (( limit_gb > 0 )); then
        local pct filled empty
        pct=$(awk -v t="$total_gb" -v l="$limit_gb" 'BEGIN {v=int(t*100/l); if(v>100)v=100; print v}')
        filled=$(( pct * 20 / 100 ))
        empty=$(( 20 - filled ))
        bar_str="["
        for (( i=0; i<filled; i++ )); do bar_str+="█"; done
        for (( i=0; i<empty;  i++ )); do bar_str+="░"; done

        local color_bar
        if   (( pct >= 90 )); then color_bar="$RED"
        elif (( pct >= 70 )); then color_bar="$YELLOW"
        else                       color_bar="$GREEN"
        fi
        bar_str+="${RESET}] ${color_bar}${pct}%${RESET}"
        bar_str="${color_bar}${bar_str}"
      else
        bar_str="${YELLOW}(pas de limite)${RESET}"
      fi

      # ── Affichage ──────────────────────────────────────────────────────
      if (( first_in_proto )); then
        echo
        echo -e "  ${BOLD}${CYAN}── ${proto^^} ──────────────────────────────────────────${RESET}"
        first_in_proto=0
      fi

      echo -e "  ${BOLD}${WHITE_BOLD}${name}${RESET}  ${MAGENTA}[${tag}]${RESET}"
      echo -e "    ↑ Upload   : ${GREEN}${up_gb} Go${RESET}"
      echo -e "    ↓ Download : ${GREEN}${down_gb} Go${RESET}"
      echo -e "    ∑ Total    : ${YELLOW}${total_gb} Go${RESET} / ${limit_gb} Go  ${bar_str}"
      echo -e "    📅 Expire  : ${expire}"
      echo -e "  ${CYAN}────────────────────────────────────────────────────${RESET}"
      (( printed++ ))

    done <<< "$users_json"
  done

  if (( printed == 0 )); then
    echo -e "  ${YELLOW}Aucun utilisateur enregistré dans users.json.${RESET}"
    if [[ -z "$raw_stats" ]]; then
      echo -e "  ${RED}⚠️  L'API stats n'a retourné aucune donnée.${RESET}"
      echo -e "     Vérifiez que le port ${YELLOW}10085${RESET} est bien configuré dans config.json."
    fi
  else
    echo
    echo -e "  ${GREEN}✅ Total utilisateurs affichés : ${printed}${RESET}"
  fi
  echo
}

# ============================================================
# SUPPRESSION UTILISATEUR
# ============================================================
delete_user_by_number() {
    [[ ! -f "$USERS_FILE" ]] && {
        echo -e "${RED}Fichier users.json introuvable.${RESET}"
        return 1
    }

    local users=()
    local protos=()
    local names=()

    for proto in vmess vless trojan; do
      while IFS= read -r line; do
        local uuid uname
        uuid=$(echo "$line"  | jq -r '.uuid  // ""')
        uname=$(echo "$line" | jq -r '.name  // .email // .uuid')
        [[ -z "$uuid" ]] && continue
        users+=("$uuid")
        protos+=("$proto")
        names+=("$uname")
      done < <(jq -c ".${proto}[]?" "$USERS_FILE" 2>/dev/null)
    done

    if (( ${#users[@]} == 0 )); then
        echo -e "${RED}Aucun utilisateur Xray à supprimer.${RESET}"
        return 0
    fi

    echo
    echo -e "${YELLOW}Liste des utilisateurs Xray :${RESET}"
    for i in "${!users[@]}"; do
        echo -e "  ${BOLD}[$((i+1))]${RESET} ${protos[$i]^^} → ${names[$i]}  ${MAGENTA}(${users[$i]})${RESET}"
    done
    echo

    read -rp "Numéro à supprimer (0 pour annuler) : " num
    if ! [[ "$num" =~ ^[0-9]+$ ]] || (( num < 0 || num > ${#users[@]} )); then
        echo -e "${RED}Numéro invalide.${RESET}"
        return 1
    fi
    (( num == 0 )) && { echo "Suppression annulée."; return 0; }

    local idx=$(( num - 1 ))
    local sel_uuid="${users[$idx]}"
    local sel_proto="${protos[$idx]}"
    local sel_name="${names[$idx]}"

    cp "$USERS_FILE"  "${USERS_FILE}.bak"
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

    # Suppression users.json
    local tmp_users
    tmp_users=$(mktemp /tmp/users.XXXXXX)
    jq --arg u "$sel_uuid" --arg proto "$sel_proto" \
      '.[$proto] |= map(select(.uuid != $u))' \
      "$USERS_FILE" > "$tmp_users"
    safe_write "$tmp_users" "$USERS_FILE" || return 1

    # Suppression config.json
    local tmp_config
    tmp_config=$(mktemp /tmp/config.XXXXXX)
    if [[ "$sel_proto" == "trojan" ]]; then
      # Trojan identifié par password (= uuid)
      jq --arg pw "$sel_uuid" \
        '(.inbounds[] | select(.protocol=="trojan") | .settings.clients)
         |= map(select(.password != $pw))' \
        "$CONFIG_FILE" > "$tmp_config"
    else
      # VMess / VLESS identifiés par id
      jq --arg u "$sel_uuid" \
        '(.inbounds[] | select(.protocol=="vmess" or .protocol=="vless") | .settings.clients)
         |= map(select(.id != $u))' \
        "$CONFIG_FILE" > "$tmp_config"
    fi
    safe_write "$tmp_config" "$CONFIG_FILE" || return 1

    [[ -f /etc/xray/users_expiry.list ]] && sed -i "/^$sel_uuid|/d" /etc/xray/users_expiry.list

    systemctl restart xray
    echo -e "${GREEN}✅ Utilisateur supprimé : $sel_proto / $sel_name ($sel_uuid)${RESET}"
}

# ============================================================
# MAIN
# ============================================================
choice=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Charger le domaine depuis plusieurs sources
[[ -f /tmp/.xray_domain ]]    && DOMAIN=$(cat /tmp/.xray_domain)
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
      read -rp "Nom de l'utilisateur VMess : " conf_name
      read -rp "Durée (jours) : " days
      read -rp "Limite totale de Go (0 = illimité) : " limit
      [[ -n "$conf_name" && -n "$days" && -n "$limit" ]] && create_config "vmess" "$conf_name" "$days" "$limit"
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    3)
      read -rp "Nom de l'utilisateur VLESS : " conf_name
      read -rp "Durée (jours) : " days
      read -rp "Limite totale de Go (0 = illimité) : " limit
      [[ -n "$conf_name" && -n "$days" && -n "$limit" ]] && create_config "vless" "$conf_name" "$days" "$limit"
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    4)
      read -rp "Nom de l'utilisateur Trojan : " conf_name
      read -rp "Durée (jours) : " days
      read -rp "Limite totale de Go (0 = illimité) : " limit
      [[ -n "$conf_name" && -n "$days" && -n "$limit" ]] && create_config "trojan" "$conf_name" "$days" "$limit"
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    5)
      afficher_quota_par_utilisateur
      read -p "Appuyez sur Entrée pour revenir..."
      ;;
    6)
      delete_user_by_number
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    7)
      echo -e "${YELLOW}Désinstallation complète de Xray en cours...${RESET}"
      read -rp "Es-tu sûr de vouloir désinstaller Xray et Nginx ? (o/n) : " confirm
      case "$confirm" in
        [oO]|[yY]|[yY][eE][sS])
          echo -e "${GREEN}Arrêt des services...${RESET}"
          systemctl stop xray nginx 2>/dev/null || true
          systemctl disable xray nginx 2>/dev/null || true

          echo -e "${GREEN}Fermeture des ports utilisés...${RESET}"
          for port in 8880 8443; do
            lsof -i tcp:$port -t 2>/dev/null | xargs -r kill -9
          done

          echo -e "${GREEN}Suppression des fichiers et dossiers...${RESET}"
          rm -rf /etc/xray /var/log/xray /usr/local/bin/xray
          rm -f /etc/systemd/system/xray.service
          rm -f /etc/nginx/conf.d/xray.conf
          rm -f /etc/logrotate.d/xray
          rm -f /tmp/.xray_domain

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
