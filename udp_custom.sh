#!/bin/bash
# udp_custom.sh
# Installation et configuration UDP Custom pour HTTP Custom VPN
# + Forwarding UDP via socat pour SSH UDP Custom

set -e

INSTALL_DIR="/root/udp-custom"
CONFIG_FILE="$INSTALL_DIR/config/config.json"
BIN_PATH="$INSTALL_DIR/bin/udp-custom-linux-amd64"
UDP_PORT=54000
BADVPN_UDP_PORT=7200
SOCAT_SERVICE="/etc/systemd/system/socat-udp-forward.service"

echo "+--------------------------------------------+"
echo "|             INSTALLATION UDP CUSTOM        |"
echo "+--------------------------------------------+"

echo "Installation des dépendances..."
apt-get update
apt-get install -y git curl build-essential libssl-dev jq iptables socat

# Cloner le dépôt udp-custom si non présent
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Clonage du dépôt udp-custom..."
    git clone https://github.com/http-custom/udp-custom.git "$INSTALL_DIR"
else
    echo "udp-custom déjà présent, mise à jour..."
    cd "$INSTALL_DIR"
    git pull
fi

cd "$INSTALL_DIR"

# Vérifier la présence et droits du binaire précompilé
if [ ! -x "$BIN_PATH" ]; then
    echo "Le binaire $BIN_PATH n'est pas exécutable, changement de permission..."
    chmod +x "$BIN_PATH"
fi

if [ ! -x "$BIN_PATH" ]; then
    echo "Erreur: Le binaire $BIN_PATH est manquant ou non exécutable."
    exit 1
fi

# Configuration du port UDP dans config.json
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Création du fichier de configuration UDP custom..."
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" << EOF
{
  "server_port": $UDP_PORT,
  "exclude_port": [],
  "udp_timeout": 600,
  "dns_cache": true
}
EOF
else
    echo "Modification du port dans la configuration existante..."
    jq ".server_port = $UDP_PORT" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
fi

# Ouverture du port UDP dans iptables
echo "Ouverture du port UDP $UDP_PORT dans iptables..."
iptables -I INPUT -p udp --dport $UDP_PORT -j ACCEPT

# Démarrage du démon udp-custom en arrière-plan
echo "Démarrage du démon udp-custom sur le port $UDP_PORT..."
nohup "$BIN_PATH" -c "$CONFIG_FILE" > /var/log/udp_custom.log 2>&1 &

sleep 3

if pgrep -f "udp-custom-linux-amd64" > /dev/null; then
    echo "UDP Custom démarré avec succès sur le port $UDP_PORT."
else
    echo "Erreur: UDP Custom ne s'est pas lancé correctement."
    exit 1
fi

# Lancement Socat pour forwarding UDP vers badvpn-udpgw
echo "Configuration du forwarding UDP via socat du port $UDP_PORT vers badvpn-udpgw sur 127.0.0.1:$BADVPN_UDP_PORT..."

# Créer un service systemd pour socat
cat << EOF > $SOCAT_SERVICE
[Unit]
Description=Socat UDP Forward from $UDP_PORT to BadVPN UDPGW $BADVPN_UDP_PORT
After=network.target

[Service]
ExecStart=/usr/bin/socat UDP4-RECVFROM:$UDP_PORT,fork UDP4-SENDTO:127.0.0.1:$BADVPN_UDP_PORT
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable socat-udp-forward.service
systemctl restart socat-udp-forward.service

# Ouverture du port badvpn UDP internal sur grand public firewall (optionnel)
iptables -I INPUT -p udp --dport $BADVPN_UDP_PORT -j ACCEPT || true

echo "+--------------------------------------------+"
echo "|         Configuration terminée             |"
echo "|   Configure HTTP Custom avec IP du serveur|"
echo "|   port UDP $UDP_PORT, activez UDP Custom   |"
echo "|                                            |"
echo "|   Côté client : lancez socat pour forwarder|"
echo "|   le port UDP local vers tunnel SSH TCP    |"
echo "|                                            |"
echo "|   Exemple client socat (termux/android/linux)|"
echo "|   socat UDP4-LISTEN:$BADVPN_UDP_PORT,fork TCP:127.0.0.1:<PORT_SSH_TCP> |"
echo "+--------------------------------------------+"
