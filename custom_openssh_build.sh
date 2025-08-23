#!/bin/bash

set -e

PATCH_STRING="SSH-2.0-Kighmu-tunnel_2.3"
OPENSSH_DIR="openssh-portable"

echo "Installation des dépendances de compilation..."
sudo apt-get update
sudo apt-get install -y build-essential zlib1g-dev libssl-dev libpam0g-dev autoconf automake libtool git

echo "Clonage ou mise à jour du dépôt OpenSSH..."
if [ ! -d "$OPENSSH_DIR" ]; then
  git clone https://github.com/openssh/openssh-portable.git "$OPENSSH_DIR"
fi

cd "$OPENSSH_DIR"
git pull

echo "Sauvegarde de l'ancien sshd..."
if [ -f /usr/sbin/sshd ]; then
    sudo cp /usr/sbin/sshd /usr/sbin/sshd.bak-$(date +%F-%T)
    echo "Sauvegarde effectuée : /usr/sbin/sshd.bak-$(date +%F-%T)"
fi

echo "Modification de la chaîne d’identification OpenSSH..."
sed -i "s/\"SSH-2.0-OpenSSH_[^\"]*\"/\"$PATCH_STRING\"/" version.h

echo "Compilation et installation..."
autoreconf
./configure --prefix=/usr --sysconfdir=/etc/ssh
make
sudo make install

echo "Redémarrage du service sshd..."
sudo systemctl restart sshd

echo "OpenSSH customisé installé avec succès avec l'identification : $PATCH_STRING"
echo "En cas de problème, restaure l'ancien sshd avec : sudo cp /usr/sbin/sshd.bak-* /usr/sbin/sshd && sudo systemctl restart sshd"
