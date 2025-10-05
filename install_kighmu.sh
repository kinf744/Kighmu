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
apt-get install ufw -y

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

install_package_if_missing "sudo"
install_package_if_missing "bsdmainutils"
install_package_if_missing "zip"
install_package_if_missing "unzip"
install_package_if_missing "ufw"
install_package_if_missing "curl"
install_package_if_missing "python3"
install_package_if_missing "python3-pip"
install_package_if_missing "openssl"
install_package_if_missing "screen"
install_package_if_missing "cron"
install_package_if_missing "iptables"
install_package_if_missing "lsof"
install_package_if_missing "pv"
install_package_if_missing "nano"
install_package_if_missing "at"
install_package_if_missing "gawk"
install_package_if_missing "grep"
install_package_if_missing "bc"
install_package_if_missing "jq"
install_package_if_missing "npm"
install_package_if_missing "nodejs"
install_package_if_missing "socat"
install_package_if_missing "netcat-openbsd"
install_package_if_missing "net-tools"
install_package_if_missing "cowsay"
install_package_if_missing "figlet"
install_package_if_missing "dnsutils"
install_package_if_missing "wget"
install_package_if_missing "psmisc"
install_package_if_missing "python3-setuptools"
install_package_if_missing "qrencode"
install_package_if_missing "gcc"
install_package_if_missing "make"
install_package_if_missing "perl"
install_package_if_missing "systemd"
install_package_if_missing "tcpdump"
install_package_if_missing "iptables"
install_package_if_missing "iproute2"
install_package_if_missing "net-tools"
install_package_if_missing "tmux"
install_package_if_missing "git"
install_package_if_missing "vnstat"
install_package_if_missing "iftop"
install_package_if_missing "bmon"
install_package_if_missing "nethogs"
install_package_if_missing "iptables-persistent"
install_package_if_missing "build-essential"
install_package_if_missing "libssl-dev"
install_package_if_missing "software-properties-common"

apt autoremove -y
apt clean

echo "Configuration du pare-feu ufw..."

export PATH=$PATH:/usr/sbin

if ! command -v ufw &> /dev/null; then
  echo "⚠️ ufw n'est pas installé ou non disponible, impossible de configurer le pare-feu."
else
  echo "Activation et configuration des règles ufw..."

  ufw default deny incoming
  ufw default allow outgoing

  ufw allow OpenSSH
  ufw allow 22
  ufw allow 80
  ufw allow 443
  ufw allow 5300
  ufw allow 54000
  ufw allow 8080

  ufw --force enable

  echo "Pare-feu ufw configuré avec succès."
fi

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
  "menu_4.sh"
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
  "ws2_proxy.py"
  "POpen.py"
  "sockspy.sh"
  "hysteria.sh"
  "ShellBot.sh"
  "botssh.sh"
  "menu_6.sh"
  "xray_installe.sh"
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

# Récupération dynamique du NS depuis la configuration DNS locale
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

# Création du script kighmu-panel.sh dans /usr/local/bin (nouvelle version avec KIGHMU VPS en rouge vif)
cat > /usr/local/bin/kighmu-panel.sh << 'EOF'
#!/bin/bash

clear

RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${RED}
K   K  III  GGG  H   H M   M U   U     V   V PPPP   SSS
K  K    I  G     H   H MM MM U   U     V   V P   P S
KKK     I  G  GG HHHHH M M M U   U     V   V PPPP   SSS
K  K    I  G   G H   H M   M U   U      V V  P         S
K   K  III  GGG  H   H M   M  UUU        V   P      SSS
${NC}"

echo
echo -e "Saisir et valider: ${YELLOW}source ~/.bashrc${NC}"

echo -e "${GREEN}Version du script : 2.5${NC}"
echo -e "${CYAN}Inbox Telegramme : @KIGHMU${NC}"
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
