#!/bin/bash
# v2ray_slowdns.sh - Gestion utilisateurs V2Ray SlowDNS avec extraction fiable JSON via jq

USERS_FILE="/etc/v2ray_slowdns/users.txt"
CONFIG_PATH="/usr/local/etc/v2ray_slowdns/config.json"
NS_FILE="/etc/slowdns/ns.txt"
PUB_KEY_FILE="/etc/slowdns/server.pub"

# Couleurs pour l'affichage
RESET="\e[0m"
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BOLD="\e[1m"

# Vérifier que jq est installé
if ! command -v jq &> /dev/null; then
  echo -e "${RED}Erreur : 'jq' n'est pas installé. Installe-le avec : sudo apt-get install -y jq${RESET}"
  exit 1
fi

# Extraction via jq
UUID=$(jq -r '.inbounds[0].settings.clients.id' "$CONFIG_PATH")
PORT=$(jq -r '.inbounds.port' "$CONFIG_PATH")
WS_PATH=$(jq -r '.inbounds.streamSettings.wsSettings.path' "$CONFIG_PATH")

if [[ -z "$UUID" || -z "$PORT" || -z "$WS_PATH" || "$UUID" == "null" || "$PORT" == "null" || "$WS_PATH" == "null" ]]; then
  echo -e "${RED}Impossible d'extraire UUID, PORT ou WS PATH depuis le fichier $CONFIG_PATH. Vérifie la configuration.${RESET}"
  exit 1
fi

# Lire namespace SlowDNS et clé publique
if [[ -f "$NS_FILE" ]]; then
  NS=$(cat "$NS_FILE")
else
  echo -e "${RED}Attention : Fichier namespace $NS_FILE introuvable.${RESET}"
  NS="inconnu"
fi

if [[ -f "$PUB_KEY_FILE" ]]; then
  PUB_KEY=$(cat "$PUB_KEY_FILE")
else
  echo -e "${RED}Attention : Fichier clé publique $PUB_KEY_FILE introuvable.${RESET}"
  PUB_KEY="inconnue"
fi

# Préparation utilisateurs
mkdir -p "$(dirname "$USERS_FILE")"
touch "$USERS_FILE"

while true; do
  clear
  echo -e "${BOLD}${YELLOW}Gestion Utilisateurs V2Ray SlowDNS${RESET}"
  echo -e "${GREEN}1) Créer un utilisateur${RESET}"
  echo -e "${GREEN}2) Supprimer un utilisateur${RESET}"
  echo -e "${GREEN}3) Lister les utilisateurs${RESET}"
  echo -e "${RED}4) Quitter${RESET}"
  echo ""

  read -rp "Votre choix : " choice

  case $choice in
    1)
      read -rp "Nom de l'utilisateur : " username
      if grep -q "^$username:" "$USERS_FILE"; then
        echo -e "${RED}Utilisateur déjà existant.${RESET}"
        read -rp "Appuyez sur Entrée pour continuer..."
        continue
      fi
      read -rp "Durée (jours) : " duration
      read -rp "Limite (ex: 7 connexions) : " limit
      read -rp "Nom de domaine : " domain

      expiry=$(date -d "+$duration days" +"%Y-%m-%d")

      echo "$username:$duration:$limit:$domain:$expiry:$UUID:$PORT:$NS:$PUB_KEY" >> "$USERS_FILE"

      vmess_json=$(cat <<EOF
{
  "v":"2",
  "ps":"V2Ray SlowDNS - $username",
  "add":"$domain",
  "port":"$PORT",
  "id":"$UUID",
  "aid":"0",
  "net":"ws",
  "type":"none",
  "host":"$domain",
  "path":"$WS_PATH",
  "tls":"none",
  "mux":true
}
EOF
)
      vmess_link="vmess://$(echo -n "$vmess_json" | base64 -w0)"

      echo -e "${GREEN}Nouvel utilisateur créé :${RESET}"
      echo "Utilisateur: $username"
      echo "Domaine: $domain"
      echo "Limite: $limit"
      echo "Expire le: $expiry"
      echo "Lien VMess (copier dans HTTP Custom) :"
      echo "$vmess_link"
      echo ""
      echo "SlowDNS Config :"
      echo "Namespace (NS): $NS"
      echo "Clé Publique (Pub KEY): $PUB_KEY"
      read -rp "Appuyez sur Entrée pour continuer..."
      ;;
    2)
      read -rp "Nom de l'utilisateur à supprimer : " username
      if grep -q "^$username:" "$USERS_FILE"; then
        grep -v "^$username:" "$USERS_FILE" > "$USERS_FILE.tmp" && mv "$USERS_FILE.tmp" "$USERS_FILE"
        echo -e "${GREEN}Utilisateur $username supprimé avec succès.${RESET}"
      else
        echo -e "${RED}Utilisateur non trouvé.${RESET}"
      fi
      read -rp "Appuyez sur Entrée pour continuer..."
      ;;
    3)
      echo -e "${BOLD}Liste des utilisateurs V2Ray SlowDNS :${RESET}"
      if [[ ! -s "$USERS_FILE" ]]; then
        echo "Aucun utilisateur enregistré."
      else
        column -t -s ':' "$USERS_FILE"
      fi
      read -rp "Appuyez sur Entrée pour continuer..."
      ;;
    4)
      echo -e "${YELLOW}Sortie...${RESET}"
      exit 0
      ;;
    *)
      echo -e "${RED}Choix invalide.${RESET}"
      read -rp "Appuyez sur Entrée pour continuer..."
      ;;
  esac
done
