#!/bin/bash

# ==============================================
# slowdns.sh - Installation et configuration SlowDNS avec gestion par screen
# ==============================================

SLOWDNS_DIR="/etc/slowdns"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"

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

# Création du dossier si absent
[ ! -d "$SLOWDNS_DIR" ] && sudo mkdir -p "$SLOWDNS_DIR"

# Demande du NameServer à chaque installation
read -p "Entrez le NameServer (NS) (ex: ns.example.com) : " NAMESERVER
if [[ -z "$NAMESERVER" ]]; then
    echo "NameServer invalide."
    exit 1
fi
echo "$NAMESERVER" | sudo tee "$CONFIG_FILE" > /dev/null

# Téléchargement du binaire SlowDNS s'il manque
if [ ! -x "$SLOWDNS_BIN" ]; then
    sudo mkdir -p /usr/local/bin
    sudo wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
    sudo chmod +x "$SLOWDNS_BIN"
fi

# Génération systématique des clés
echo "Génération des clés SlowDNS..."
sudo $SLOWDNS_BIN -gen-key -privkey-file "$SERVER_KEY" -pubkey-file "$SERVER_PUB"
sudo chmod 600 "$SERVER_KEY"
sudo chmod 644 "$SERVER_PUB"

PUB_KEY=$(cat "$SERVER_PUB")

# Arrêt propre de l'ancienne session screen slowdns_session si existante
if screen -list | grep -q "slowdns_session"; then
    echo "Arrêt de l'ancienne session screen slowdns_session..."
    screen -S slowdns_session -X quit
    sleep 2
fi

# Configuration iptables
configure_iptables() {
    interface=$(ip a | awk '/state UP/{print $2}' | cut -d: -f1 | head -1)
    echo "Configuration iptables: redirige UDP port 53 vers $PORT..."
    sudo iptables -I INPUT -p udp --dport $PORT -j ACCEPT
    sudo iptables -t nat -I PREROUTING -i $interface -p udp --dport 53 -j REDIRECT --to-ports $PORT
    sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
}

configure_iptables

# Lancement SlowDNS dans screen détaché
echo "Démarrage du serveur SlowDNS dans screen (session slowdns_session)..."
sudo screen -dmS slowdns_session $SLOWDNS_BIN -udp ":$PORT" -privkey-file "$SERVER_KEY" "$NAMESERVER" 0.0.0.0:22

sleep 3

if pgrep -f "sldns-server" > /dev/null; then
    echo -e "\033[32mSlowDNS démarré avec succès sur UDP port $PORT.\033[0m"
    echo "Pour rattacher la session screen : screen -r slowdns_session"
else
    echo "ERREUR : Le service SlowDNS n'a pas pu démarrer."
    exit 1
fi

# Activation routage IP si nécessaire
if [ "$(sysctl -n net.ipv4.ip_forward)" -ne 1 ]; then
    echo "Activation du routage IP..."
    sudo sysctl -w net.ipv4.ip_forward=1
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
    fi
fi

# Ouverture port UDP sur ufw si présent
if command -v ufw >/dev/null 2>&1; then
    echo "Ouverture du port UDP $PORT dans ufw..."
    sudo ufw allow "$PORT"/udp
    sudo ufw reload
else
    echo "[INFO] UFW non installé, veuillez vérifier manuellement l'ouverture du port UDP $PORT."
fi

echo "+--------------------------------------------+"
echo "|            CONFIGURATION SLOWDNS           |"
echo "+--------------------------------------------+"
echo ""
echo "Clé publique :"
echo "$PUB_KEY"
echo ""
echo "NameServer  : $NAMESERVER"
echo ""
echo "Commande client Termux :"
echo "curl -sO https://github.com/khaledagn/DNS-AGN/raw/main/files/slowdns && chmod +x slowdns && ./slowdns $NAMESERVER $PUB_KEY"
echo ""
