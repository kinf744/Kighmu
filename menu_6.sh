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
      echo -ne "${YELLOW}Voulez-vous créer un utilisateur Trojan avec TLS ? (o/n) : ${RESET}"
      read -r use_tls
      if [[ "$use_tls" == "o" || "$use_tls" == "O" ]]; then
        new_uuid=$(cat /proc/sys/kernel/random/uuid)
        jq --arg id "$new_uuid" '
          (.inbounds[] | select(.protocol=="trojan" and .streamSettings.security=="tls") | .settings.clients) += [{"password": $id}]
        ' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
        jq --arg id "$new_uuid" '.trojan_pass = $id' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
        link_tls="trojan://$new_uuid@$DOMAIN:$port_tls?security=tls&type=ws&path=/trojanws#$name"
      else
        new_uuid=$(cat /proc/sys/kernel/random/uuid)
        jq --arg id "$new_uuid" '
          (.inbounds[] | select(.protocol=="trojan" and .streamSettings.security=="none") | .settings.clients) += [{"password": $id}]
        ' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
        jq --arg id "$new_uuid" '.trojan_ntls_pass = $id' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
        link_ntls="trojan://$new_uuid@$DOMAIN:$port_ntls?type=ws&path=/trojanws#$name"
      fi
      ;;
    *)
      echo -e "${RED}Protocole inconnu.${RESET}"
      return 1
      ;;
  esac

  # Ajouter la date d'expiration dans users_expiry.list
  local exp_date_iso
  exp_date_iso=$(date -d "+$days days" +"%Y-%m-%d")
  touch /etc/xray/users_expiry.list
  chmod 600 /etc/xray/users_expiry.list
  echo "$new_uuid|$exp_date_iso" >> /etc/xray/users_expiry.list

  # Calcul date expiration
  local expiry_date
  expiry_date=$(date -d "+$days days" +"%d/%m/%Y")

  # Affichage config générée avec encadrement
  echo
  echo "========================="
  echo -e "🧩 ${proto^^}"
  echo "========================="
  echo -e "📄 Configuration $proto générée pour l'utilisateur : $name"
  echo "--------------------------------------------------"
  echo -e "➤ UUID / Mot de passe :"
  if [[ "$proto" == "trojan" ]]; then
    echo -e "    Mot de passe : $new_uuid"
  else
    echo -e "    UUID : $new_uuid"
  fi
  echo -e "➤ Durée de validité : $days jours (expire le $expiry_date)"
  echo
  echo -e "●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●"
  echo -e "┃ TLS  :"
  if [[ "$proto" == "trojan" ]]; then
    if [[ "$use_tls" == "o" || "$use_tls" == "O" ]]; then
      echo -e "┃ $link_tls"
      echo -e "┃"
      echo -e "┃ Non-TLS :"
      echo -e "┃ Aucun accès Non-TLS configuré"
    else
      echo -e "┃ Aucun accès TLS configuré"
      echo -e "┃"
      echo -e "┃ Non-TLS :"
      echo -e "┃ $link_ntls"
    fi
  else
    echo -e "┃ $link_tls"
    echo -e "┃"
    echo -e "┃ Non-TLS :"
    echo -e "┃ $link_ntls"
  fi
  echo -e "●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●"
  echo

  # Redémarrer Xray pour appliquer les changements
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

  # Nettoyer expiration dans users_expiry.list
  if [[ -f /etc/xray/users_expiry.list ]]; then
    grep -v "^$id|" /etc/xray/users_expiry.list > "$tmp_expiry" && mv "$tmp_expiry" /etc/xray/users_expiry.list
  fi

  systemctl restart xray
  echo -e "${GREEN}Utilisateur supprimé : protocole=$proto, ID=$id${RESET}"
}

choice=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -f /tmp/.xray_domain ]] && DOMAIN=$(cat /tmp/.xray_domain)
load_user_data

while true; do
  clear
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
      read -rp "Protocole (vmess, vless, trojan) : " proto
      read -rp "UUID ou mot de passe de l'utilisateur à supprimer : " id
      if [[ -n "$proto" && -n "$id" ]]; then
        delete_user "$proto" "$id"
      else
        echo -e "${RED}Paramètres invalides.${RESET}"
      fi
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    6)
      echo -e "${YELLOW}Désinstallation complète de Xray et Trojan-Go en cours...${RESET}"

      # Arrêter et désactiver les services
      systemctl stop xray trojan-go 2>/dev/null || true
      systemctl disable xray trojan-go 2>/dev/null || true

      # Tuer processus sur ports 80 et 8443
      for port in 80 8443; do
        lsof -i tcp:$port -t | xargs -r kill -9
        lsof -i udp:$port -t | xargs -r kill -9
      done

      # Supprimer fichiers et dossiers liés
      rm -rf /etc/xray /var/log/xray /usr/local/bin/xray /etc/systemd/system/xray.service
      rm -rf /etc/trojan-go /var/log/trojan-go /usr/local/bin/trojan-go /etc/systemd/system/trojan-go.service
      rm -f /tmp/.xray_domain /etc/xray/users_expiry.list /etc/xray/users.json /etc/xray/config.json

      # Reload systemd
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
