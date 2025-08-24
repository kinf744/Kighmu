#!/bin/bash
set -e

echo "Mise à jour des paquets..."
apt-get update -y

echo "Installation des dépendances nécessaires..."
apt-get install -y git cmake build-essential

echo "Clonage du dépôt BadVPN..."
if [ ! -d "/root/badvpn" ]; then
    git clone https://github.com/ambrop72/badvpn.git /root/badvpn
else
    echo "Le dossier BadVPN existe déjà, mise à jour du dépôt..."
    cd /root/badvpn && git pull
fi

echo "Compilation de BadVPN uniquement UDPGW..."
cd /root/badvpn
mkdir -p build
cd build
cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1
make

echo "Installation du binaire badvpn-udpgw..."
cp ./udpgw/badvpn-udpgw /usr/local/bin/
chmod +x /usr/local/bin/badvpn-udpgw

echo "Création du service systemd pour badvpn-udpgw..."
cat << EOF > /etc/systemd/system/badvpn-udp.service
[Unit]
Description=BadVPN UDP Gateway
After=network.target

[Service]
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 0.0.0.0:54000 --max-clients 500
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

echo "Activation et démarrage du service badvpn-udp.service..."
systemctl daemon-reload
systemctl enable badvpn-udp.service
systemctl restart badvpn-udp.service

echo "Ouverture du port UDP 54000 dans le firewall (ufw)..."
ufw allow 54000/udp

echo "Installation et configuration terminées."
systemctl status badvpn-udp.service --no-pager
