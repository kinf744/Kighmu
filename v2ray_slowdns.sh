#!/bin/bash
# v2ray_slowdns.sh - Gestion utilisateurs compatible avec tunnel V2Ray SlowDNS

INSTALL_DIR="$HOME/Kighmu"
USERS_FILE="/etc/v2ray_slowdns/users.txt"
CONFIG_PATH="/usr/local/etc/v2ray_slowdns/config.json"
NS_FILE="/etc/slowdns/ns.txt"
PUB_KEY_FILE="/etc/slowdns/server.pub"

# Couleurs
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

# Extraction correcte avec indexation tableau
UUID=$(jq -r '.inbounds[0].settings.clients.id' "$CONFIG_PATH")
PORT=$(jq -r '.inbounds.port' "$CONFIG_PATH")
WS_PATH=$(jq -r '.inbounds.streamSettings.wsSettings.path' "$CONFIG_PATH")

if [[ -z "$UUID" || -z "$PORT" || -z "$WS_PATH" || "$UUID" == "null" || "$PORT" == "null" || "$WS_PATH" == "null" ]]; then
  echo -e "${RED}Impossible d'extraire UUID, PORT ou WS PATH depuis $CONFIG_PATH. Vérifie la configuration.${RESET}"
  exit 1
fi

# Lire namespace SlowDNS et clé publique
if [[ -f "$NS_FILE" ]]; then
  NS=$(cat "$NS_FILE")
else
  echo -e "${RED}Attention : fichier namespace $NS_FILE introuvable.${RESET}"
  NS="inconnu"
fi

if [[ -f "$PUB_KEY_FILE" ]]; then
  PUB_KEY=$(cat "$PUB_KEY_FILE")
else
  echo -e "${RED}Attention : fichier clé publique $PUB_KEY_FILE introuvable.${RESET}"
  PUB_KEY="inconnue"
fi

mkdir -p "$(dirname "$USERS_FILE")"
touch "$USERS_FILE"

while true; do
    clear
    echo -e "${BOLD}${YELLOW}MENU V2RAY SLOWDNS${RESET}"
    echo -e "${GREEN}1) Installer le tunnel V2Ray SlowDNS${RESET}"
    echo -e "${GREEN}2) Créer un utilisateur${RESET}"
    echo -e "${RED}3) Supprimer un utilisateur${RESET}"
    echo -e "4) Retour au menu précédent"
    echo ""

    read -p "Votre choix : " choix

    case $choix in
        1)
            if [[ -x "$INSTALL_DIR/v2ray_slowdns_install.sh" ]]; then
                bash "$INSTALL_DIR/v2ray_slowdns_install.sh"
            else
                echo -e "${RED}Script d'installation introuvable.${RESET}"
            fi
            read -p "Appuyez sur Entrée pour continuer..."
            ;;
        2)
            read -p "Nom de l'utilisateur : " username
            if grep -q "^$username:" "$USERS_FILE"; then
                echo -e "${RED}Utilisateur déjà existant.${RESET}"
                read -p "Appuyez sur Entrée pour continuer..."
                continue
            fi
            read -p "Durée (jours) : " duration
            read -p "Limite (ex: 7 connexions) : " limit
            read -p "Nom de domaine : " domain

            expiry=$(date -d "+$duration days" +"%Y-%m-%d")

            echo "$username:$duration:$limit:$domain:$expiry:$UUID:$PORT:$NS:$PUB_KEY" >> "$USERS_FILE"

            vmess_link=$(echo -n "{\"v\":\"2\",\"ps\":\"V2Ray SlowDNS\",\"add\":\"$domain\",\"port\":\"$PORT\",\"id\":\"$UUID\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$domain\",\"path\":\"$WS_PATH\",\"tls\":\"none\",\"mux\":true}" | base64 -w0)
            vmess_link="vmess://$vmess_link"

            clear
            echo -e "*NOUVEAU UTILISATEUR V2RAYDNSTT CRÉÉ*"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "DOMAIN        : $domain"
            echo "UTILISATEUR   : $username"
            echo "LIMITE       : $limit"
            echo "DATE EXPIRÉE : $expiry"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "$vmess_link"
            echo ""
            echo "━━━━━━━━━━━  CONFIG SLOWDNS  ━━━━━━━━━━━"
            echo "Pub KEY : $PUB_KEY"
            echo "NameServer (NS) : $NS"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            read -p "Appuyez sur Entrée pour continuer..."
            ;;
        3)
            read -p "Nom de l'utilisateur à supprimer : " username
            if grep -q "^$username:" "$USERS_FILE"; then
                grep -v "^$username:" "$USERS_FILE" > "$USERS_FILE.tmp" && mv "$USERS_FILE.tmp" "$USERS_FILE"
                echo -e "${GREEN}Utilisateur $username supprimé avec succès.${RESET}"
            else
                echo -e "${RED}Utilisateur non trouvé.${RESET}"
            fi
            read -p "Appuyez sur Entrée pour continuer..."
            ;;
        4)
            echo -e "${YELLOW}Retour au menu précédent...${RESET}"
            sleep 1
            break
            ;;
        *)
            echo -e "${RED}Choix invalide.${RESET}"
            read -p "Appuyez sur Entrée pour continuer..."
            ;;
    esac
done
