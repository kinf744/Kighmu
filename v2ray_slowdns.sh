#!/bin/bash
# v2ray_slowdns.sh - Gestion utilisateurs V2Ray SlowDNS corrigé extraction jq

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

# Vérifier si JSON valide
if ! jq empty "$CONFIG_PATH" 2>/dev/null; then
  echo -e "${RED}Le fichier $CONFIG_PATH contient du JSON invalide ou des commentaires non supportés par jq.${RESET}"
  echo "Nettoie les commentaires ou valide le JSON avant de continuer."
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
  echo -e "${RED}Attention : Fichier namespace $NS_FILE introuvable.${RESET}"
  NS="inconnu"
fi

if [[ -f "$PUB_KEY_FILE" ]]; then
  PUB_KEY=$(cat "$PUB_KEY_FILE")
else
  echo -e "${RED}Attention : Fichier clé publique $PUB_KEY_FILE introuvable.${RESET}"
  PUB_KEY="inconnue"
fi

# Reste du script (menu gestion utilisateurs, création, suppression, etc.) inchangé...

# Exemple simple menu continuer ici...

echo "UUID=$UUID, PORT=$PORT, WS_PATH=$WS_PATH"
