#!/bin/bash

CONFIG_DIR="/usr/local/etc/xray"
CONFIG_FILE="$CONFIG_DIR/config.json"

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

generate_uuid() {
  cat /proc/sys/kernel/random/uuid
}

create_config() {
  # Paramètres simplifiés pour exemple, adapte en fonction de ton script complet
  local proto=$1
  local name=$2
  local days=$3
  # Création de configs et redémarrage de xray ici...
  echo "Création de la configuration $proto pour $name valable $days jours..."
  # … Ton code détaillé ici
}

choice=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while true; do
  clear
  print_header
  show_menu
  case $choice in
    1)
      bash "$SCRIPT_DIR/xray_installe.sh"
      read -p "Appuyez sur Entrée pour revenir au menu..."
      ;;
    2)
      read -rp "Entrez un nom pour la configuration VMESS : " conf_name
      read -rp "Durée de validité (jours) : " days
      create_config "vmess" "$conf_name" "$days"
      read -p "Appuyez sur Entrée pour revenir au menu..."
      ;;
    3)
      read -rp "Entrez un nom pour la configuration VLESS : " conf_name
      read -rp "Durée de validité (jours) : " days
      create_config "vless" "$conf_name" "$days"
      read -p "Appuyez sur Entrée pour revenir au menu..."
      ;;
    4)
      read -rp "Entrez un nom pour la configuration TROJAN : " conf_name
      read -rp "Durée de validité (jours) : " days
      create_config "trojan" "$conf_name" "$days"
      read -p "Appuyez sur Entrée pour revenir au menu..."
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
      echo "Choix invalide, veuillez réessayer."
      sleep 2
      ;;
  esac
done
