#!/bin/bash
# menu7.sh
# Blocage des torrents

echo "+--------------------------------------------+"
echo "|              BLOCAGE DE TORRENTS           |"
echo "+--------------------------------------------+"

read -p "Voulez-vous activer le blocage des torrents ? [oui/non] : " confirm

case "$confirm" in
    [oO][uU][iI]|[yY][eE][sS])
        echo "Activation du blocage des torrents..."

        # Exemple avec iptables pour bloquer certains ports et protocoles BitTorrent
        iptables -A OUTPUT -p tcp --dport 6881:6889 -j DROP
        iptables -A OUTPUT -p udp --dport 1024:65535 -j DROP

        echo "Blocage des torrents activé."
        ;;
    [nN][oO]|[nN])
        echo "Blocage des torrents non activé."
        ;;
    *)
        echo "Réponse invalide. Action annulée."
        ;;
esac
