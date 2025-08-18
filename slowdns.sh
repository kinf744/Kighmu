#!/bin/bash

# ==============================================
# slowdns.sh - Installation et configuration SlowDNS avec stockage NS
# ==============================================

PUB_KEY="7fbd1f8aa0abfe15a7903e837f78aba39cf61d36f183bd604daa2fe4ef3b7b59"
SLOWDNS_DIR="/etc/slowdns"
SERVER_KEY="$SLOWDNS_DIR/server.key"     # Clé privée serveur
SERVER_PUB="$SLOWDNS_DIR/server.pub"     # Clé publique serveur
SLOWDNS_BIN="/usr/local/bin/sldns-server" # Chemin du binaire SlowDNS
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"

# Vérification et création du dossier slowdns si besoin
if [ ! -d "$SLOWDNS_DIR" ]; then
    sudo mkdir -p "$SLOWDNS_DIR"
fi

# Chargement ou saisie du NameServer (NS)
if [ -f "$CONFIG_FILE" ]; then
    NAMESERVER=$(cat "$CONFIG_FILE")
    echo "Utilisation du NameServer existant : $NAMESERVER"
else
    read -p "Entrez le NameServer (NS) (ex: ns.example.com) : " NAMESERVER
    echo "$NAMESERVER" | sudo tee "$CONFIG_FILE" > /dev/null
    echo "NameServer enregistré dans $CONFIG_FILE"
fi

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

echo ""
echo "Configuration de SlowDNS..."
echo "Clé publique : $PUB_KEY"
echo "NameServer  : $NAMESERVER"

# Génération automatique des clés si absentes ou vides
if [ ! -s "$SERVER_KEY" ] || [ ! -s "$SERVER_PUB" ]; then
    echo "Clés SlowDNS manquantes ou vides, génération en cours..."
    sudo $SLOWDNS_BIN -gen-key -privkey-file "$SERVER_KEY" -pubkey-file "$SERVER_PUB"
    sudo sed -i '/^\s*$/d' "$SERVER_KEY"
    sudo sed -i '/^\s*$/d' "$SERVER_PUB"
    sudo chmod 600 "$SERVER_KEY"
    sudo chmod 644 "$SERVER_PUB"
    echo "Clés SlowDNS générées et nettoyées avec succès."
fi

# Arrêt de l'ancienne instance SlowDNS si existante
sudo fuser -k ${PORT}/udp || true

echo "Lancement du serveur SlowDNS en arrière-plan..."
nohup sudo "$SLOWDNS_BIN" -udp ":$PORT" -privkey-file "$SERVER_KEY" "$NAMESERVER" 8.8.8.8:53 > /var/log/slowdns.log 2>&1 &

sleep 3

# Vérification du démarrage
if pgrep -f "sldns-server" > /dev/null; then
    echo "Service SlowDNS démarré avec succès sur le port UDP $PORT."
    echo "Pour vérifier les logs, consulte : /var/log/slowdns.log"
else
    echo "ERREUR : Le service SlowDNS n'a pas pu démarrer."
    echo "Consulte les logs pour plus d'information."
    exit 1
fi

# Activation IP forwarding si nécessaire
if [ "$(sysctl -n net.ipv4.ip_forward)" -ne 1 ]; then
    echo "Activation du routage IP..."
    sudo sysctl -w net.ipv4.ip_forward=1
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
fi

# Ouverture du port UDP dans firewall ufw si présent
echo "Ouverture du port UDP $PORT dans le firewall (ufw)..."
if command -v ufw >/dev/null 2>&1; then
    sudo ufw allow "$PORT"/udp
    sudo ufw reload
else
    echo "UFW non installé, vérifie manuellement l'ouverture du port UDP $PORT"
fi

echo "Configuration SlowDNS terminée."
