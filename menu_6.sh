#!/bin/bash

CONFIG_DIR="/usr/local/etc/xray"
CONFIG_FILE="$CONFIG_DIR/config.json"
DOMAIN=""

print_header() {
  local width=50
  local text="Xray CONFIG INSTALLER"
  local border="+--------------------------------------------------+"

  echo "$border"
  local padding=$(( (width - ${#text}) / 2 ))
  printf "|%*s%s%*s|\n" $padding "" "$text" $padding ""
  echo "$border"
}

show_menu() {
  echo "Choisissez une action :"
  echo "1) Installer le Xray"
  echo "2) VMESS"
  echo "3) VLESS"
  echo "4) TROJAN"
  echo "5) Supprimer un utilisateur Xray"
  echo "6) Quitter"
  read -rp "Votre choix : " choice
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
    echo "⚠️ Le nom de domaine n'est pas défini. Veuillez installer Xray d'abord."
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
  echo "=================================================="
  echo "📄 Configuration $proto générée pour l'utilisateur : $name"
  echo "--------------------------------------------------"
  echo "➤ UUID / Mot de passe :"
  echo "    UUID (VMESS/VLESS) : $uuid"
  if [[ "$proto" == "trojan" ]]; then
    echo "    Mot de passe Trojan : $trojan_pass"
  fi
  echo
  echo "➤ Durée de validité : $days jours (expire le $expiry_date)"
  echo "➤ Ports utilisés : TLS=$port_tls, Non-TLS=$port_ntls"
  echo
  echo "➤ Liens de configuration :"
  echo "  • TLS :"
  echo "    $link_tls"
  echo
  echo "  • Non-TLS :"
  echo "    $link_ntls"
  echo
  echo "  • GRPC :"
  echo "    $link_grpc"
  echo "=================================================="
  echo
}

choice=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Charger domaine précédemment saisi
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
        echo "Nom de domaine $DOMAIN chargé automatiquement."
      else
        DOMAIN=""
        echo "Aucun domaine enregistré. Veuillez installer Xray d’abord."
      fi
      read -p "Appuyez sur Entrée pour revenir au menu..."
      ;;
    2)
      read -rp "Nom de l'utilisateur VMESS : " conf_name
      read -rp "Durée de validité (jours) : " days
      if [[ -z "$conf_name" || -z "$days" ]]; then
        echo "Nom ou durée invalide."
        read -p "Appuyez sur Entrée pour revenir au menu..."
      else
        create_config "vmess" "$conf_name" "$days"
        read -p "Appuyez sur Entrée pour revenir au menu..."
      fi
      ;;
    3)
      read -rp "Nom de l'utilisateur VLESS : " conf_name
      read -rp "Durée de validité (jours) : " days
      if [[ -z "$conf_name" || -z "$days" ]]; then
        echo "Nom ou durée invalide."
        read -p "Appuyez sur Entrée pour revenir au menu..."
      else
        create_config "vless" "$conf_name" "$days"
        read -p "Appuyez sur Entrée pour revenir au menu..."
      fi
      ;;
    4)
      read -rp "Nom de l'utilisateur TROJAN : " conf_name
      read -rp "Durée de validité (jours) : " days
      if [[ -z "$conf_name" || -z "$days" ]]; then
        echo "Nom ou durée invalide."
        read -p "Appuyez sur Entrée pour revenir au menu..."
      else
        create_config "trojan" "$conf_name" "$days"
        read -p "Appuyez sur Entrée pour revenir au menu..."
      fi
      ;;
    5)
      read -rp "Entrez le nom exact de l'utilisateur Xray à supprimer : " del_name
      if [[ -z "$del_name" ]]; then
        echo "Nom invalide. Aucune suppression effectuée."
      else
        read -rp "Confirmez-vous la suppression de l'utilisateur '$del_name' ? (oui/non) : " conf
        if [[ "$conf" =~ ^([oO][uU][iI]|[oO])$ ]]; then
          if [[ ! -f "$CONFIG_FILE" ]]; then
            echo "Fichier de configuration Xray introuvable."
          else
            sudo jq "del(.inbounds[].settings.clients[] | select(.email==\"$del_name\"))" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && sudo mv "$CONFIG_FILE.tmp" "$CONFIG_FILE" && echo "Utilisateur $del_name supprimé avec succès." || echo "Erreur lors de la suppression."
            sudo systemctl restart xray
          fi
        else
          echo "Suppression annulée."
        fi
      fi
      read -p "Appuyez sur Entrée pour revenir au menu..."
      ;;
    6)
      echo "Quitter..."
      rm -f /tmp/.xray_domain
      break
      ;;
    *)
      echo "Choix invalide, veuillez réessayer."
      sleep 2
      ;;
  esac
done
