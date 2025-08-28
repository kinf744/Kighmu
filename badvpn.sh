#!/bin/bash
# Installation automatique de badvpn-udpgw compilé

set -e

echo "Installation des dépendances de compilation..."
sudo apt update
sudo apt install -y cmake build-essential git

TMPDIR=$(mktemp -d)
echo "Téléchargement du dépôt badvpn dans $TMPDIR..."
git clone https://github.com/ambrop72/badvpn.git "$TMPDIR/badvpn"

cd "$TMPDIR/badvpn"
echo "Compilation du module UDPGW..."
cmake -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 .
make

echo "Copie du binaire badvpn-udpgw dans /usr/local/bin/..."
sudo cp badvpn-udpgw /usr/local/bin/
sudo chmod +x /usr/local/bin/badvpn-udpgw

# Nettoyage
cd ~
rm -rf "$TMPDIR"

echo "Lancement de badvpn-udpgw en background sur le port 7300..."
nohup sudo badvpn-udpgw --listen-addr 0.0.0.0:7300 >/dev/null 2>&1 &

echo "Installation terminée. badvpn-udpgw est opérationnel sur le port 7300."
echo "Configure un screen ou systemd pour démarrer ce service automatiquement si besoin."
