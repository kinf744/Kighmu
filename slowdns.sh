#!/bin/bash
# slowdns.sh
# Installation et configuration du mode SlowDNS

PUB_KEY="7fbd1f8aa0abfe15a7903e837f78aba39cf61d36f183bd604daa2fe4ef3b7b59"

echo "+--------------------------------------------+"
echo "|               CONFIG SLOWDNS               |"
echo "+--------------------------------------------+"

read -p "Entrez le NameServer (NS) : " NAMESERVER

echo ""
echo "Configuration de SlowDNS..."
echo "Clé publique : $PUB_KEY"
echo "NameServer : $NAMESERVER"

# Ici vous pouvez ajouter les commandes réelles pour installer et configurer SlowDNS
# Exemple fictif :
echo "Installation des services SlowDNS..."
sleep 2
echo "Service SlowDNS démarré avec succès."
