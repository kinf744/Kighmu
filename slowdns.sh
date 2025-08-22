#!/bin/bash

# ==============================================
# slowdns_optimized.sh - Installation et configuration SlowDNS optimisée
# ==============================================

SLOWDNS_DIR="/etc/slowdns"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
NAMESPACE_FILE="$SLOWDNS_DIR/ns.txt"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=5300

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

sudo mkdir -p "$SLOWDNS_DIR"

# Lire le Namespace depuis fichier
if [ -f "$NAMESPACE_FILE" ]; then
    NAMESERVER=$(cat "$NAMESPACE_FILE")
    echo "Utilisation du NameServer existant : $NAMESERVER"
else
    echo "Fichier Namespace ($NAMESPACE_FILE) introuvable. Assurez-vous que le script principal d'installation a été exécuté."
    exit 1
fi

# Installer SlowDNS binaire si besoin
if [ ! -x "$SLOWDNS_BIN" ]; then
    echo "Le binaire SlowDNS n'existe pas. Téléchargement en cours..."
    sudo wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
    sudo chmod +x "$SLOWDNS_BIN"
    echo "Installation du binaire SlowDNS terminée."
else
    echo "Le binaire SlowDNS est déjà installé."
fi

# Génération des clés si absentes
if [ ! -s "$SERVER_KEY" ] || [ ! -s "$SERVER_PUB" ]; then
    echo "Clés SlowDNS manquantes ou vides, génération en cours..."
    sudo $SLOWDNS_BIN -gen-key -privkey-file "$SERVER_KEY" -pubkey-file "$SERVER_PUB"
    sudo chmod 600 "$SERVER_KEY"
    sudo chmod 644 "$SERVER_PUB"
    echo "Clés SlowDNS générées avec succès."
else
    echo "Clés SlowDNS déjà présentes."
fi

PUB_KEY=$(cat "$SERVER_PUB")

sudo sysctl -w net.core.rmem_max=26214400
sudo sysctl -w net.core.wmem_max=26214400
sudo sysctl -w net.core.rmem_default=26214400
sudo sysctl -w net.core.wmem_default=26214400
sudo sysctl -w net.ipv4.udp_mem="65536 131072 262144"
sudo sysctl -w net.ipv4.udp_rmem_min=8192
sudo sysctl -w net.ipv4.udp_wmem_min=8192

interface=$(ip a | awk '/state UP/{print $2}' | cut -d: -f1 | head -1)
sudo ip link set dev "$interface" mtu 1400

if pgrep -f "sldns-server" >/dev/null; then
    sudo fuser -k ${PORT}/udp || true
    sleep 2
fi

sudo iptables -I INPUT -p udp --dport $PORT -j ACCEPT
sudo iptables -t nat -I PREROUTING -i "$interface" -p udp --dport 53 -j REDIRECT --to-ports $PORT
sudo iptables-save | sudo tee /etc/iptables/rules.v4 >/dev/null

sudo sysctl -w net.ipv4.ip_forward=1
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
fi

sudo screen -dmS slowdns_session $SLOWDNS_BIN -udp ":$PORT" -privkey-file "$SERVER_KEY" "$NAMESERVER" 0.0.0.0:22
sleep 3

if pgrep -f "sldns-server" > /dev/null; then
    echo "Service SlowDNS démarré sur le port UDP $PORT."
else
    echo "ERREUR : Le service SlowDNS n'a pas pu démarrer."
    exit 1
fi

if command -v ufw >/dev/null 2>&1; then
    sudo ufw allow "$PORT"/udp
    sudo ufw reload
fi

echo "+--------------------------------------------+"
echo "|               CONFIG SLOWDNS               |"
echo "+--------------------------------------------+"
echo ""
echo "Clé publique : $PUB_KEY"
echo "NameServer   : $NAMESERVER"
echo ""
echo "Commande client Termux à utiliser :"
echo "curl -sO https://github.com/khaledagn/DNS-AGN/raw/main/files/slowdns && chmod +x slowdns && ./slowdns $NAMESERVER $PUB_KEY"
echo ""
echo "Installation et configuration SlowDNS optimisées terminées."
