#!/bin/bash
# badvpn.sh
# Script d'installation et configuration de BadVPN sur VPS

set -e

echo "Mise à jour des paquets..."
apt-get update -y

echo "Installation des dépendances nécessaires..."
apt-get install -y cmake build-essential git

echo "Clonage du dépôt BadVPN..."
if [ ! -d "/root/badvpn" ]; then
    git clone https://github.com/ambrop72/badvpn.git /root/badvpn
else
    echo "Le dossier BadVPN existe déjà, mise à jour du dépôt..."
    cd /root/badvpn && git pull
fi

echo "Compilation de BadVPN..."
cd /root/badvpn
cmake -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 .
make

echo "Copie binaire badvpn-udpgw dans /usr/local/bin/..."
cp badvpn-udpgw /usr/local/bin/

echo "Lancement de BadVPN UDPGW sur les ports 7200 et 7300..."
# Arrêt des éventuels processus existants sur ces ports
pkill -f "badvpn-udpgw --listen-addr 127.0.0.1:7200" || true
pkill -f "badvpn-udpgw --listen-addr 127.0.0.1:7300" || true

# Démarrage en arrière-plan
nohup /usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:7200 > /dev/null 2>&1 &
nohup /usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 > /dev/null 2>&1 &

echo "BadVPN installé et lancé sur les ports 7200 et 7300."
