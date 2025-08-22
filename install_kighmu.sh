#!/bin/bash
# ==============================================
# Kighmu VPS Manager - Script d'installation modifié avec SlowDNS par screen
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

apt update && apt upgrade -y

apt install -y \
dnsutils net-tools wget sudo iptables ufw screen \
openssl openssl-blacklist psmisc \
nginx certbot python3-certbot-nginx \
dropbear badvpn \
python3 python3-pip python3-setuptools \
wireguard-tools qrencode \
gcc make perl \
software-properties-common socat

echo "=============================================="
echo " 🚀 Installation des dépendances supplémentaires..."
echo "=============================================="

if ! command -v lsof >/dev/null 2>&1; then
    echo "lsof non trouvé, installation en cours..."
    apt update
    apt install -y lsof
fi

if [ ! -f /etc/iptables/rules.v4 ]; then
    echo "Création du fichier /etc/iptables/rules.v4 manquant..."
    mkdir -p /etc/iptables
    touch /etc/iptables/rules.v4
fi

INSTALL_DIR="$HOME/Kighmu"
SLOWDNS_SCRIPT="$INSTALL_DIR/slowdns.sh"
if [ ! -x "/usr/local/bin/slowdns.sh" ] && [ -x "$SLOWDNS_SCRIPT" ]; then
    echo "Création du lien symbolique /usr/local/bin/slowdns.sh ..."
    ln -s "$SLOWDNS_SCRIPT" /usr/local/bin/slowdns.sh
    chmod +x /usr/local/bin/slowdns.sh
fi

ufw allow OpenSSH
ufw allow 22
ufw allow 80
ufw allow 443
ufw --force enable

echo "=============================================="
echo " 🚀 Installation de Kighmu VPS Manager..."
echo "=============================================="

mkdir -p "$INSTALL_DIR" || { echo "Erreur : impossible de créer le dossier $INSTALL_DIR"; exit 1; }

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

run_script "$INSTALL_DIR/dropbear.sh"
run_script "$INSTALL_DIR/ssl.sh"
run_script "$INSTALL_DIR/badvpn.sh"
run_script "$INSTALL_DIR/system_dns.sh"
run_script "$INSTALL_DIR/nginx.sh"
run_script "$INSTALL_DIR/socks_python.sh"
run_script "$INSTALL_DIR/slowdns.sh"
run_script "$INSTALL_DIR/udp_custom.sh"

echo "=============================================="
echo " 🚀 Installation et configuration SlowDNS..."
echo "=============================================="

SLOWDNS_DIR="/etc/slowdns"
mkdir -p "$SLOWDNS_DIR"

read -p "Entrez le NameServer (NS) (ex: ns.example.com) : " NS
if [[ -z "$NS" ]]; then
    echo "Erreur : NameServer invalide."
    exit 1
fi
echo "$NS" > "$SLOWDNS_DIR/ns.conf"

DNS_BIN="/usr/local/bin/sldns-server"
if [ ! -x "$DNS_BIN" ]; then
    echo "Téléchargement du binaire slowdns..."
    wget -q -O "$DNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
    chmod +x "$DNS_BIN"
fi

echo "Génération des clés SlowDNS à chaque installation..."
"$DNS_BIN" -gen-key -privkey-file "$SLOWDNS_DIR/server.key" -pubkey-file "$SLOWDNS_DIR/server.pub"
chmod 600 "$SLOWDNS_DIR/server.key"
chmod 644 "$SLOWDNS_DIR/server.pub"

# Arrêt propre de l'ancienne session slowdns si existante
if screen -list | grep -q "slowdns_session"; then
    echo "Arrêt de l'ancienne session screen slowdns_session..."
    screen -S slowdns_session -X quit
    sleep 2
fi

configure_iptables() {
    interface=$(ip a | awk '/state UP/{print $2}' | cut -d: -f1 | head -1)
    echo "Configuration iptables pour rediriger UDP port 53 vers 5300 (port SlowDNS)..."
    sudo iptables -I INPUT -p udp --dport 5300 -j ACCEPT
    sudo iptables -t nat -I PREROUTING -i $interface -p udp --dport 53 -j REDIRECT --to-ports 5300
    sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
}

configure_iptables

echo "Démarrage du serveur SlowDNS dans screen session détachée..."
screen -dmS slowdns_session "$DNS_BIN" -udp ":5300" -privkey-file "$SLOWDNS_DIR/server.key" "$NS" 0.0.0.0:22

sleep 3

if pgrep -f "sldns-server" > /dev/null; then
    echo "SlowDNS démarré avec succès sur UDP port 5300."
    echo "Pour rattacher la session screen : screen -r slowdns_session"
else
    echo "ERREUR : Le service SlowDNS n'a pas pu démarrer."
    exit 1
fi

if [ "$(sysctl -n net.ipv4.ip_forward)" -ne 1 ]; then
    echo "Activation du routage IP..."
    sudo sysctl -w net.ipv4.ip_forward=1
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
    fi
fi

if command -v ufw >/dev/null 2>&1; then
    echo "Ouverture du port UDP 5300 dans ufw..."
    sudo ufw allow 5300/udp
    sudo ufw reload
else
    echo "UFW non installé. Merci de vérifier manuellement l'ouverture du port UDP 5300."
fi

echo "+--------------------------------------------+"
echo " Clé publique SlowDNS (à communiquer au client) :"
cat "$SLOWDNS_DIR/server.pub"
echo "+--------------------------------------------+"

echo
echo "=============================================="
echo " ✅ Installation terminée !"
echo " Pour lancer Kighmu, utilisez la commande : kighmu"
echo
echo " ⚠️ Pour que l'alias soit pris en compte, ouvre un nouveau terminal ou exécute : source ~/.bashrc"
echo "=============================================="
