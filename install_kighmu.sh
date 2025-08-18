#!/bin/bash
# ==============================================
# Kighmu VPS Manager - Script d'installation
# Copyright (c) 2025 Kinf744
# Licence MIT (version française)
# ==============================================

echo "+--------------------------------------------+"
echo "|             INSTALLATION VPS               |"
echo "+--------------------------------------------+"

# Demander le nom de domaine qui pointe vers l’IP du serveur
read -p "Veuillez entrer votre nom de domaine (doit pointer vers l'IP de ce serveur) : " DOMAIN

if [ -z "$DOMAIN" ]; then
  echo "Erreur : vous devez entrer un nom de domaine valide."
  exit 1
fi

IP_PUBLIC=$(curl -s https://api.ipify.org)
echo "Votre IP publique détectée est : $IP_PUBLIC"

DOMAIN_IP=$(dig +short "$DOMAIN" | tail -n1)
if [ "$DOMAIN_IP" != "$IP_PUBLIC" ]; then
  echo "Attention : le domaine $DOMAIN ne pointe pas vers l’IP $IP_PUBLIC."
  echo "Assurez-vous que le domaine est correctement configuré avant de continuer."
  read -p "Voulez-vous continuer quand même ? [oui/non] : " choix
  if [[ ! "$choix" =~ ^(o|oui)$ ]]; then
    echo "Installation arrêtée."
    exit 1
  fi
fi

# Exporter la variable pour que les scripts enfants y aient accès
export DOMAIN

echo "=============================================="
echo " 🚀 Installation des paquets essentiels..."
echo "=============================================="

apt update && apt upgrade -y

apt install -y \
curl dnsutils net-tools wget sudo iptables ufw \
openssl openssl-blacklist psmisc \
nginx certbot python3-certbot-nginx \
dropbear badvpn \
python3 python3-pip python3-setuptools \
wireguard-tools qrencode \
gcc make perl \
software-properties-common socat

# Activer et configurer UFW
ufw allow OpenSSH
ufw allow 22
ufw allow 80
ufw allow 443
ufw --force enable

echo "=============================================="
echo " 🚀 Installation de Kighmu VPS Manager..."
echo "=============================================="

# Création du dossier d'installation
INSTALL_DIR="$HOME/Kighmu"
mkdir -p "$INSTALL_DIR" || { echo "Erreur : impossible de créer le dossier $INSTALL_DIR"; exit 1; }

# Liste des fichiers à télécharger (ajout des nouveaux scripts)
FILES=(
    "install_kighmu.sh"
    "kighmu-manager.sh"
    "kighmu.sh"
    "menu1.sh"
    "menu2.sh"
    "menu3.sh"
    "menu4.sh"
    "menu5.sh"
    "menu6.sh"
    "menu7.sh"
    "slowdns.sh"
    "socks_python.sh"
    "udp_custom.sh"
    "dropbear.sh"
    "ssl.sh"
    "badvpn.sh"
    "system_dns.sh"
    "install_modes.sh"
    "show_resources.sh"
    "nginx.sh"
)

# URL de base du dépôt GitHub
BASE_URL="https://raw.githubusercontent.com/kinf744/Kighmu/main"

# Téléchargement et vérification de chaque fichier
for file in "${FILES[@]}"; do
    echo "Téléchargement de $file ..."
    wget -O "$INSTALL_DIR/$file" "$BASE_URL/$file"
    if [ ! -s "$INSTALL_DIR/$file" ]; then
        echo "Erreur : le fichier $file n'a pas été téléchargé correctement ou est vide !"
        exit 1
    fi
    chmod +x "$INSTALL_DIR/$file"
done

# Exécution automatique des scripts d’installation supplémentaires
echo "🚀 Lancement des installations automatiques complémentaires..."

bash "$INSTALL_DIR/dropbear.sh"
bash "$INSTALL_DIR/ssl.sh"
bash "$INSTALL_DIR/badvpn.sh"
bash "$INSTALL_DIR/system_dns.sh"
bash "$INSTALL_DIR/nginx.sh"
bash "$INSTALL_DIR/socks_python.sh"
bash "$INSTALL_DIR/slowdns.sh"
bash "$INSTALL_DIR/udp_custom.sh"

# Ajout alias kighmu dans ~/.bashrc s'il n'existe pas déjà
if ! grep -q "alias kighmu=" ~/.bashrc; then
    echo "alias kighmu='$INSTALL_DIR/kighmu.sh'" >> ~/.bashrc
    echo "Alias kighmu ajouté dans ~/.bashrc"
else
    echo "Alias kighmu déjà présent dans ~/.bashrc"
fi

# Ajouter /usr/local/bin au PATH si non présent dans ~/.bashrc
if ! grep -q "/usr/local/bin" ~/.bashrc; then
    echo 'export PATH=$PATH:/usr/local/bin' >> ~/.bashrc
    echo "Ajout de /usr/local/bin au PATH dans ~/.bashrc"
fi

echo
echo "=============================================="
echo " ✅ Installation terminée !"
echo " Pour lancer Kighmu, utilisez la commande : kighmu"
echo
echo " ⚠️ Pour que l'alias soit pris en compte :"
echo " - Ouvre un nouveau terminal, ou"
echo " - Exécute manuellement : source ~/.bashrc"
echo
echo "Tentative de rechargement automatique de ~/.bashrc dans cette session..."
source ~/.bashrc || echo "Le rechargement automatique a échoué, merci de le faire manuellement."
echo "=============================================="
