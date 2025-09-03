#!/bin/bash
# ==============================================
# Kighmu VPS Manager - Script d'installation
# Copyright (c) 2025 Kinf744
# Licence MIT (version française)
# ==============================================

echo "Vérification de la présence de curl..."
if ! command -v curl >/dev/null 2>&1; then
    echo "curl non trouvé, installation en cours..."
    apt update
    apt install -y curl
    echo "Installation de curl terminée."
else
    echo "curl est déjà installé."
fi

echo "+--------------------------------------------+"
echo "|             INSTALLATION VPS               |"
echo "+--------------------------------------------+"

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

export DOMAIN

echo "=============================================="
echo " 🚀 Installation des paquets essentiels..."
echo "=============================================="

apt update -y && apt upgrade -y

packages=(
  sudo bsdmainutils zip unzip ufw curl python3 python3-pip openssl screen cron iptables
  lsof pv boxes nano at mlocate gawk grep bc jq npm nodejs socat netcat netcat-traditional
  net-tools cowsay figlet lolcat dnsutils wget psmisc nginx dropbear badvpn python3-setuptools
  wireguard-tools qrencode gcc make perl systemd tcpdump iproute2 tmux git build-essential
  libssl-dev software-properties-common
)

apt install -y "${packages[@]}"

ufw allow OpenSSH
ufw allow 22
ufw allow 80
ufw allow 443
ufw --force enable

echo "=============================================="
echo " 🚀 Installation de Kighmu VPS Manager..."
echo "=============================================="

INSTALL_DIR="$HOME/Kighmu"
mkdir -p "$INSTALL_DIR" || { echo "Erreur : impossible de créer le dossier $INSTALL_DIR"; exit 1; }

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
  "setup_ssh_config.sh"
  "create_ssh_user.sh"
)

BASE_URL="https://raw.githubusercontent.com/kinf744/Kighmu/main"

for file in "${FILES[@]}"; do
  echo "Téléchargement de $file ..."
  wget -O "$INSTALL_DIR/$file" "$BASE_URL/$file"
  if [ ! -s "$INSTALL_DIR/$file" ]; then
    echo "Erreur : le fichier $file n'a pas été téléchargé correctement ou est vide !"
    exit 1
  fi
  chmod +x "$INSTALL_DIR/$file"
done

run_script() {
  local script_path="$1"
  echo "🚀 Lancement du script : $script_path"
  if bash "$script_path"; then
    echo "✅ $script_path exécuté avec succès."
  else
    echo "⚠️ Attention : $script_path a rencontré une erreur. L'installation continue..."
  fi
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

echo -e "${YELLOW}KIGHMU${NC}"

echo -e "${GREEN}Version du script : 2.5${NC}"
echo
echo "Pour ouvrir le panneau de contrôle principal, tapez : kighmu"
EOF

chmod +x /usr/local/bin/kighmu-panel.sh

if ! grep -q "/usr/local/bin/kighmu-panel.sh" ~/.bashrc; then
  echo -e "\n# Affichage automatique du panneau KIGHMU\nif [ -x /usr/local/bin/kighmu-panel.sh ]; then\n    /usr/local/bin/kighmu-panel.sh\nfi\n" >> ~/.bashrc
fi

/usr/local/bin/kighmu-panel.sh
