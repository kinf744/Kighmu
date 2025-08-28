#!/bin/bash
# Installation compilée de badvpn (udpgw)

set -e

# Dépendances nécessaires
sudo apt update
sudo apt install -y cmake build-essential git

# Répertoire temporaire
TMPDIR=$(mktemp -d)
cd $TMPDIR

echo "Téléchargement de badvpn ..."
git clone https://github.com/ambrop72/badvpn.git
cd badvpn

# Compilation uniquement UDPGW (réduit les temps)
cmake -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 .
make

echo "Installation de badvpn-udpgw ..."
sudo cp badvpn-udpgw /usr/local/bin/
sudo chmod +x /usr/local/bin/badvpn-udpgw

# Nettoyage
cd ~
rm -rf $TMPDIR

# Lancement en background (exemple sur port 7300)
echo "Lancement de badvpn-udpgw sur le port 7300 ..."
nohup sudo badvpn-udpgw --listen-addr 0.0.0.0:7300 > /dev/null 2>&1 &

echo "Installation terminée. badvpn-udpgw est opérationnel sur le port 7300."
echo "Vous pouvez modifier le port ou lancer ce service dans un screen ou systemd si besoin."

