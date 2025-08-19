#!/bin/bash
set -e

OPENSSH_VERSION="8.2p1"
CUSTOM_VERSION="Kighmu.tunnel_1.3"
SRC_DIR="openssh-$OPENSSH_VERSION"
TAR_FILE="$SRC_DIR.tar.gz"
SSHD_BIN="/usr/sbin/sshd"
BACKUP_SUFFIX=$(date +%F-%T)

echo "=== Préparation de l'environnement ==="
sudo apt update
sudo apt install -y build-essential zlib1g-dev libssl-dev libpam0g-dev wget

echo "=== Téléchargement des sources OpenSSH $OPENSSH_VERSION ==="
if [ ! -d "$SRC_DIR" ]; then
  wget -q "https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/$TAR_FILE"
  tar -xf "$TAR_FILE"
else
  echo "$SRC_DIR existe déjà, utilisation des sources existantes."
fi

echo "=== Modification de la version dans version.h ==="
VERSION_FILE="$SRC_DIR/version.h"
if grep -q 'SSH_VERSION' "$VERSION_FILE"; then
  sed -i "s/#define SSH_VERSION .*/#define SSH_VERSION \"$CUSTOM_VERSION\"/" "$VERSION_FILE"
else
  echo "Erreur: #define SSH_VERSION introuvable dans $VERSION_FILE"
  exit 1
fi

echo "=== Compilation OpenSSH ==="
cd "$SRC_DIR"

echo "Nettoyage d'anciennes compilations..."
make clean || true

./configure --prefix=/usr --sysconfdir=/etc/ssh --sbindir=/usr/sbin --bindir=/usr/bin --with-pam
make

echo "=== Sauvegarde du binaire sshd existant ==="
if [ -f "$SSHD_BIN" ]; then
  echo "Sauvegarde de $SSHD_BIN en $SSHD_BIN.bak-$BACKUP_SUFFIX"
  sudo cp "$SSHD_BIN" "$SSHD_BIN.bak-$BACKUP_SUFFIX"
fi

echo "=== Installation du nouvel OpenSSH compilé ==="
sudo make install

echo "=== Vérification de la nouvelle version compilée ==="
NEW_VERSION=$($SSHD_BIN -v 2>&1 || true)
if [[ "$NEW_VERSION" == *"$CUSTOM_VERSION"* ]]; then
  echo "Version personnalisée détectée dans le binaire sshd: $CUSTOM_VERSION"
else
  echo "Attention : la version personnalisée n'a pas été détectée."
  echo "Sortie sshd -v : $NEW_VERSION"
  echo "Abandon du redémarrage sshd."
  exit 1
fi

echo "=== Redémarrage du service sshd ==="
sudo systemctl restart sshd

echo "=== Vérification du redémarrage ==="
if systemctl is-active --quiet sshd; then
  echo "Le service sshd est actif."
else
  echo "Erreur : le service sshd n'a pas démarré correctement."
  exit 1
fi

echo "=== TEST CONNEXION CLIENT ==="
echo "Connectez-vous en SSH avec l'option -v depuis un client :"
echo "ssh -v utilisateur@serveur"
echo "La première ligne doit montrer : Server version: SSH-2.0-$CUSTOM_VERSION"

echo "=== Script terminé avec succès ==="
