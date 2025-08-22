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

# Demander le nom de domaine
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

apt update && apt upgrade -y

apt install -y \
dnsutils net-tools wget sudo iptables ufw \
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

# Liste des fichiers à télécharger
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
    "menu_6.sh"
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
    "xray_installe.sh"
    "v2ray_slowdns.sh"
    "v2ray_slowdns_install.sh"
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

# Exécution automatique des scripts d’installation supplémentaires
run_script "$INSTALL_DIR/dropbear.sh"
run_script "$INSTALL_DIR/ssl.sh"
run_script "$INSTALL_DIR/badvpn.sh"
run_script "$INSTALL_DIR/system_dns.sh"
run_script "$INSTALL_DIR/nginx.sh"
run_script "$INSTALL_DIR/socks_python.sh"
run_script "$INSTALL_DIR/slowdns.sh"
run_script "$INSTALL_DIR/udp_custom.sh"

# Création du dossier SlowDNS
SLOWDNS_DIR="/etc/slowdns"
mkdir -p "$SLOWDNS_DIR"

# Téléchargement du binaire SlowDNS si nécessaire
DNS_BIN="/usr/local/bin/dns-server"
if [ ! -x "$DNS_BIN" ]; then
    echo "Téléchargement du binaire dns-server..."
    wget -q -O "$DNS_BIN" https://github.com/sbatrow/DARKSSH-MANAGER/raw/main/Modulos/dns-server
    chmod +x "$DNS_BIN"
fi

# Génération automatique des clés SlowDNS si absentes
if [ ! -s "$SLOWDNS_DIR/server.key" ] || [ ! -s "$SLOWDNS_DIR/server.pub" ]; then
    echo "Clés SlowDNS manquantes ou vides, génération automatique..."
    "$DNS_BIN" -gen-key -privkey-file "$SLOWDNS_DIR/server.key" -pubkey-file "$SLOWDNS_DIR/server.pub"
    chmod 600 "$SLOWDNS_DIR/server.key"
    chmod 644 "$SLOWDNS_DIR/server.pub"
    echo "Clés SlowDNS générées automatiquement."
else
    echo "Clés SlowDNS déjà présentes."
fi

# Lecture dynamique de la clé publique et NS pour V2Ray SlowDNS
SLOWDNS_PUBKEY=$(cat "$SLOWDNS_DIR/server.pub")
SLOWDNS_NS=$(cat "/etc/slowdns/ns.conf" 2>/dev/null || echo "$DOMAIN")
export SLOWDNS_PUBKEY
export SLOWDNS_NS

# Lancement du tunnel V2Ray SlowDNS
run_script "$INSTALL_DIR/v2ray_slowdns_install.sh"

# Configuration IPtables et démarrage SlowDNS (SSH tunnel) inchangée
interface=$(ip a | awk '/state UP/{print $2}' | cut -d: -f1 | head -1)
iptables -F
iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -t nat -I PREROUTING -i $interface -p udp --dport 53 -j REDIRECT --to-ports 5300

ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
screen -dmS slowdns "$DNS_BIN" -udp :5300 -privkey-file "$SLOWDNS_DIR/server.key" "$DOMAIN" 0.0.0.0:$ssh_port

# Informations finales
echo "+--------------------------------------------+"
echo " SlowDNS installé et lancé avec succès !"
echo " Clé publique (à utiliser côté client) :"
echo "$SLOWDNS_PUBKEY"
echo ""
echo "Commande client SlowDNS à utiliser :"
echo "curl -sO https://github.com/khaledagn/DNS-AGN/raw/main/files/slowdns && chmod +x slowdns && ./slowdns $DOMAIN $SLOWDNS_PUBKEY"
echo "+--------------------------------------------+"

# Configuration SSH personnalisée et alias kighmu (inchangés)
chmod +x "$INSTALL_DIR/setup_ssh_config.sh"
chmod +x "$INSTALL_DIR/xray_installe.sh"
run_script "sudo $INSTALL_DIR/setup_ssh_config.sh"

if ! grep -q "alias kighmu=" ~/.bashrc; then
    echo "alias kighmu='$INSTALL_DIR/kighmu.sh'" >> ~/.bashrc
fi

if ! grep -q "/usr/local/bin" ~/.bashrc; then
    echo 'export PATH=$PATH:/usr/local/bin' >> ~/.bashrc
fi

# Génération automatique du fichier ~/.kighmu_info
cat > ~/.kighmu_info <<EOF
DOMAIN=$DOMAIN
PUBLIC_KEY="$SLOWDNS_PUBKEY"
EOF
chmod 600 ~/.kighmu_info

echo "=============================================="
echo " ✅ Installation terminée !"
echo " Pour lancer Kighmu, utilisez la commande : kighmu"
echo " - Ouvre un nouveau terminal, ou source ~/.bashrc"
echo "=============================================="
