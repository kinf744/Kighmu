#!/bin/bash
# udp_request.sh
# Installation et configuration UDP Request pour SocksIP Tunnel VPN

set -e

INSTALL_DIR="/root/udp-request"
CONFIG_FILE="$INSTALL_DIR/config/config.json"
BIN_PATH="$INSTALL_DIR/bin/udp-request-linux-amd64"
UDP_PORT=36712

echo "+--------------------------------------------+"
echo "|           INSTALLATION UDP REQUEST          |"
echo "+--------------------------------------------+"

echo "Installation des dépendances..."
apt-get update
apt-get install -y git curl build-essential libssl-dev jq iptables

# Clonage ou mise à jour du dépôt udp-request (changer URL si besoin)
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Clonage du dépôt udp-request..."
    git clone https://github.com/user/udp-request.git "$INSTALL_DIR"
else
    echo "udp-request déjà présent, mise à jour..."
    cd "$INSTALL_DIR"
    git pull
fi

cd "$INSTALL_DIR"

# Vérification et permission du binaire
if [ ! -x "$BIN_PATH" ]; then
    echo "Le binaire $BIN_PATH n'est pas exécutable, changement de permission..."
    chmod +x "$BIN_PATH"
fi

if [ ! -x "$BIN_PATH" ]; then
    echo "Erreur: Le binaire $BIN_PATH est manquant ou non exécutable."
    exit 1
fi

# Création ou modification de la config JSON spécifique UDP Request
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Création du fichier de configuration UDP Request..."
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" << EOF
{
  "server_port": $UDP_PORT,
  "port_range_start": $UDP_PORT,
  "port_range_end": $((UDP_PORT + 100)),  
  "udp_timeout": 600,
  "dns_cache": true
}
EOF
else
    echo "Modification des ports dans la configuration existante..."
    jq ".server_port = $UDP_PORT | .port_range_start = $UDP_PORT | .port_range_end = ($UDP_PORT + 100)" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
fi

# Ouverture du port UDP principal et de la plage dans iptables
echo "Ouverture du port UDP $UDP_PORT et plage $UDP_PORT-$((UDP_PORT+100)) dans iptables..."
iptables -I INPUT -p udp --dport $UDP_PORT -j ACCEPT
iptables -I INPUT -p udp --dport $UDP_PORT:$((UDP_PORT+100)) -j ACCEPT

# Démarrage du serveur UDP Request en arrière-plan
echo "Démarrage du démon udp-request sur le port $UDP_PORT..."
nohup "$BIN_PATH" -c "$CONFIG_FILE" > /var/log/udp_request.log 2>&1 &

sleep 3

if pgrep -f "udp-request-linux-amd64" > /dev/null; then
    echo "UDP Request démarré avec succès sur le port $UDP_PORT."
else
    echo "Erreur: UDP Request ne s'est pas lancé correctement."
fi

echo "+--------------------------------------------+"
echo "|          Configuration terminée            |"
echo "|  Configure SocksIP Tunnel avec IP serveur  |"
echo "|  port UDP $UDP_PORT et activez UDP Request |"
echo "+--------------------------------------------+"
