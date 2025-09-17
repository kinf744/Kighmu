#!/usr/bin/env bash
# ==============================================
# Kighmu VPS Manager - Script d'installation
# Copyright (c) 2025 Kinf744
# Licence MIT (version française)
# ==============================================

set -o errexit
set -o nounset
set -o pipefail

echo "Vérification et installation de curl si nécessaire..."

install_package_if_missing() {
  local pkg=$1
  echo "Installation de $pkg..."
  set +e
  apt-get install -y "$pkg"
  if [[ $? -ne 0 ]]; then
    echo "⚠️ Attention : échec de l'installation du paquet $pkg, le script continue..."
  else
    echo "Le paquet $pkg a été installé avec succès."
  fi
  set -e
}

apt-get update -y
apt-get install dnsutils -y

install_package_if_missing "curl"

echo "+--------------------------------------------+"
echo "|             INSTALLATION VPS               |"
echo "+--------------------------------------------+"

read -r -p "Veuillez entrer votre nom de domaine (doit pointer vers l'IP de ce serveur) : " DOMAIN

if [[ -z "$DOMAIN" ]]; then
  echo "Erreur : vous devez entrer un nom de domaine valide."
  exit 1
fi

IP_PUBLIC=$(curl -s https://api.ipify.org)
echo "Votre IP publique détectée est : $IP_PUBLIC"

DOMAIN_IP=$(dig +short "$DOMAIN" | tail -n1)
if [[ "$DOMAIN_IP" != "$IP_PUBLIC" ]]; then
  echo "Attention : le domaine $DOMAIN ne pointe pas vers l’IP $IP_PUBLIC."
  echo "Assurez-vous que le domaine est correctement configuré avant de continuer."
  read -r -p "Voulez-vous continuer quand même ? [oui/non] : " choix
  if [[ ! "$choix" =~ ^(o|oui)$ ]]; then
    echo "Installation arrêtée."
    exit 1
  fi
fi

export DOMAIN

echo "=============================================="
echo " 🚀 Installation des paquets essentiels..."
echo "=============================================="

apt update -y && apt upgrade -y

apt install -y sudo
apt install -y bsdmainutils
apt install -y zip
apt install -y unzip
apt install -y ufw
apt install -y curl
apt install -y python3
apt install -y python3-pip
apt install -y openssl
apt install -y screen
apt install -y cron
apt install -y iptables
apt install -y lsof
apt install -y pv
apt install -y nano
apt install -y at
apt install -y gawk
apt install -y grep
apt install -y bc
apt install -y jq
apt install -y npm
apt install -y nodejs
apt install -y socat
apt install -y netcat
apt install -y netcat-traditional
apt install -y net-tools
apt install -y cowsay
apt install -y figlet
apt install -y dnsutils
apt install -y wget
apt install -y psmisc
apt install -y python3-setuptools
apt install -y qrencode
apt install -y gcc
apt install -y make
apt install -y perl
apt install -y systemd
apt install -y tcpdump
apt install -y iptables
apt install -y iproute2
apt install -y net-tools
apt install -y tmux
apt install -y git
apt install -y iptables-persistent
apt install -y build-essential
apt install -y libssl-dev
apt install -y software-properties-common

apt autoremove -y
apt clean

# Configuration ufw
ufw allow OpenSSH
ufw allow 22
ufw allow 80
ufw allow 443
ufw allow 5300
ufw allow 54000
ufw allow 8080
ufw --force enable

echo "=============================================="
echo " 🚀 Installation de Kighmu VPS Manager..."
echo "=============================================="

INSTALL_DIR="$HOME/Kighmu"
mkdir -p "$INSTALL_DIR"

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
  "KIGHMUPROXY.py"
  "udp_custom.sh"
  "dropbear.sh"
  "ssl.sh"
  "badvpn.sh"
  "system_dns.sh"
  "install_modes.sh"
  "show_resources.sh"
  "nginx.sh"
  "setup_ssh_config.sh"
  "create_ssh_user.sh"
  "menu4_2.sh"
)

BASE_URL="https://raw.githubusercontent.com/kinf744/Kighmu/main"

for file in "${FILES[@]}"; do
  echo "Téléchargement de $file ..."
  wget -q --show-progress -O "$INSTALL_DIR/$file" "$BASE_URL/$file"
  if [[ ! -s "$INSTALL_DIR/$file" ]]; then
    echo "⚠️ Erreur : le fichier $file n'a pas été téléchargé correctement ou est vide, mais le script continue..."
  else
    chmod +x "$INSTALL_DIR/$file"
  fi
done

# Récupération dynamique du NS depuis la configuration DNS locale du système
NS=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)
if [[ -z "$NS" ]]; then
  echo "⚠️ Erreur : aucun serveur DNS trouvé dans /etc/resolv.conf, continuez prudemment."
fi

# Lecture et formatage de la clé publique SlowDNS
SLOWDNS_PUBKEY="/etc/slowdns/server.pub"
if [[ -f "$SLOWDNS_PUBKEY" ]]; then
  PUBLIC_KEY=$(sed ':a;N;$!ba;s/\n/\\n/g' "$SLOWDNS_PUBKEY")
else
  PUBLIC_KEY="Clé publique SlowDNS non trouvée"
fi

# Création du fichier ~/.kighmu_info avec les infos globales nécessaires
cat > ~/.kighmu_info <<EOF
DOMAIN=$DOMAIN
NS=$NS
PUBLIC_KEY="$PUBLIC_KEY"
EOF

chmod 600 ~/.kighmu_info
echo "Fichier ~/.kighmu_info créé avec succès et permissions sécurisées."

run_script() {
  local script_path=$1
  echo "🚀 Lancement du script : $script_path"
  set +e
  bash "$script_path"
  if [[ $? -ne 0 ]]; then
    echo "⚠️ Attention : $script_path a rencontré une erreur, mais l'installation continue..."
  else
    echo "✅ $script_path exécuté avec succès."
  fi
  set -e
}

echo "🚀 Application de la configuration SSH personnalisée..."
chmod +x "$INSTALL_DIR/setup_ssh_config.sh"
run_script "sudo $INSTALL_DIR/setup_ssh_config.sh"

echo "🚀 Script de création utilisateur SSH disponible : $INSTALL_DIR/create_ssh_user.sh"
echo "Tu peux le lancer manuellement quand tu veux."

if ! grep -q "alias kighmu=" ~/.bashrc; then
  echo "alias kighmu='$INSTALL_DIR/kighmu.sh'" >> ~/.bashrc
  echo "Alias kighmu ajouté dans ~/.bashrc"
fi

if ! grep -q "/usr/local/bin" ~/.bashrc; then
  echo 'export PATH=$PATH:/usr/local/bin' >> ~/.bashrc
  echo "Ajout de /usr/local/bin au PATH dans ~/.bashrc"
fi

# Création du script kighmu-panel.sh dans /usr/local/bin
cat > /usr/local/bin/kighmu-panel.sh << 'EOF'
#!/bin/bash

clear

BLUE='\033[0;34m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${BLUE}
K   K  III  GGG  H   H M   M U   U
K  K    I  G     H   H MM MM U   U
KKK     I  G  GG HHHHH M M M U   U
K  K    I  G   G H   H M   M U   U
K   K  III  GGG  H   H M   M  UUU
${NC}"

echo
echo -e "Saisir et valider: ${YELLOW}source ~/.bashrc${NC}"

echo -e "${GREEN}Version du script : 2.5${NC}"
echo -e "${BLUE}Inbox Telegramme : @KIGHMU${NC}"
echo
echo -e "Pour ouvrir le panneau de contrôle principal, tapez : ${YELLOW}kighmu${NC}"
echo
EOF

chmod +x /usr/local/bin/kighmu-panel.sh

# Ajout automatique au démarrage du shell du panneau avec nettoyage écran
if ! grep -q "kighmu-panel.sh" ~/.bashrc; then
  echo -e "\n# Affichage automatique du panneau KIGHMU au démarrage\nclear\n/usr/local/bin/kighmu-panel.sh\n" >> ~/.bashrc
fi

# Lancement immédiat une fois après installation
/usr/local/bin/kighmu-panel.sh
