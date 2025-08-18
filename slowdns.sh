#!/bin/bash
# slowdns.sh
# Installation et configuration du mode SlowDNS réel

PUB_KEY="7fbd1f8aa0abfe15a7903e837f78aba39cf61d36f183bd604daa2fe4ef3b7b59"
SLOWDNS_DIR="/etc/slowdns"
SERVER_KEY="$SLOWDNS_DIR/server.key"   # Assure-toi que la clé privée est présente ici
SERVER_PUB="$SLOWDNS_DIR/server.pub"   # Clé publique correspondante
SLOWDNS_BIN="/usr/local/bin/sldns-server"  # Chemin vers le binaire SlowDNS
PORT=53

echo "+--------------------------------------------+"
echo "|               CONFIG SLOWDNS               |"
echo "+--------------------------------------------+"

read -p "Entrez le NameServer (NS) : " NAMESERVER

echo ""
echo "Configuration de SlowDNS..."
echo "Clé publique : $PUB_KEY"
echo "NameServer  : $NAMESERVER"

# Vérifier et créer dossier de SlowDNS si nécessaire
mkdir -p "$SLOWDNS_DIR"

# Ici tu dois copier ou générer les clés .key et .pub dans $SLOWDNS_DIR
# Par exemple, si tu as les clés dans ton dépôt, télécharge-les

# Exemple de lancement du serveur SlowDNS
if [ ! -f "$SLOWDNS_BIN" ]; then
    echo "Le binaire SlowDNS n'existe pas, veuillez l'installer manuellement."
    exit 1
fi

# Kill ancienne instance sur ce port si existante
fuser -k $PORT/udp || true

# Lancer le serveur SlowDNS en arrière-plan
nohup $SLOWDNS_BIN -udp :$PORT -privkey $SERVER_KEY -pubkey $SERVER_PUB > /var/log/slowdns.log 2>&1 &

sleep 2

if pgrep -f "sldns-server" > /dev/null; then
    echo "Service SlowDNS démarré avec succès sur le port UDP $PORT."
else
    echo "Erreur : le service SlowDNS n'a pas pu démarrer."
fi
