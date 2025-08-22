#!/bin/bash
# v2ray_slowdns.sh - Gestion utilisateurs compatible avec tunnel V2Ray SlowDNS

INSTALL_DIR="$HOME/Kighmu"
USERS_FILE="/etc/v2ray_slowdns/users.txt"
CONFIG_PATH="/usr/local/etc/v2ray_slowdns/config.json"
NS_FILE="/etc/slowdns/ns.txt"
PUB_KEY_FILE="/etc/slowdns/server.pub"
SERVICE_NAME="v2ray-slowdns"

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

# Vérifier que le fichier de config existe
if [[ ! -f "$CONFIG_PATH" ]]; then
  echo -e "${RED}Erreur : $CONFIG_PATH introuvable. Installe d'abord le tunnel V2Ray SlowDNS.${RESET}"
  exit 1
fi

# Créer le fichier users.txt si inexistant
mkdir -p "$(dirname "$USERS_FILE")"
touch "$USERS_FILE"

# Lire namespace SlowDNS et clé publique
NS=$( [[ -f "$NS_FILE" ]] && cat "$NS_FILE" || echo "inconnu" )
PUB_KEY=$( [[ -f "$PUB_KEY_FILE" ]] && cat "$PUB_KEY_FILE" || echo "inconnue" )

restart_service() {
  sudo systemctl restart "$SERVICE_NAME"
  sleep 2
  if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "${RED}Erreur : le service V2Ray ne démarre pas. Vérifie config.json${RESET}"
    exit 1
  fi
}

# Créer clients si absent
jq 'if .inbounds[0].settings.clients == null then .inbounds[0].settings.clients = [] else . end' "$CONFIG_PATH" > tmp && mv tmp "$CONFIG_PATH"

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
            user_uuid=$(cat /proc/sys/kernel/random/uuid)

            # Ajouter utilisateur dans users.txt
            echo "$username:$duration:$limit:$domain:$expiry:$user_uuid:$NS:$PUB_KEY" >> "$USERS_FILE"

            # Ajouter utilisateur dans config.json
            tmp=$(mktemp)
            jq ".inbounds[0].settings.clients += [{\"id\":\"$user_uuid\",\"alterId\":0,\"email\":\"$username\"}]" "$CONFIG_PATH" > "$tmp" && mv "$tmp" "$CONFIG_PATH"

            restart_service

            # Extraire infos pour vmess
            PORT=$(jq -r '.inbounds[0].port' "$CONFIG_PATH")
            WS_PATH=$(jq -r '.inbounds[0].streamSettings.wsSettings.path' "$CONFIG_PATH")
            vmess_link=$(echo -n "{\"v\":\"2\",\"ps\":\"$username\",\"add\":\"$domain\",\"port\":\"$PORT\",\"id\":\"$user_uuid\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$domain\",\"path\":\"$WS_PATH\",\"tls\":\"none\"}" | base64 -w0)
            vmess_link="vmess://$vmess_link"

            clear
            echo -e "*NOUVEL UTILISATEUR V2RAY SLOWDNS CRÉÉ*"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "DOMAIN        : $domain"
            echo "UTILISATEUR   : $username"
            echo "UUID          : $user_uuid"
            echo "LIMITE        : $limit"
            echo "DATE EXPIRÉE  : $expiry"
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
                user_uuid=$(grep "^$username:" "$USERS_FILE" | cut -d: -f6)
                # Supprimer du fichier users.txt
                grep -v "^$username:" "$USERS_FILE" > "$USERS_FILE.tmp" && mv "$USERS_FILE.tmp" "$USERS_FILE"
                # Supprimer du config.json
                tmp=$(mktemp)
                jq "(.inbounds[0].settings.clients) |= map(select(.id != \"$user_uuid\"))" "$CONFIG_PATH" > "$tmp" && mv "$tmp" "$CONFIG_PATH"
                restart_service
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
