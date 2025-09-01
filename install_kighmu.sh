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
    apt update -y
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

export DOMAIN

echo "=============================================="
echo " 🚀 Mise à jour et installation des paquets essentiels..."
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
apt install -y iptables-persistent
apt install -y systemd
apt install -y tcpdump
apt install -y iptables
apt install -y iproute2
apt install -y net-tools
apt install -y software-properties-common

apt autoremove -y
apt clean

echo "=============================================="
echo " 🚀 Préparation du mode HTTP/WS sans SSL..."
echo "=============================================="

# Installer le module python websockets si absent
if ! python3 -c "import websockets" &> /dev/null; then
    echo "Installation du module python websockets via pip3..."
    pip3 install websockets
else
    echo "Module python websockets déjà installé."
fi

echo "=============================================="
echo " 🚀 Installation et configuration du module Python pysocks et du proxy SOCKS"
echo "=============================================="

if ! python3 -c "import socks" &> /dev/null; then
    echo "Installation du module pysocks via pip3..."
    pip3 install pysocks
else
    echo "Module pysocks déjà installé."
fi

PROXY_SCRIPT_PATH="/usr/local/bin/KIGHMUPROXY.py"
if [ ! -f "$PROXY_SCRIPT_PATH" ]; then
    echo "Téléchargement du script KIGHMUPROXY.py..."
    wget -q -O "$PROXY_SCRIPT_PATH" "https://raw.githubusercontent.com/kinf744/Kighmu/main/KIGHMUPROXY.py"
    if [ $? -eq 0 ]; then
        chmod +x "$PROXY_SCRIPT_PATH"
        echo "Script téléchargé et rendu exécutable."
    else
        echo "Erreur: impossible de télécharger KIGHMUPROXY.py. Veuillez vérifier l'URL."
    fi
else
    echo "Script KIGHMUPROXY.py déjà présent."
fi

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
    "proxy_wss.py"
    "badvpn.sh"
    "system_dns.sh"
    "install_modes.sh"
    "show_resources.sh"
    "nginx.sh"
    "setup_ssh_config.sh"
    "create_ssh_user.sh"
    "menu2_et_expire.sh"
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
echo " 🚀 Lancement du mode HTTP/WS via screen..."
echo "=============================================="

# Nettoyer sessions écran existantes nommées proxy_wss
sessions=$(screen -ls | grep proxy_wss | awk '{print $1}')
if [ -n "$sessions" ]; then
    for session in $sessions; do
        screen -S "$session" -X quit
    done
    echo "Anciennes sessions proxy_wss supprimées."
fi

# Lancer proxy_wss.py dans screen détaché
screen -dmS proxy_wss /usr/bin/python3 "$INSTALL_DIR/proxy_wss.py"

sleep 2

# Vérifier que la session est bien lancée
if screen -ls | grep -q proxy_wss; then
    echo "Le serveur WS est démarré et fonctionne dans screen."
else
    echo "Erreur : le serveur WS n'a pas pu démarrer dans screen."
fi

echo "=============================================="
echo " 🚀 Installation et configuration SlowDNS..."
echo "=============================================="

SLOWDNS_DIR="/etc/slowdns"
mkdir -p "$SLOWDNS_DIR"

DNS_BIN="/usr/local/bin/dns-server"
if [ ! -x "$DNS_BIN" ]; then
    echo "Téléchargement du binaire dns-server..."
    wget -q -O "$DNS_BIN" https://github.com/sbatrow/DARKSSH-MANAGER/raw/main/Modulos/dns-server
    chmod +x "$DNS_BIN"
fi

if [ ! -f "$SLOWDNS_DIR/server.key" ] || [ ! -f "$SLOWDNS_DIR/server.pub" ]; then
    echo "Génération des clés SlowDNS..."
    "$DNS_BIN" -gen-key -privkey-file "$SLOWDNS_DIR/server.key" -pubkey-file "$SLOWDNS_DIR/server.pub"
    chmod 600 "$SLOWDNS_DIR/server.key"
    chmod 644 "$SLOWDNS_DIR/server.pub"
fi

interface=$(ip a | awk '/state UP/{print $2}' | cut -d: -f1 | head -1)
iptables -F
iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -t nat -I PREROUTING -i $interface -p udp --dport 53 -j REDIRECT --to-ports 5300

ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
screen -dmS slowdns "$DNS_BIN" -udp :5300 -privkey-file "$SLOWDNS_DIR/server.key" slowdns5.kighmup.ddns-ip.net 0.0.0.0:$ssh_port

echo "+--------------------------------------------+"
echo " SlowDNS installé et lancé avec succès !"
echo " Clé publique (à utiliser côté client) :"
cat "$SLOWDNS_DIR/server.pub"
echo ""
echo "Commande client SlowDNS à utiliser :"
echo "curl -sO https://github.com/khaledagn/DNS-AGN/raw/main/files/slowdns && chmod +x slowdns && ./slowdns slowdns5.kighmup.ddns-ip.net $(cat $SLOWDNS_DIR/server.pub)"
echo "+--------------------------------------------+"

echo "🚀 Application de la configuration SSH personnalisée..."
chmod +x "$INSTALL_DIR/setup_ssh_config.sh"
run_script "$INSTALL_DIR/setup_ssh_config.sh"

echo "🚀 Script de création utilisateur SSH disponible : $INSTALL_DIR/create_ssh_user.sh"
echo "Tu peux le lancer manuellement quand tu veux."

if ! grep -q "alias kighmu=" ~/.bashrc; then
    echo "alias kighmu='$INSTALL_DIR/kighmu.sh'" >> ~/.bashrc
    echo "Alias kighmu ajouté dans ~/.bashrc"
else
    echo "Alias kighmu déjà présent dans ~/.bashrc"
fi

if ! grep -q "/usr/local/bin" ~/.bashrc; then
    echo 'export PATH=$PATH:/usr/local/bin' >> ~/.bashrc
    echo "Ajout de /usr/local/bin au PATH dans ~/.bashrc"
fi

NS="slowdns5.kighmup.ddns-ip.net"

SLOWDNS_PUBKEY="/etc/slowdns/server.pub"
if [ -f "$SLOWDNS_PUBKEY" ]; then
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
echo "Fichier ~/.kighmu_info créé avec succès et prêt à être utilisé par les scripts."

echo
echo "=============================================="
echo " ✅ Installation terminée !"
echo " Pour lancer Kighmu, utilisez la commande : kighmu"
echo
echo " ⚠️ Pour que l'alias soit pris en compte :"
echo " - Ouvre un nouveau terminal, ou"
echo " - Exécutez manuellement : source ~/.bashrc"
echo
echo "=============================================="
