#!/bin/bash
# v2ray_slowdns_install.sh
# Installation et lancement tunnel V2Ray SlowDNS WS TCP 5304
# Utilise le même namespace que SSH SlowDNS (récupéré depuis un fichier) et WS path fixe /kighmu

set -e

SERVICE_NAME="v2ray-slowdns"
INSTALL_DIR="/usr/local/etc/v2ray_slowdns"
BIN_PATH="/usr/local/bin/v2ray"
CONFIG_PATH="$INSTALL_DIR/config.json"
TCP_PORT=5304
UUID="afefe672-fae4-40ed-86c8-807c17d66703"

# Définir le chemin où SSH SlowDNS stocke son NS
SSH_SLOWDNS_NS_FILE="/etc/slowdns/ns.txt"

# Récupérer le NS ou demander à l'utilisateur
if [[ -f "$SSH_SLOWDNS_NS_FILE" ]]; then
  NAMESPACE=$(cat "$SSH_SLOWDNS_NS_FILE")
  echo "Namespace récupéré depuis SSH SlowDNS : $NAMESPACE"
else
  echo "Fichier namespace SSH SlowDNS introuvable ($SSH_SLOWDNS_NS_FILE)."
  read -rp "Entrez manuellement le namespace (NS) pour V2Ray SlowDNS : " NAMESPACE
  if [[ -z "$NAMESPACE" ]]; then
    echo "Namespace non fourni, arrêt de l'installation."
    exit 1
  fi
fi

echo "Installation et configuration du tunnel V2Ray SlowDNS (WS TCP port $TCP_PORT)"
echo "Namespace utilisé : $NAMESPACE"
echo "UUID configuré : $UUID"
echo "Chemin WS fixé à /kighmu"

# Installer V2Ray si non existant
if ! command -v $BIN_PATH &> /dev/null; then
  echo "V2Ray non trouvé, installation en cours..."
  bash <(curl -L -s https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
else
  echo "V2Ray déjà installé."
fi

# Créer dossier de configuration
mkdir -p "$INSTALL_DIR"

# Créer le fichier de configuration V2Ray avec WebSocket path fixe /kighmu

cat > "$CONFIG_PATH" <<EOF
{
  "inbounds": [
    {
      "port": $TCP_PORT,
      "listen": "0.0.0.0",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/kighmu"
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

echo "Fichier de configuration créé : $CONFIG_PATH"

# Création du service systemd

SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=V2Ray SlowDNS Tunnel Service (WS)
After=network.target

[Service]
Type=simple
User=root
ExecStart=$BIN_PATH run -config $CONFIG_PATH
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Activer et démarrer le service

systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl restart $SERVICE_NAME

echo "Service $SERVICE_NAME démarré sur TCP port $TCP_PORT avec WS chemin /kighmu, namespace $NAMESPACE et UUID $UUID."

# Vérifier écoute sur TCP 5304

ss -lnpt | grep $TCP_PORT && echo "V2Ray SlowDNS WS fonctionne correctement." || echo "Erreur : le service n'écoute pas sur le port $TCP_PORT."
