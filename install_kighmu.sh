#!/bin/bash
# ==============================================
# Kighmu VPS Manager - Script d'installation complet
# Copyright (c) 2025 Kinf744
# Licence MIT (version française)
# ==============================================

set -e

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
apt install -y sudo bsdmainutils zip unzip ufw curl python3 python3-pip openssl screen cron iptables lsof pv boxes nano at mlocate \
gawk grep bc jq npm nodejs socat netcat netcat-traditional net-tools cowsay figlet lolcat dnsutils wget sudo iptables ufw openssl psmisc \
nginx dropbear badvpn python3-setuptools wireguard-tools qrencode gcc make perl software-properties-common socat haproxy

apt autoremove -y
apt clean

echo "=============================================="
echo " 🚀 Installation des modules Python websockets & pysocks..."
echo "=============================================="

if ! python3 -c "import websockets" &> /dev/null; then
    echo "Installation du module python websockets via pip3..."
    pip3 install websockets
else
    echo "Module python websockets déjà installé."
fi

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
    chmod +x "$PROXY_SCRIPT_PATH"
    echo "Script téléchargé et rendu exécutable."
else
    echo "Script KIGHMUPROXY.py déjà présent."
fi

ufw allow OpenSSH
ufw allow 22
ufw allow 80
ufw allow 443
ufw --force enable

echo "=============================================="
echo " 🚀 Installation des scripts Kighmu..."
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
    wget -q -O "$INSTALL_DIR/$file" "$BASE_URL/$file"
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

# Partie SlowDNS x3 + HAProxy intégrée ici
echo "=============================================="
echo " 🚀 Installation et configuration du mode SlowDNS x3 + HAProxy..."
echo "=============================================="

SLOWDNS_DIR="/etc/slowdns"
sudo mkdir -p "$SLOWDNS_DIR"

SLOWDNS_BIN="/usr/local/bin/sldns-server"
if [ ! -x "$SLOWDNS_BIN" ]; then
    echo "Téléchargement du binaire sldns-server..."
    sudo wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
    sudo chmod +x "$SLOWDNS_BIN"
fi

UDP_PORTS=(5301 5302 5303)
SSH_PORTS=(2201 2202 2203)
VIP_PORT=5300

# Ajout des ports SSH personnalisés
for p in "${SSH_PORTS[@]}"; do
    if ! grep -q "Port $p" /etc/ssh/sshd_config; then
        echo "Port $p" | sudo tee -a /etc/ssh/sshd_config > /dev/null
    fi
done
sudo systemctl restart ssh

# Génération et lancement des instances SlowDNS
for i in 1 2 3; do
    KEY="$SLOWDNS_DIR/server$i.key"
    PUB="$SLOWDNS_DIR/server$i.pub"
    PORT="${UDP_PORTS[$((i-1))]}"
    SSH="${SSH_PORTS[$((i-1))]}"
    if [ ! -s "$KEY" ] || [ ! -s "$PUB" ]; then
        sudo $SLOWDNS_BIN -gen-key -privkey-file "$KEY" -pubkey-file "$PUB"
        sudo chmod 600 "$KEY"
        sudo chmod 644 "$PUB"
    fi
    sudo pkill -f "$SLOWDNS_BIN.*:$PORT" || true
    sleep 1
    sudo screen -dmS slowdns_$i $SLOWDNS_BIN -udp ":$PORT" -privkey-file "$KEY" "$DOMAIN" 0.0.0.0:$SSH
done

sleep 3

# Configuration HAProxy (UDP load balancing sur port VIP_PORT)
cat <<EOL | sudo tee /etc/haproxy/haproxy.cfg
global
    daemon
    maxconn 4096

defaults
    mode tcp
    timeout connect 10s
    timeout client 1m
    timeout server 1m

frontend slowdns_in
    bind *:$VIP_PORT
    mode tcp
    default_backend slowdns_out

backend slowdns_out
    mode tcp
    balance roundrobin
    server s1 127.0.0.1:${UDP_PORTS[0]}
    server s2 127.0.0.1:${UDP_PORTS[1]}
    server s3 127.0.0.1:${UDP_PORTS[2]}
EOL

sudo systemctl restart haproxy

# Ouverture des ports au firewall
for p in $VIP_PORT "${UDP_PORTS[@]}" "${SSH_PORTS[@]}"; do
    sudo iptables -I INPUT -p udp --dport $p -j ACCEPT
    sudo iptables -I INPUT -p tcp --dport $p -j ACCEPT
done

if command -v ufw >/dev/null 2>&1; then
    sudo ufw allow "$VIP_PORT"/udp
    for p in "${UDP_PORTS[@]}"; do sudo ufw allow "$p"/udp; done
    for p in "${SSH_PORTS[@]}"; do sudo ufw allow "$p"/tcp; done
    sudo ufw reload
fi

# Lancement SlowDNS.sh (ancien script, peut être supprimé si tu préfères)
run_script "$INSTALL_DIR/slowdns.sh"
run_script "$INSTALL_DIR/udp_custom.sh"

echo "=============================================="
echo " 🚀 Lancement du mode HTTP/WS via screen..."
echo "=============================================="

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
    echo "Le serveur WS est démarré et fonctionne dans screen."
else
    echo "Erreur : le serveur WS n'a pas pu démarrer dans screen."
fi

echo "=============================================="
echo " ✅ Installation terminée !"
echo " Pour lancer Kighmu, utilisez la commande : kighmu"
echo " ⚠️ Pour que l'alias soit pris en compte :"
echo " - Ouvre un nouveau terminal, ou"
echo " - Exécutez manuellement : source ~/.bashrc"
echo "=============================================="
