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

  # Suppression dans TLS et NTLS pour le même protocole
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
    # WS TLS
    jq --arg proto "$sel_proto" --arg id "$sel_uuid" '
      (.inbounds[] | select(.protocol == $proto and .streamSettings.security == "tls") | .settings.clients) |= map(select(.id != $id))
    ' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

    # WS Non-TLS
    jq --arg proto "$sel_proto" --arg id "$sel_uuid" '
      (.inbounds[] | select(.protocol == $proto and .streamSettings.security == "none") | .settings.clients) |= map(select(.id != $id))
    ' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

    # TCP TLS & gRPC TLS
    jq --arg proto "$sel_proto" --arg id "$sel_uuid" '
      (.inbounds[] | select(.protocol == $proto and .streamSettings.network=="tcp") | .settings.clients) |= map(select(.id != $id)) |
      (.inbounds[] | select(.protocol == $proto and .streamSettings.network=="grpc") | .settings.clients) |= map(select(.id != $id))
    ' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
  else
    # Trojan (TLS WS, TCP TLS et gRPC TLS)
    jq --arg id "$sel_uuid" '
      (.inbounds[] | select(.protocol=="trojan") | .settings.clients) |= map(select(.password != $id))
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
