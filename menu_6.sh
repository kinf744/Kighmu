#!/bin/bash

CONFIG_DIR="/usr/local/etc/xray"
CONFIG_FILE="$CONFIG_DIR/config.json"

EMAIL="votre-email@example.com"

apt update && apt install -y curl unzip sudo socat snapd jq
snap install core; snap refresh core
snap install --classic certbot
ln -sf /snap/bin/certbot /usr/bin/certbot

systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true

read -rp "Entrez le nom de domaine (ex: monsite.com) : " DOMAIN

CRT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

certbot certonly --standalone --non-interactive --agree-tos --email "$EMAIL" -d "$DOMAIN"

if [[ ! -f "$CRT_PATH" ]] || [[ ! -f "$KEY_PATH" ]]; then
  echo "Erreur : certificats TLS non trouvés, interrompu."
  exit 1
fi

if ! command -v xray >/dev/null 2>&1; then
  bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
fi

generate_uuid() {
  cat /proc/sys/kernel/random/uuid
}

print_header() {
  local width=44
  local text="Xray_CONFIG_INSTALLER"
  local border="+--------------------------------------------+"

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

create_config() {
  local proto=$1
  local name=$2
  local days=$3
  local expiry=$(date -d "+$days days" +"%Y-%m-%d")
  local id=$(generate_uuid)
  local trojan_pass=$(openssl rand -base64 16)
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
      link_tls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_tls\",\"id\":\"$id\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"$path_ws\",\"tls\":\"tls\"}" | base64 -w 0)"
      link_ntls="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_ntls\",\"id\":\"$id\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"$path_ws\",\"tls\":\"\"}" | base64 -w 0)"
      link_grpc="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$name\",\"add\":\"$DOMAIN\",\"port\":\"$port_tls\",\"id\":\"$id\",\"aid\":\"0\",\"net\":\"grpc\",\"type\":\"none\",\"host\":\"$DOMAIN\",\"path\":\"\",\"tls\":\"tls\",\"serviceName\":\"$grpc_name\"}" | base64 -w 0)"
      ;;
    vless)
      path_ws="/vlessws"
      grpc_name="vless-grpc"
      link_tls="vless://$id@$DOMAIN:$port_tls?path=$path_ws&security=tls&encryption=$encryption&type=ws#$name"
      link_ntls="vless://$id@$DOMAIN:$port_ntls?path=$path_ws&encryption=$encryption&type=ws#$name"
      link_grpc="vless://$id@$DOMAIN:$port_tls?mode=gun&security=tls&encryption=$encryption&type=grpc&serviceName=$grpc_name&sni=$DOMAIN#$name"
      ;;
    trojan)
      path_ws="/trojanws"
      grpc_name="trojan-grpc"
      link_tls="trojan://$trojan_pass@$DOMAIN:$port_tls?security=tls&type=ws&path=$path_ws#$name"
      link_ntls="trojan://$trojan_pass@$DOMAIN:$port_ntls?type=ws&path=$path_ws#$name"
      link_grpc="trojan://$trojan_pass@$DOMAIN:$port_tls?mode=gun&security=tls&type=grpc&serviceName=$grpc_name&sni=$DOMAIN#$name"
      ;;
  esac

  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" << EOF
{
  "log": { "loglevel": "info" },
  "inbounds": [
    {
      "port": $port_tls,
      "protocol": "$proto",
      "settings": {
        "clients": [ { "id": "$id", "password": "$trojan_pass", "email": "$name" } ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": { "certificates": [ { "certificateFile": "$CRT_PATH", "keyFile": "$KEY_PATH" } ] },
        "wsSettings": { "path": "$path_ws" }
      }
    },
    {
      "port": $port_ntls,
      "protocol": "$proto",
      "settings": {
        "clients": [ { "id": "$id", "password": "$trojan_pass", "email": "$name" } ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "$path_ws" }
      }
    },
    {
      "port": $port_tls,
      "protocol": "$proto",
      "settings": {
        "clients": [ { "id": "$id", "password": "$trojan_pass", "email": "$name" } ]
      },
      "streamSettings": {
        "network": "grpc",
        "security": "tls",
        "tlsSettings": { "certificates": [ { "certificateFile": "$CRT_PATH","keyFile": "$KEY_PATH" } ] },
        "grpcSettings": { "serviceName": "$grpc_name" }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom", "settings": {} }]
}
EOF

  systemctl restart xray

  echo
  echo "🧿Status Create $proto Success🧿"
  echo "☉——————————————————————————☉"
  echo "Remarks     : $name"
  echo "Domain      : $DOMAIN"
  echo "port TLS    : $port_tls"
  echo "Port NTLS   : $port_ntls"
  echo "User ID     : $id"
  echo "Encryption  : $encryption"
  echo "Path TLS    : $path_ws"
  echo "ServiceName : $grpc_name"
  echo "☉——————————————————————————☉"
  echo "🧿Link TLS    : $link_tls"
  echo "🧿Link NTLS   : $link_ntls"
  echo "🧿Link GRPC   : $link_grpc"
  echo "☉——————————————————————————☉"
  echo "Format OpenClash : https://$DOMAIN:81/$proto-$name.txt"
  echo "☉——————————————————————————☉"
  echo "Durée       : $days jours"
  echo "Créé le     : $(date +"%d %b, %Y")"
  echo "Expire le   : $expiry"
  echo "☉——————————————————————————☉"
  echo
}

choice=0
while true; do
  clear
  print_header
  show_menu
  case $choice in
    1)
      echo "Installation automatique de Xray en cours..."
      if ! command -v xray >/dev/null 2>&1; then
        bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
      else
        echo "Xray est déjà installé."
      fi
      read -p "Appuyez sur Entrée pour revenir au menu..."
      ;;
    2)
      read -rp "Entrez un nom pour cette configuration : " conf_name
      read -rp "Durée de validité (jours) : " days
      create_config "vmess" "$conf_name" "$days"
      ;;
    3)
      read -rp "Entrez un nom pour cette configuration : " conf_name
      read -rp "Durée de validité (jours) : " days
      create_config "vless" "$conf_name" "$days"
      ;;
    4)
      read -rp "Entrez un nom pour cette configuration : " conf_name
      read -rp "Durée de validité (jours) : " days
      create_config "trojan" "$conf_name" "$days"
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
      break
      ;;
    *)
      echo "Choix invalide"
      sleep 2
      ;;
  esac
done
