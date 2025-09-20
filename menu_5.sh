#!/bin/bash

# Couleurs ANSI
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

V2RAY_CONFIG="/usr/local/etc/v2ray/config.json"
UUID_FILE="/usr/local/etc/v2ray/uuid.txt"
DOMAIN_FILE="/etc/slowdns/ns.conf"
SLOWDNS_KEY_PRIV="/etc/slowdns/server.key"
SLOWDNS_KEY_PUB="/etc/slowdns/server.pub"
SLOWDNS_BIN_CLIENT="/usr/local/bin/sldns-client"

V2RAY_PORT=10000
WS_PATH="/kighmu"

install_complete() {
    echo -e "${CYAN}Installation complète de V2Ray SlowDNS (sans TUN)...${RESET}"

    read -rp "Entrez le nom de domaine SlowDNS (ex: kiaje.kighmuop.dpdns.org) : " DOMAIN
    while [[ -z "$DOMAIN" ]]; do
        echo -e "${RED}Le nom de domaine ne peut pas être vide. Veuillez réessayer.${RESET}"
        read -rp "Entrez le nom de domaine SlowDNS (ex: kiaje.kighmuop.dpdns.org) : " DOMAIN
    done
    echo "$DOMAIN" > "$DOMAIN_FILE"

    if [[ ! -f $SLOWDNS_KEY_PUB ]]; then
        echo -e "${RED}Clé publique SlowDNS introuvable à $SLOWDNS_KEY_PUB.${RESET}"
        exit 1
    fi

    echo -e "${YELLOW}Mise à jour système et installation des dépendances...${RESET}"
    apt update && apt upgrade -y
    apt install -y curl unzip jq iproute2

    if ! command -v v2ray &>/dev/null; then
        echo -e "${YELLOW}Installation de V2Ray...${RESET}"
        curl -O https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh
        bash install-release.sh
    fi

    mkdir -p "$(dirname $V2RAY_CONFIG)"

    if [[ ! -f $UUID_FILE ]]; then
        UUID=$(uuidgen)
        echo "$UUID" > $UUID_FILE
    else
        UUID=$(cat $UUID_FILE)
    fi

    echo -e "${YELLOW}Création de la configuration V2Ray avec websocket et logs debug...${RESET}"

    cat > $V2RAY_CONFIG <<EOF
{
  "log": {
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log",
    "loglevel": "debug"
  },
  "inbounds": [
    {
      "port": $V2RAY_PORT,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "alterId": 0,
            "email": "slowdns-v2ray"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "$WS_PATH"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

    systemctl daemon-reload
    systemctl enable v2ray
    systemctl restart v2ray

    echo -e "${GREEN}Installation terminée. V2Ray écoute sur 127.0.0.1:$V2RAY_PORT avec ws path $WS_PATH${RESET}"
}

create_user() {
    if [[ ! -f $V2RAY_CONFIG ]]; then
        echo -e "${RED}Configuration V2Ray absente. Veuillez faire l'installation complète d'abord.${RESET}"
        return
    fi

    DOMAIN=$(cat $DOMAIN_FILE)
    if [[ ! -f $SLOWDNS_KEY_PUB ]]; then
        echo -e "${RED}Clé publique SlowDNS non trouvée.${RESET}"
        return
    fi

    read -p "Nom d'utilisateur : " USERNAME
    read -p "Durée (jours) : " DURATION

    EXPIRY_DATE=$(date -d "+$DURATION days" +"%Y-%m-%d")
    USER_UUID=$(uuidgen)

    jq ".inbounds[0].settings.clients += [{\"id\":\"$USER_UUID\",\"alterId\":0,\"email\":\"$USERNAME\"}]" "$V2RAY_CONFIG" > "${V2RAY_CONFIG}.tmp" && mv "${V2RAY_CONFIG}.tmp" "$V2RAY_CONFIG"
    systemctl restart v2ray

    VMESS_JSON=$(cat <<EOF
{
  "v":"2",
  "ps":"$USERNAME",
  "add":"$DOMAIN",
  "port":"$V2RAY_PORT",
  "id":"$USER_UUID",
  "aid":"0",
  "net":"ws",
  "type":"none",
  "host":"$DOMAIN",
  "path":"$WS_PATH",
  "tls":"none",
  "mux":true
}
EOF
)
    VMESS_LINK="vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)"
    PUBKEY=$(cat "$SLOWDNS_KEY_PUB")

    clear
    echo -e "${CYAN}+=============================================+${RESET}"
    echo -e "${CYAN}|           ${YELLOW}NOUVEAU UTILISATEUR V2RAYDNSTT CRÉÉ${CYAN}           |${RESET}"
    echo -e "${CYAN}+=============================================+${RESET}"
    echo -e "${GREEN}DOMAIN        :${RESET} $DOMAIN"
    echo -e "${GREEN}PORT          :${RESET} $V2RAY_PORT"
    echo -e "${GREEN}UUID          :${RESET} $USER_UUID"
    echo -e "${GREEN}MÉTHODE       :${RESET} WS sans TLS"
    echo -e "${GREEN}PATH          :${RESET} $WS_PATH"
    echo -e "${GREEN}UTILISATEUR   :${RESET} $USERNAME"
    echo -e "${GREEN}LIMITE        :${RESET} $DURATION jours"
    echo -e "${GREEN}DATE EXPIRÉE  :${RESET} $EXPIRY_DATE"
    echo
    echo -e "${YELLOW}VMess Link:${RESET}"
    echo "$VMESS_LINK"
    echo
    echo -e "${YELLOW}Nom de domaine NS slowdns :${RESET}"
    echo -e "${GREEN}$DOMAIN${RESET}"
    echo
    echo -e "${YELLOW}Clé publique SlowDNS:${RESET}"
    echo "$PUBKEY"
    echo -e "${CYAN}+=============================================+${RESET}"
}

delete_user() {
    if [[ ! -f $V2RAY_CONFIG ]]; then
        echo -e "${RED}Configuration V2Ray absente. Faites l'installation complète d'abord.${RESET}"
        return
    fi

    echo -e "${YELLOW}UUIDs existants :${RESET}"
    jq -r '.inbounds[0].settings.clients[].id' $V2RAY_CONFIG

    read -p "UUID utilisateur à supprimer : " DEL_UUID

    if jq -e ".inbounds[0].settings.clients[] | select(.id==\"$DEL_UUID\")" $V2RAY_CONFIG >/dev/null; then
        jq "del(.inbounds[0].settings.clients[] | select(.id==\"$DEL_UUID\"))" $V2RAY_CONFIG > "${V2RAY_CONFIG}.tmp" && mv "${V2RAY_CONFIG}.tmp" $V2RAY_CONFIG
        echo -e "${GREEN}Utilisateur $DEL_UUID supprimé.${RESET}"
        systemctl restart v2ray
    else
        echo -e "${RED}UUID non trouvé.${RESET}"
    fi
}

while true; do
    clear
    echo -e "${CYAN}+=============================================+${RESET}"
    echo -e "${CYAN}|           ${YELLOW}Gestion V2Ray SlowDNS${CYAN}           |${RESET}"
    echo -e "${CYAN}+=============================================+${RESET}"
    echo -e "${GREEN}1)${RESET} Installation complète V2Ray SlowDNS"
    echo -e "${GREEN}2)${RESET} Créer un utilisateur V2Ray SlowDNS"
    echo -e "${GREEN}3)${RESET} Supprimer un utilisateur V2Ray SlowDNS"
    echo -e "${GREEN}4)${RESET} Quitter"
    echo
    read -rp "Choisissez une option [1-4] : " option

    case $option in
        1) install_complete ;;
        2) create_user ;;
        3) delete_user ;;
        4) exit 0 ;;
        *) echo -e "${RED}Option invalide.${RESET}" ;;
    esac

    echo
    read -rp "Appuyez sur Entrée pour continuer..." pause
done
