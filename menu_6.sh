#!/bin/bash

CONFIG_DIR="/usr/local/etc/xray"
CONFIG_FILE="$CONFIG_DIR/config.json"
DOMAIN=""

# Couleurs
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
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
  echo -e "${RED}[06]${RESET} Quitter"
  echo -e "${CYAN}+--------------------------------------------------+${RESET}"
  echo -ne "${BOLD}${YELLOW}Votre choix [1-6] : ${RESET}"
  read -r choice
}

generate_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  else
    cat /proc/sys/kernel/random/uuid
  fi
}

create_config() {
  local proto=$1
  local name=$2
  local days=$3

  if [[ -z "$DOMAIN" ]]; then
    echo -e "${RED}⚠️ Le nom de domaine n'est pas défini. Veuillez installer Xray d'abord.${RESET}"
    return
  fi

  local uuid=$(generate_uuid)
  local trojan_pass=$(openssl rand -base64 16)
  local expiry_date=$(date -d "+$days days" +"%d/%m/%Y")
  local port_tls=443
  local port_ntls=80
  local path_ws=""
  local grpc_name=""
  local link_tls=""
  local link_ntls=""
  local link_grpc=""
  local encryption="none"

  case "$proto" in
    vmess)
      path_ws="/vmessws"
      grpc_name="vmess-grpc"
      link_tls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_tls\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"$path_ws\",\"tls\":\"tls\"}" | base64 -w0)"
      link_ntls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_ntls\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"$path_ws\",\"tls\":\"\"}" | base64 -w0)"
      link_grpc="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_tls\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"grpc\",\"type\":\"none\",\"host\":\"$DOMAIN\",\"path\":\"\",\"tls\":\"tls\",\"serviceName\":\"$grpc_name\"}" | base64 -w0)"
      ;;
    vless)
      path_ws="/vlessws"
      grpc_name="vless-grpc"
      link_tls="vless://$uuid@$DOMAIN:$port_tls?path=$path_ws&security=tls&encryption=$encryption&type=ws#$name"
      link_ntls="vless://$uuid@$DOMAIN:$port_ntls?path=$path_ws&encryption=$encryption&type=ws#$name"
      link_grpc="vless://$uuid@$DOMAIN:$port_tls?mode=gun&security=tls&encryption=$encryption&type=grpc&serviceName=$grpc_name&sni=$DOMAIN#$name"
      ;;
    trojan)
      path_ws="/trojanws"
      grpc_name="trojan-grpc"
      link_tls="trojan://$trojan_pass@$DOMAIN:$port_tls?security=tls&type=ws&path=$path_ws#$name"
      link_ntls="trojan://$trojan_pass@$DOMAIN:$port_ntls?type=ws&path=$path_ws#$name"
      link_grpc="trojan://$trojan_pass@$DOMAIN:$port_tls?mode=gun&security=tls&type=grpc&serviceName=$grpc_name&sni=$DOMAIN#$name"
      ;;
  esac

  echo
  echo -e "${CYAN}==================================================${RESET}"
  echo -e "${BOLD}${MAGENTA}📄 Configuration $proto générée pour l'utilisateur : $name${RESET}"
  echo -e "${CYAN}--------------------------------------------------${RESET}"
  echo -e "${YELLOW}➤ UUID / Mot de passe :${RESET}"
  echo -e "    UUID (VMESS/VLESS) : $uuid"
  if [[ "$proto" == "trojan" ]]; then
    echo -e "    Mot de passe Trojan : $trojan_pass"
  fi
  echo
  echo -e "${YELLOW}➤ Durée de validité :${RESET} $days jours (expire le $expiry_date)"
  echo -e "➤ Ports utilisés : TLS=$port_tls, Non-TLS=$port_ntls"
  echo
  echo -e "${YELLOW}➤ Liens de configuration :${RESET}"
  echo -e "  • TLS : $link_tls"
  echo -e "  • Non-TLS : $link_ntls"
  echo -e "  • GRPC : $link_grpc"
  echo -e "${CYAN}==================================================${RESET}"
  echo
}

choice=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Charger automatiquement le domaine utilisé par Xray s’il existe
if [[ -f /tmp/.xray_domain ]]; then
  DOMAIN=$(cat /tmp/.xray_domain)
fi

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
      read -p "Appuyez sur Entrée pour revenir au menu..."
      ;;
    2)
      read -rp "Nom de l'utilisateur VMESS : " conf_name
      read -rp "Durée de validité (jours) : " days
      [[ -n "$conf_name" && -n "$days" ]] && create_config "vmess" "$conf_name" "$days"
      read -p "Appuyez sur Entrée pour revenir au menu..."
      ;;
    3)
      read -rp "Nom de l'utilisateur VLESS : " conf_name
      read -rp "Durée de validité (jours) : " days
      [[ -n "$conf_name" && -n "$days" ]] && create_config "vless" "$conf_name" "$days"
      read -p "Appuyez sur Entrée pour revenir au menu..."
      ;;
    4)
      read -rp "Nom de l'utilisateur TROJAN : " conf_name
      read -rp "Durée de validité (jours) : " days
      [[ -n "$conf_name" && -n "$days" ]] && create_config "trojan" "$conf_name" "$days"
      read -p "Appuyez sur Entrée pour revenir au menu..."
      ;;
    5)
      read -rp "Entrez le nom exact de l'utilisateur Xray à supprimer : " del_name
      if [[ -n "$del_name" ]]; then
        read -rp "Confirmez la suppression de '$del_name' ? (oui/non) : " conf
        if [[ "$conf" =~ ^([oO][uU][iI]|[oO])$ ]]; then
          if [[ -f "$CONFIG_FILE" ]]; then
            sudo jq "del(.inbounds[].settings.clients[] | select(.email==\"$del_name\"))" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && sudo mv "$CONFIG_FILE.tmp" "$CONFIG_FILE" && echo -e "${GREEN}Utilisateur $del_name supprimé avec succès.${RESET}" || echo -e "${RED}Erreur lors de la suppression.${RESET}"
            sudo systemctl restart xray
          else
            echo -e "${RED}Fichier de configuration Xray introuvable.${RESET}"
          fi
        else
          echo -e "${YELLOW}Suppression annulée.${RESET}"
        fi
      fi
      read -p "Appuyez sur Entrée pour revenir au menu..."
      ;;
    6)
      echo -e "${RED}Quitter...${RESET}"
      rm -f /tmp/.xray_domain
      break
      ;;
    *)
      echo -e "${RED}Choix invalide, veuillez réessayer.${RESET}"
      sleep 2
      ;;
  esac
done
