#!/bin/bash

# ==============================================
# slowdns.sh - Installation et configuration SlowDNS
# ==============================================

PUB_KEY="7fbd1f8aa0abfe15a7903e837f78aba39cf61d36f183bd604daa2fe4ef3b7b59"
SLOWDNS_DIR="/etc/slowdns"
SERVER_KEY="$SLOWDNS_DIR/server.key"     # Clé privée serveur
SERVER_PUB="$SLOWDNS_DIR/server.pub"     # Clé publique serveur
SLOWDNS_BIN="/usr/local/bin/sldns-server" # Chemin du binaire SlowDNS
PORT=5300

echo "Vérification et installation du binaire SlowDNS..."

if [ ! -x "$SLOWDNS_BIN" ]; then
    echo "Le binaire SlowDNS n'existe pas. Téléchargement en cours..."
    sudo mkdir -p /usr/local/bin
    sudo wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
    sudo chmod +x "$SLOWDNS_BIN"
    echo "Installation du binaire SlowDNS terminée."
else
    echo "Le binaire SlowDNS est déjà installé."
fi

echo "+--------------------------------------------+"
echo "|               CONFIG SLOWDNS               |"
echo "+--------------------------------------------+"

read -p "Entrez le NameServer (NS) (ex: ns.example.com) : " NAMESERVER

echo ""
echo "Configuration de SlowDNS..."
echo "Clé publique : $PUB_KEY"
echo "NameServer  : $NAMESERVER"

# Vérification et création du dossier SlowDNS
if [ ! -d "$SLOWDNS_DIR" ]; then
    echo "Création du dossier SlowDNS dans $SLOWDNS_DIR"
    sudo mkdir -p "$SLOWDNS_DIR"
fi

# Génération automatique des clés si absentes
if [ ! -f "$SERVER_KEY" ] || [ ! -f "$SERVER_PUB" ]; then
    echo "Clés SlowDNS manquantes, génération en cours..."
    sudo openssl genpkey -algorithm RSA -out "$SERVER_KEY" -pkeyopt rsa_keygen_bits:2048
    sudo openssl rsa -pubout -in "$SERVER_KEY" -out "$SERVER_PUB"
    sudo chmod 600 "$SERVER_KEY"
    sudo chmod 644 "$SERVER_PUB"
    echo "Clés SlowDNS générées avec succès."
fi

# Tuer l'ancienne instance SlowDNS si elle tourne toujours sur le port UDP
sudo fuser -k ${PORT}/udp || true

echo "Lancement du serveur SlowDNS en arrière-plan..."
nohup sudo "$SLOWDNS_BIN" -udp ":$PORT" -privkey "$SERVER_KEY" -pubkey "$SERVER_PUB" > /var/log/slowdns.log 2>&1 &

sleep 3

# Vérifier si SlowDNS a démarré
if pgrep -f "sldns-server" > /dev/null; then
    echo "Service SlowDNS démarré avec succès sur le port UDP $PORT."
    echo "Pour vérifier les logs, consulte : /var/log/slowdns.log"
else
    echo "ERREUR : Le service SlowDNS n'a pas pu démarrer."
    echo "Consulte les logs pour plus d'information."
    exit 1
fi

# Activer le forwarding IP si ce n'est pas déjà fait
if [ "$(sysctl -n net.ipv4.ip_forward)" -ne 1 ]; then
    echo "Activation du routage IP..."
    sudo sysctl -w net.ipv4.ip_forward=1
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
fi

# Ouvrir le port UDP dans le firewall
echo "Ouverture du port UDP $PORT dans le firewall (ufw)..."
sudo ufw allow "$PORT"/udp
sudo ufw reload

echo "Configuration SlowDNS terminée."
