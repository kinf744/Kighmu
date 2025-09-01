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

apt install -y \
sudo bsdmainutils zip unzip ufw curl python3 python3-pip openssl screen cron iptables lsof pv boxes nano at mlocate \
gawk grep bc jq npm nodejs socat netcat netcat-traditional net-tools cowsay figlet lolcat \
dnsutils net-tools wget sudo iptables ufw openssl psmisc nginx dropbear badvpn \
python3-setuptools wireguard-tools qrencode gcc make perl software-properties-common socat

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
    "server.js"
    "nginx.config"
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
echo " 🚀 Déploiement et activation de la configuration Nginx pour WebSocket..."
echo "=============================================="

NGINX_CONF="/etc/nginx/sites-available/kighmu_ws.conf"
cp "$INSTALL_DIR/nginx.config" "$NGINX_CONF" || { echo "Erreur : copie de nginx.config impossible!"; exit 1; }
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/kighmu_ws.conf

nginx -t && systemctl reload nginx || { echo "Erreur de configuration nginx"; exit 1; }

echo "=============================================="
echo " 🚀 Lancement du serveur WS proxy (proxy_wss.py) dans screen..."
echo "=============================================="

# Nettoyer sessions écran existantes nommées proxy_wss
sessions=$(screen -ls | grep proxy_wss | awk '{print $1}')
if [ -n "$sessions" ]; then
    for session in $sessions; do
        screen -S "$session" -X quit
    done
    echo "Anciennes sessions proxy_wss supprimées."
fi

screen -dmS proxy_wss /usr/bin/python3 "$INSTALL_DIR/proxy_wss.py"

sleep 2

if screen -ls | grep -q proxy_wss; then
    echo "Le serveur WS proxy_wss.py est démarré et fonctionne dans screen."
else
    echo "Erreur : le serveur WS proxy_wss.py n'a pas pu démarrer dans screen."
fi

echo "=============================================="
echo " 🚀 Lancement du serveur Node.js (server.js) dans screen..."
echo "=============================================="

# Nettoyer sessions écran existantes nommées serverjs
sessions_node=$(screen -ls | grep serverjs | awk '{print $1}')
if [ -n "$sessions_node" ]; then
    for session in $sessions_node; do
        screen -S "$session" -X quit
    done
    echo "Anciennes sessions server.js supprimées."
fi

screen -dmS serverjs node "$INSTALL_DIR/server.js"

sleep 2

if screen -ls | grep -q serverjs; then
    echo "Le serveur Node.js server.js est démarré et fonctionne dans screen."
else
    echo "Erreur : le serveur Node.js server.js n'a pas pu démarrer dans screen."
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
echo " - Ouvrez un nouveau terminal, ou"
echo " - Exécutez manuellement : source ~/.bashrc"
echo
echo "=============================================="
