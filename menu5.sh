#!/bin/bash
# menu5.sh
# Installation et gestion des modes spéciaux

echo "+--------------------------------------------+"
echo "|        INSTALLATION DES MODES SPÉCIAUX    |"
echo "+--------------------------------------------+"

# Détection IP et uptime
HOST_IP=$(curl -s https://api.ipify.org)
UPTIME=$(uptime -p)

echo "IP: $HOST_IP | Uptime: $UPTIME"
echo ""

# Modes et statuts (exemple de base, à compléter selon installation réelle)
declare -A modes
modes=( 
    ["Openssh"]="déjà installé"
    ["Dropbear"]="déjà installé"
    ["SlowDNS"]="déjà installé"
    ["UDP Custom"]="non installé"
    ["SOCKS/Python"]="actif"
    ["SSL/TLS"]="prêt à installer"
    ["BadVPN"]="en configuration"
)

# Afficher le menu des modes
i=1
for mode in "${!modes[@]}"; do
    status=${modes[$mode]}
    printf "%d. [%-7s] %s\n" "$i" "$status" "$mode"
    ((i++))
done
echo "8. Retour au menu principal"
echo ""

read -p "Entrez votre choix [1-8]: " choice

case $choice in
    1)
        echo "Openssh déjà installé."
        ;;
    2)
        echo "Dropbear déjà installé."
        ;;
    3)
        echo "SlowDNS déjà installé. Pour configurer, exécuter le script slowdns.sh séparément."
        ;;
    4)
        echo "UDP Custom non installé. Installer via udp_custom.sh."
        ;;
    5)
        echo "SOCKS/Python actif."
        ;;
    6)
        echo "SSL/TLS prêt à installer."
        ;;
    7)
        echo "BadVPN en configuration."
        ;;
    8)
        echo "Retour au menu principal..."
        ;;
    *)
        echo "Choix invalide."
        ;;
esac
