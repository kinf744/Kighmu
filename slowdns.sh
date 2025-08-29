#!/bin/bash

# ==============================================
# slowdns.sh - Installation et configuration SlowDNS avec stockage NS
# Optimisé pour performances et stabilité + persistance via systemd
# ==============================================

SLOWDNS_DIR="/etc/slowdns"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVICE_FILE="/etc/systemd/system/slowdns.service"

# Installation dépendances si manquantes
install_dependencies() {
    sudo apt update
    for pkg in iptables screen tcpdump; do
        if ! command -v $pkg >/dev/null 2>&1; then
            echo "$pkg non trouvé. Installation en cours..."
            sudo apt install -y $pkg
        else
            echo "$pkg est déjà installé."
        fi
    done
}

install_dependencies

# Création dossier slowdns
[ ! -d "$SLOWDNS_DIR" ] && sudo mkdir -p "$SLOWDNS_DIR"

# Chargement ou saisie NameServer
if [ -f "$CONFIG_FILE" ]; then
    NAMESERVER=$(cat "$CONFIG_FILE")
    echo "Utilisation du NameServer existant : $NAMESERVER"
else
    read -p "Entrez le NameServer (NS) (ex: ns.example.com) : " NAMESERVER
    [[ -z "$NAMESERVER" ]] && { echo "NameServer invalide."; exit 1; }
    echo "$NAMESERVER" | sudo tee "$CONFIG_FILE" > /dev/null
    echo "NameServer enregistré dans $CONFIG_FILE"
fi

# Installation binaire SlowDNS si absent
if [ ! -x "$SLOWDNS_BIN" ]; then
    sudo mkdir -p /usr/local/bin
    sudo wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
    sudo chmod +x "$SLOWDNS_BIN"
fi

# Génération automatique clés
generate_keys() {
    if [ ! -s "$SERVER_KEY" ] || [ ! -s "$SERVER_PUB" ]; then
        echo "Génération des clés SlowDNS..."
        sudo $SLOWDNS_BIN -gen-key -privkey-file "$SERVER_KEY" -pubkey-file "$SERVER_PUB"
        sudo chmod 600 "$SERVER_KEY"
        sudo chmod 644 "$SERVER_PUB"
    else
        echo "Clés SlowDNS déjà présentes."
    fi
}

generate_keys
PUB_KEY=$(cat "$SERVER_PUB")

# Détection port SSH
ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)

# Création du fichier service systemd
sudo tee $SERVICE_FILE > /dev/null << EOF
[Unit]
Description=SlowDNS Server Service
After=network.target

[Service]
Type=simple
ExecStart=$SLOWDNS_BIN -udp :$PORT -privkey-file $SERVER_KEY $NAMESERVER 0.0.0.0:$ssh_port
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

# Rechargement systemd pour prise en compte
sudo systemctl daemon-reload

# Activation du service au démarrage
sudo systemctl enable slowdns.service

# Arrêt de l’ancienne instance
if pgrep -f "sldns-server" >/dev/null; then
    echo "Arrêt de l'ancienne instance SlowDNS..."
    sudo fuser -k ${PORT}/udp || true
    sleep 2
fi

# Démarrage du service systemd slowdns
sudo systemctl start slowdns.service

# Optimisation réseau
interface=$(ip a | awk '/state UP/{print $2}' | cut -d: -f1 | head -1)
echo "Réglage MTU sur interface $interface à 1400..."
sudo ip link set dev $interface mtu 1400

echo "Augmentation des buffers UDP..."
sudo sysctl -w net.core.rmem_max=26214400
sudo sysctl -w net.core.wmem_max=26214400

# Réglage iptables
sudo iptables -F
sudo iptables -I INPUT -p udp --dport $PORT -j ACCEPT
sudo iptables -t nat -I PREROUTING -i $interface -p udp --dport 53 -j REDIRECT --to-ports $PORT

if command -v iptables-save >/dev/null 2>&1; then
    sudo iptables-save | sudo tee /etc/iptables/rules.v4 >/dev/null
fi

# Activation IP forwarding
if [ "$(sysctl -n net.ipv4.ip_forward)" -ne 1 ]; then
    echo "Activation du routage IP..."
    sudo sysctl -w net.ipv4.ip_forward=1
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
    fi
fi

# Vérification démarrage service
if systemctl is-active --quiet slowdns.service; then
    echo "SlowDNS démarré et activé au démarrage automatique."
else
    echo "ERREUR : SlowDNS n'a pas pu démarrer via systemd."
    exit 1
fi

# Firewall UFW port ouvert
if command -v ufw >/dev/null 2>&1; then
    sudo ufw allow "$PORT"/udp
    sudo ufw reload
else
    echo "UFW non installé. Vérifier ouverture port UDP $PORT manuellement."
fi

echo "+--------------------------------------------+"
echo "|               CONFIG SLOWDNS               |"
echo "+--------------------------------------------+"
echo ""
echo "Clé publique :"
echo "$PUB_KEY"
echo ""
echo "NameServer  : $NAMESERVER"
echo ""
echo "Commande client (termux) :"
echo "curl -sO https://github.com/khaledagn/DNS-AGN/raw/main/files/slowdns && chmod +x slowdns && ./slowdns $NAMESERVER $PUB_KEY"
echo ""
echo "Installation et configuration SlowDNS optimisées et persistantes terminées."
