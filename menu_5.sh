#!/bin/bash

V2RAY_CONFIG="/etc/v2ray/config.json"
UUID_FILE="/etc/v2ray/uuid.txt"
DOMAIN_FILE="/etc/v2ray/domain.txt"
SLOWDNS_KEY_PRIV="/etc/slowdns/server.key"
SLOWDNS_KEY_PUB="/etc/slowdns/server.pub"
SLOWDNS_BIN_CLIENT="/usr/local/bin/sldns-client"
SLOWDNS_NS_FILE="/etc/slowdns/ns.conf"
TUN_IF="tun0"

install_complete() {
    echo "Installation complète de V2Ray SlowDNS en mode TUN..."

    # Demande nom de domaine (NS) slowdns
    if [[ -f "$SLOWDNS_NS_FILE" ]]; then
        DOMAIN=$(cat "$SLOWDNS_NS_FILE")
        echo "Nom de domaine SlowDNS actuel : $DOMAIN"
        read -p "Voulez-vous le changer ? (o/N): " choice
        if [[ "$choice" =~ ^[oO]$ ]]; then
            read -p "Entrez le nouveau nom de domaine SlowDNS : " DOMAIN
        fi
    else
        read -p "Entrez le nom de domaine SlowDNS (ex: kiaje.kighmuop.dpdns.org): " DOMAIN
    fi

    echo "$DOMAIN" > $DOMAIN_FILE

    # Mise à jour système
    echo "Mise à jour système et installation dépendances..."
    apt update && apt upgrade -y
    apt install -y curl unzip jq openssh-client iproute2

    # Vérification clé publique SlowDNS
    if [[ ! -f $SLOWDNS_KEY_PUB ]]; then
        echo "Clé publique SlowDNS introuvable à $SLOWDNS_KEY_PUB. Veuillez générer les clés avec le serveur SlowDNS."
        exit 1
    fi

    # Installer V2Ray si absent
    if ! command -v v2ray &>/dev/null; then
        echo "Installation de V2Ray..."
        curl -O https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh
        bash install-release.sh
    fi

    # Création service systemd tunnel SlowDNS SSH TUN
    cat > /etc/systemd/system/slowdns-tun.service <<EOF
[Unit]
Description=SlowDNS SSH Tunnel mode TUN
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/ssh -o ProxyCommand="$SLOWDNS_BIN_CLIENT -key $SLOWDNS_KEY_PUB -ns $DOMAIN" -w 0:0 user@$DOMAIN -N
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable slowdns-tun.service
    systemctl restart slowdns-tun.service

    sleep 5
    if ip link show $TUN_IF | grep -q "state UP"; then
        echo "Tunnel TUN SlowDNS actif."
    else
        echo "Erreur : tunnel TUN SlowDNS non actif."
        exit 1
    fi

    # UUID généré ou lu
    if [[ ! -f $UUID_FILE ]]; then
        UUID=$(uuidgen)
        echo $UUID > $UUID_FILE
    else
        UUID=$(cat $UUID_FILE)
    fi

    # Génération config V2Ray
    cat > $V2RAY_CONFIG <<EOF
{
  "inbounds": [
    {
      "port": 10000,
      "listen": "0.0.0.0",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "alterId": 64,
            "email": "default-user"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/ray"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

    systemctl restart v2ray
    echo "Installation terminée avec succès."
}

create_user() {
    if [[ ! -f $V2RAY_CONFIG ]]; then
        echo "Configuration V2Ray absente. Veuillez faire l'installation complète d'abord."
        return
    fi

    if [[ ! -f $DOMAIN_FILE ]]; then
        echo "Domaine SlowDNS non défini. Veuillez réinstaller."
        return
    fi

    DOMAIN=$(cat $DOMAIN_FILE)
    if [[ ! -f $SLOWDNS_KEY_PUB ]]; then
        echo "Clé publique SlowDNS non trouvée."
        return
    fi

    echo -n "Entrez le nom d'utilisateur : "
    read USERNAME

    echo -n "Entrez la durée (jours) : "
    read DURATION

    EXPIRY_DATE=$(date -d "+$DURATION days" +"%Y-%m-%d")

    USER_UUID=$(uuidgen)

    jq ".inbounds[0].settings.clients += [{\"id\":\"$USER_UUID\",\"alterId\":64,\"email\":\"$USERNAME\"}]" $V2RAY_CONFIG > "${V2RAY_CONFIG}.tmp" && mv "${V2RAY_CONFIG}.tmp" $V2RAY_CONFIG
    systemctl restart v2ray

    VMESS_JSON=$(cat <<EOF
{
  "v":"2",
  "ps":"V2Ray SlowDNS",
  "add":"$DOMAIN",
  "port":"10000",
  "id":"$USER_UUID",
  "aid":"0",
  "net":"ws",
  "type":"none",
  "host":"$DOMAIN",
  "path":"/ray",
  "tls":"none",
  "mux":true
}
EOF
)
    VMESS_LINK="vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)"
    PUBKEY=$(cat $SLOWDNS_KEY_PUB)

    echo -e "\n*NOUVEAU UTILISATEUR V2RAYDNSTT CRÉÉ*"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "DOMAIN        : $DOMAIN"
    echo "UTILISATEUR   : $USERNAME"
    echo "LIMITE        : $DURATION"
    echo "DATE EXPIRÉE  : $EXPIRY_DATE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    echo "$VMESS_LINK"
    echo -e "\n━━━━━━━━━━━  CONFIG SLOWDNS  ━━━━━━━━━━━"
    echo "Pub KEY :"
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

    echo -n "Entrez l'UUID utilisateur à supprimer : "
    read DEL_UUID

    if jq -e ".inbounds.settings.clients[] | select(.id==\"$DEL_UUID\")" $V2RAY_CONFIG > /dev/null; then
        jq "del(.inbounds.settings.clients[] | select(.id==\"$DEL_UUID\"))" $V2RAY_CONFIG > "${V2RAY_CONFIG}.tmp" && mv "${V2RAY_CONFIG}.tmp" $V2RAY_CONFIG
        echo "Utilisateur $DEL_UUID supprimé."
        systemctl restart v2ray
    else
        echo "Erreur : UUID $DEL_UUID non trouvé."
    fi
}

while true; do
    echo "===== Gestion V2Ray SlowDNS ====="
    echo "1) Installation complète V2Ray SlowDNS (mode TUN)"
    echo "2) Créer un utilisateur V2Ray SlowDNS"
    echo "3) Supprimer un utilisateur V2Ray SlowDNS"
    echo "4) Quitter"
    echo -n "Choisissez une option [1-4] : "
    read option

    case $option in
        1) install_complete ;;
        2) create_user ;;
        3) delete_user ;;
        4) exit 0 ;;
        *) echo "Option invalide." ;;
    esac
done
