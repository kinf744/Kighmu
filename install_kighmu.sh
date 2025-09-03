#!/bin/bash
# ==============================================
# Kighmu VPS Manager - Script d'installation
# Copyright (c) 2025 Kinf744
# Licence MIT (version française)
# ==============================================

# Vérification de la présence de curl et installation si manquant
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
apt install -y boxes
apt install -y nano
apt install -y at
apt install -y mlocate
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
apt install -y lolcat
apt install -y dnsutils
apt install -y wget
apt install -y psmisc
apt install -y nginx
apt install -y dropbear
apt install -y badvpn
apt install -y python3-setuptools
apt install -y wireguard-tools
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
apt install -y build-essential
apt install -y libssl-dev
apt install -y software-properties-common

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

# Liste des fichiers à télécharger
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

# Fonction pour exécuter un script avec gestion d’erreur
run_script() {
    local script_path="$1"
    echo "🚀 Lancement du script : $script_path"
    if bash "$script_path"; then
        echo "✅ $script_path exécuté avec succès."
    else
        echo "⚠️ Attention : $script_path a rencontré une erreur. L'installation continue..."
    fi
}

# Ne lance aucun script automatiquement ici

# Ajout de l'exécution du script de configuration SSH
echo "🚀 Application de la configuration SSH personnalisée..."
chmod +x "$INSTALL_DIR/setup_ssh_config.sh"
run_script "sudo $INSTALL_DIR/setup_ssh_config.sh"

echo "🚀 Script de création utilisateur SSH disponible : $INSTALL_DIR/create_ssh_user.sh"
echo "Tu peux le lancer manuellement quand tu veux."

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

# Création du script du panneau KIGHMU qui s'affichera automatiquement à la connexion
cat > /usr/local/bin/kighmu-panel.sh << 'EOF'
#!/bin/bash

cat << "EOT"

K   K  III  GGG  H   H M   M U   U
K  K    I  G     H   H MM MM U   U
KKK     I  G  GG HHHHH M M M U   U
K  K    I  G   G H   H M   M U   U
K   K  III  GGG  H   H M   M  UUU

EOT

echo "Pour ouvrir le panneau de contrôle principal, tapez : kighmu"
EOF

chmod +x /usr/local/bin/kighmu-panel.sh

# Ajout dans ~/.bashrc de la commande pour afficher le panneau automatiquement à chaque connexion
if ! grep -q "/usr/local/bin/kighmu-panel.sh" ~/.bashrc; then
    echo -e "\n# Affichage automatique du panneau Kighmu\nif [ -x /usr/local/bin/kighmu-panel.sh ]; then\n    /usr/local/bin/kighmu-panel.sh\nfi\n" >> ~/.bashrc
fi

echo
echo "=============================================="
echo " ✅ Installation terminée !"
echo
echo " ⚠️ Pour que l'alias soit pris en compte :"
echo " - Ouvre un nouveau terminal, ou"
echo " - Exécute manuellement : source ~/.bashrc"
echo
echo "Tentative de rechargement automatique de ~/.bashrc dans cette session..."
source ~/.bashrc || echo "Le rechargement automatique a échoué, merci de le faire manuellement."
echo "=============================================="
