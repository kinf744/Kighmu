#!/bin/bash
# ==============================================
# slowdns.sh - Installation et configuration SlowDNS rapide et stable
# ==============================================

SLOWDNS_DIR="/etc/slowdns"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT1=5300 # premier port UDP
PORT2=5353 # second port UDP
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"

# Installation des dépendances
install_dependencies() {
    sudo apt update
    for pkg in iptables screen tcpdump iftop nload dstat; do
        if ! command -v $pkg >/dev/null 2>&1; then
            sudo apt install -y $pkg
        fi
    done
}

install_dependencies

# Création du dossier slowdns si absent
sudo mkdir -p "$SLOWDNS_DIR"

# Demande toujours le NameServer (NS)
read -p "Entrez le NameServer (NS) (ex: ns.example.com) : " NAMESERVER
echo "$NAMESERVER" | sudo tee "$CONFIG_FILE" > /dev/null

# Installation du binaire SlowDNS si besoin
if [ ! -x "$SLOWDNS_BIN" ]; then
    sudo wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
    sudo chmod +x "$SLOWDNS_BIN"
fi

# Génération automatique des clés si absentes
if [ ! -s "$SERVER_KEY" ] || [ ! -s "$SERVER_PUB" ]; then
    sudo $SLOWDNS_BIN -gen-key -privkey-file "$SERVER_KEY" -pubkey-file "$SERVER_PUB"
    sudo chmod 600 "$SERVER_KEY"
    sudo chmod 644 "$SERVER_PUB"
fi

PUB_KEY=$(cat "$SERVER_PUB")

# Arrêt de l’ancienne instance SlowDNS si existante
sudo pkill -f "sldns-server" || true
sleep 2

# Optimisations kernel pour débit & stabilité
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.core.rmem_max=26214400
sudo sysctl -w net.core.wmem_max=26214400
sudo sysctl -w net.ipv4.tcp_rmem="4096 87380 26214400"
sudo sysctl -w net.ipv4.tcp_wmem="4096 65536 26214400"
sudo sysctl -w net.ipv4.tcp_fastopen=3
sudo sysctl -w net.ipv4.tcp_tw_reuse=1
sudo sysctl -w net.core.netdev_max_backlog=2500

interface=$(ip a | awk '/state UP/{print $2}' | cut -d: -f1 | head -1)
sudo ip link set dev "$interface" mtu 1400

for param in "net.ipv4.ip_forward=1" "net.core.rmem_max=26214400" "net.core.wmem_max=26214400" "net.ipv4.tcp_fastopen=3" "net.ipv4.tcp_tw_reuse=1" "net.ipv4.tcp_rmem=4096 87380 26214400" "net.ipv4.tcp_wmem=4096 65536 26214400" "net.core.netdev_max_backlog=2500"
do
    if ! grep -q "$param" /etc/sysctl.conf; then
        echo "$param" | sudo tee -a /etc/sysctl.conf >/dev/null
    fi
done

# IPtables pour redirection 53 -> 5300 et 5353 UDP + journalisation
sudo iptables -I INPUT -p udp --dport $PORT1 -j ACCEPT
sudo iptables -I INPUT -p udp --dport $PORT2 -j ACCEPT
sudo iptables -I INPUT -p udp --dport 53 -j ACCEPT
sudo iptables -t nat -I PREROUTING -i "$interface" -p udp --dport 53 -j REDIRECT --to-ports $PORT1

sudo iptables -N LOGGING || true
sudo iptables -A INPUT -j LOGGING
sudo iptables -A LOGGING -m limit --limit 2/min -j LOG --log-prefix "IPTables-Dropped: " --log-level 4
sudo iptables -A LOGGING -j DROP

sudo iptables-save | sudo tee /etc/iptables/rules.v4 >/dev/null

# Firewall UFW
if command -v ufw >/dev/null 2>&1; then
    sudo ufw allow "$PORT1"/udp
    sudo ufw allow "$PORT2"/udp
    sudo ufw reload
fi

# Lancement du serveur SlowDNS sur 2 ports pour multi-threading (multi-session)
sudo screen -dmS slowdns_1 $SLOWDNS_BIN -udp ":$PORT1" -privkey-file "$SERVER_KEY" "$NAMESERVER" 0.0.0.0:22
sudo screen -dmS slowdns_2 $SLOWDNS_BIN -udp ":$PORT2" -privkey-file "$SERVER_KEY" "$NAMESERVER" 0.0.0.0:22

sleep 3

if pgrep -f "sldns-server" > /dev/null; then
    echo "Service SlowDNS démarré avec succès sur les ports UDP $PORT1 et $PORT2."
else
    echo "ERREUR : Le service SlowDNS n'a pas pu démarrer."
    exit 1
fi

echo "+--------------------------------------------+"
echo "|           CONFIG SLOWDNS OPTIMISÉE          |"
echo "+--------------------------------------------+"
echo ""
echo "Clé publique :"
echo "$PUB_KEY"
echo ""
echo "NameServer  : $NAMESERVER"
echo ""
echo "Commande client Termux (modifiée pour multi-threading) :"
echo "curl -sO https://github.com/khaledagn/DNS-AGN/raw/main/files/slowdns && chmod +x slowdns"
echo "./slowdns $NAMESERVER $PUB_KEY" # Lancer une instance par port UDP utilisé (ex: 5300, 5353)
echo ""
echo "Ports utilisés : $PORT1 / $PORT2 UDP (multi-threading multi-session)"
echo ""
echo "Installation, optimisation kernel, iptables, journaux et multi-threading activés."
