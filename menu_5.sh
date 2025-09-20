#!/bin/bash

V2RAY_CONFIG="/etc/v2ray/config.json"
UUID_FILE="/etc/v2ray/uuid.txt"
DOMAIN_FILE="/etc/slowdns/ns.conf"
SLOWDNS_KEY_PRIV="/etc/slowdns/server.key"
SLOWDNS_KEY_PUB="/etc/slowdns/server.pub"
SLOWDNS_BIN_CLIENT="/usr/local/bin/sldns-client"

V2RAY_PORT=10000
WS_PATH="/kighmu"  # Chemin websocket forcé

install_complete() {
    echo "Installation complète de V2Ray SlowDNS (sans TUN)..."

    if [[ ! -f "$DOMAIN_FILE" ]]; then
        echo "Le fichier nameserver $DOMAIN_FILE est introuvable. Veuillez exécuter l'installation SlowDNS avant."
        exit 1
    fi
    DOMAIN=$(cat "$DOMAIN_FILE")
    echo "Nom de domaine SlowDNS : $DOMAIN"

    if [[ ! -f $SLOWDNS_KEY_PUB ]]; then
        echo "Clé publique SlowDNS introuvable à $SLOWDNS_KEY_PUB."
        exit 1
    fi

    echo "Mise à jour système et installation des dépendances nécessaires..."
    apt update && apt upgrade -y
    apt install -y curl unzip jq iproute2

    if ! command -v v2ray &>/dev/null; then
        echo "Installation de V2Ray..."
        curl -O https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh
        bash install-release.sh
    fi

    if [[ ! -f $UUID_FILE ]]; then
        UUID=$(uuidgen)
        echo "$UUID" > $UUID_FILE
    else
        UUID=$(cat $UUID_FILE)
    fi

    echo "Création de la configuration V2Ray avec websocket..."

    cat > $V2RAY_CONFIG <<EOF
{
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

    echo "Installation terminée. V2Ray écoute sur 127.0.0.1:$V2RAY_PORT avec ws path $WS_PATH"
}

create_user() {
    if [[ ! -f $V2RAY_CONFIG ]]; then
        echo "Configuration V2Ray absente. Veuillez faire l'installation complète d'abord."
        return
    fi

    DOMAIN=$(cat $DOMAIN_FILE)
    if [[ ! -f $SLOWDNS_KEY_PUB ]]; then
        echo "Clé publique SlowDNS non trouvée."
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

    echo -e "\n*NOUVEAU UTILISATEUR V2RAYDNSTT CRÉÉ*"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "DOMAIN        : $DOMAIN"
    echo "PORT          : $V2RAY_PORT"
    echo "UUID          : $USER_UUID"
    echo "MÉTHODE       : WS sans TLS"
    echo "PATH          : $WS_PATH"
    echo "UTILISATEUR   : $USERNAME"
    echo "LIMITE        : $DURATION jours"
    echo "DATE EXPIRÉE  : $EXPIRY_DATE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    echo "$VMESS_LINK"
    echo -e "\n━━━━━━━━━━━  CONFIG SLOWDNS  ━━━━━━━━━━━"
    echo "Clé publique :"
    echo "$PUBKEY"
    echo "NameServer (NS) : $DOMAIN"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

delete_user() {
    if [[ ! -f $V2RAY_CONFIG ]]; then
        echo "Configuration V2Ray absente. Faites l'installation complète d'abord."
        return
    fi

    echo "UUIDs existants :"
    jq -r '.inbounds[0].settings.clients[].id' $V2RAY_CONFIG

    read -p "UUID utilisateur à supprimer : " DEL_UUID

    if jq -e ".inbounds[0].settings.clients[] | select(.id==\"$DEL_UUID\")" $V2RAY_CONFIG >/dev/null; then
        jq "del(.inbounds[0].settings.clients[] | select(.id==\"$DEL_UUID\"))" $V2RAY_CONFIG > "${V2RAY_CONFIG}.tmp" && mv "${V2RAY_CONFIG}.tmp" $V2RAY_CONFIG
        echo "Utilisateur $DEL_UUID supprimé."
        systemctl restart v2ray
    else
        echo "UUID non trouvé."
    fi
}

while true; do
    echo "===== Gestion V2Ray SlowDNS ====="
    echo "1) Installation complète V2Ray SlowDNS"
    echo "2) Créer un utilisateur V2Ray SlowDNS"
    echo "3) Supprimer un utilisateur V2Ray SlowDNS"
    echo "4) Quitter"
    read -rp "Choisissez une option [1-4] : " option

    case $option in
        1) install_complete ;;
        2) create_user ;;
        3) delete_user ;;
        4) exit 0 ;;
        *) echo "Option invalide." ;;
    esac
done
