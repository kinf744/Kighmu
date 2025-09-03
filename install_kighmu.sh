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

install_package_ignore_error() {
  local pkg=$1
  echo "Installation de $pkg..."
  set +e
  apt-get install -y "$pkg"
  local status=$?
  set -e
  if [[ $status -ne 0 ]]; then
    echo "⚠️ Attention : échec de l'installation du paquet $pkg, mais le script continue..."
  else
    echo "Le paquet $pkg a été installé avec succès."
  fi
  return $status
}

echo "Mise à jour de la liste des paquets..."
apt-get update -y

# Attente du déverrouillage dpkg s'il est actif
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ; do
  echo "Attente du déverrouillage de dpkg..."
  sleep 2
done

echo "Vérification des paquets cassés et configuration en attente..."
set +e
sudo dpkg --configure -a
sudo apt-get install -f -y
set -e

install_package_ignore_error dnsutils
install_package_ignore_error curl

echo "Conversion des clés OpenSSH au format compatible Dropbear..."

convert_key_if_exists() {
  local key_type=$1
  local openssh_key="/etc/ssh/ssh_host_${key_type}_key"
  local dropbear_key="/etc/dropbear/dropbear_${key_type}_host_key"
  if [[ -f $openssh_key ]]; then
    echo "Conversion de la clé $openssh_key..."
    set +e
    ssh-keygen -p -m PEM -f "$openssh_key" -N ""
    dropbearconvert openssh dropbear "$openssh_key" "$dropbear_key"
    local status=$?
    set -e
    if [[ $status -ne 0 ]]; then
      echo "Erreur conversion clé $key_type, génération d'une nouvelle clé Dropbear..."
      dropbearkey -t "$key_type" -f "$dropbear_key"
    fi
  else
    echo "Clé $openssh_key non trouvée, génération d'une nouvelle clé Dropbear..."
    dropbearkey -t "$key_type" -f "$dropbear_key"
  fi
}

convert_key_if_exists "rsa"
convert_key_if_exists "ecdsa"
convert_key_if_exists "ed25519"

set +e
sudo dpkg-reconfigure openssh-server
sudo dpkg-reconfigure dropbear
set -e

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

# Liste des paquets essentiels
PACKAGES=(
  sudo bsdmainutils zip unzip ufw curl python3 python3-pip openssl screen cron iptables lsof pv boxes nano at mlocate gawk grep bc jq npm nodejs socat netcat netcat-traditional net-tools cowsay figlet lolcat dnsutils wget psmisc nginx dropbear python3-setuptools wireguard-tools qrencode gcc make perl systemd tcpdump iproute2 tmux git build-essential libssl-dev software-properties-common
)

for pkg in "${PACKAGES[@]}"; do
  install_package_ignore_error "$pkg"
done

apt autoremove -y
apt clean

echo "Configuration du pare-feu ufw..."

set +e
ufw allow OpenSSH
ufw allow 22
ufw allow 80
ufw allow 443
ufw allow 5300
ufw allow 54000
ufw allow 8080
ufw --force enable
set -e

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
  wget -q --show-progress -O "$INSTALL_DIR/$file" "$BASE_URL/$file" || echo "⚠️ Erreur téléchargement $file"
  if [[ ! -s "$INSTALL_DIR/$file" ]]; then
    echo "⚠️ Le fichier $file est vide ou absent, mais le script continue..."
  else
    chmod +x "$INSTALL_DIR/$file"
  fi
done

NS=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)
if [[ -z "$NS" ]]; then
  echo "⚠️ Aucun serveur DNS trouvé dans /etc/resolv.conf"
fi

SLOWDNS_PUBKEY="/etc/slowdns/server.pub"
if [[ -f "$SLOWDNS_PUBKEY" ]]; then
  PUBLIC_KEY=$(sed ':a;N;$!ba;s/\n/\\n/g' "$SLOWDNS_PUBKEY")
else
  PUBLIC_KEY="Clé publique SlowDNS non trouvée"
fi

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
  local status=$?
  set -e
  if [[ $status -ne 0 ]]; then
    echo "⚠️ Attention : $script_path a rencontré une erreur, mais le script continue..."
  else
    echo "✅ $script_path exécuté avec succès."
  fi
  return $status
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

if ! grep -q "kighmu-panel.sh" ~/.bashrc; then
  echo -e "\n# Affichage automatique du panneau KIGHMU au démarrage\nclear\n/usr/local/bin/kighmu-panel.sh\n" >> ~/.bashrc
fi

/usr/local/bin/kighmu-panel.sh
