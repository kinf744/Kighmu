#!/bin/bash
# ==============================================
# Kighmu VPS Manager - Script d'installation complet tolérant erreurs
# Copyright (c) 2025 Kinf744
# Licence MIT (version française)
# ==============================================

echo "Vérification de la présence de curl..."
if ! command -v curl >/dev/null 2>&1; then
    echo "curl non trouvé, installation en cours..."
    if ! apt update -y; then
        echo "⚠️ Échec de apt update, on continue..."
    fi
    if ! apt install -y curl; then
        echo "⚠️ Impossible d'installer curl, on continue..."
    fi
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

PACKAGES=(sudo bsdmainutils zip unzip ufw curl python3 python3-pip openssl screen cron iptables lsof pv boxes nano at mlocate \
gawk grep bc jq npm nodejs socat netcat netcat-traditional net-tools cowsay figlet lolcat dnsutils wget sudo iptables ufw openssl psmisc \
nginx dropbear badvpn python3-setuptools wireguard-tools qrencode gcc make perl software-properties-common socat haproxy)

if ! apt update -y; then
    echo "⚠️ Échec de apt update, on continue..."
fi

if ! apt upgrade -y; then
    echo "⚠️ Échec de apt upgrade, on continue..."
fi

for pkg in "${PACKAGES[@]}"; do
    dpkg -s "$pkg" &>/dev/null
    if [ $? -ne 0 ]; then
        echo "Installation du paquet $pkg..."
        if ! apt install -y "$pkg"; then
            echo "⚠️ Échec d'installation du paquet $pkg, on continue..."
        fi
    else
        echo "Le paquet $pkg est déjà installé."
    fi
done

if ! apt autoremove -y; then
    echo "⚠️ Échec d'autoremove, on continue..."
fi

if ! apt clean; then
    echo "⚠️ Échec d'apt clean, on continue..."
fi

echo "=============================================="
echo " 🚀 Installation modules Python websockets & pysocks..."
echo "=============================================="

if ! python3 -c "import websockets" &> /dev/null; then
    echo "Installation du module python websockets via pip3..."
    if ! pip3 install websockets; then
        echo "⚠️ Échec d'installation de websockets, on continue..."
    fi
else
    echo "Module python websockets déjà installé."
fi

if ! python3 -c "import socks" &> /dev/null; then
    echo "Installation du module pysocks via pip3..."
    if ! pip3 install pysocks; then
        echo "⚠️ Échec d'installation de pysocks, on continue..."
    fi
else
    echo "Module pysocks déjà installé."
fi

PROXY_SCRIPT_PATH="/usr/local/bin/KIGHMUPROXY.py"
if [ ! -f "$PROXY_SCRIPT_PATH" ]; then
    echo "Téléchargement du script KIGHMUPROXY.py..."
    if ! wget -q -O "$PROXY_SCRIPT_PATH" "https://raw.githubusercontent.com/kinf744/Kighmu/main/KIGHMUPROXY.py"; then
        echo "⚠️ Impossible de télécharger KIGHMUPROXY.py, on continue..."
    else
        chmod +x "$PROXY_SCRIPT_PATH"
        echo "Script téléchargé et rendu exécutable."
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
    if ! wget -q -O "$INSTALL_DIR/$file" "$BASE_URL/$file"; then
        echo "⚠️ Erreur lors du téléchargement de $file, on continue..."
        continue
    fi
    if [ ! -s "$INSTALL_DIR/$file" ]; then
        echo "⚠️ Le fichier $file est vide après téléchargement, on continue..."
        continue
    fi
    chmod +x "$INSTALL_DIR/$file"
done

run_script() {
    local script_path="$1"
    echo "🚀 Lancement du script : $script_path"
    if ! bash "$script_path"; then
        echo "⚠️ Attention : $script_path a rencontré une erreur. L'installation continue..."
    else
        echo "✅ $script_path exécuté avec succès."
    fi
}

run_script "$INSTALL_DIR/dropbear.sh"
run_script "$INSTALL_DIR/ssl.sh"
run_script "$INSTALL_DIR/badvpn.sh"
run_script "$INSTALL_DIR/system_dns.sh"
run_script "$INSTALL_DIR/nginx.sh"
run_script "$INSTALL_DIR/socks_python.sh"

echo "=============================================="
echo " 🚀 Installation et configuration du mode SlowDNS x3 + HAProxy..."
echo "=============================================="

SLOWDNS_DIR="/etc/slowdns"
sudo mkdir -p "$SLOWDNS_DIR"

SLOWDNS_BIN="/usr/local/bin/sldns-server"
if [ ! -x "$SLOWDNS_BIN" ]; then
    echo "Téléchargement du binaire sldns-server..."
    if ! sudo wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server; then
        echo "⚠️ Échec du téléchargement du binaire slowdns."
    else
        sudo chmod +x "$SLOWDNS_BIN"
    fi
fi

UDP_PORTS=(5301 5302 5303)
SSH_PORTS=(2201 2202 2203)
VIP_PORT=5300

for p in "${SSH_PORTS[@]}"; do
    if ! grep -q "Port $p" /etc/ssh/sshd_config; then
        echo "Port $p" | sudo tee -a /etc/ssh/sshd_config > /dev/null
    fi
done
if ! sudo systemctl restart ssh; then
    echo "⚠️ Échec du redémarrage de ssh."
fi

for i in 1 2 3; do
    KEY="$SLOWDNS_DIR/server$i.key"
    PUB="$SLOWDNS_DIR/server$i.pub"
    PORT="${UDP_PORTS[$((i-1))]}"
    SSH="${SSH_PORTS[$((i-1))]}"
    if [ ! -s "$KEY" ] || [ ! -s "$PUB" ]; then
        if ! sudo $SLOWDNS_BIN -gen-key -privkey-file "$KEY" -pubkey-file "$PUB"; then
            echo "⚠️ Échec génération clé SlowDNS instance $i."
        else
            sudo chmod 600 "$KEY"
            sudo chmod 644 "$PUB"
        fi
    fi
    sudo pkill -f "$SLOWDNS_BIN.*:$PORT" || true
    sleep 1
    if ! sudo screen -dmS slowdns_$i $SLOWDNS_BIN -udp ":$PORT" -privkey-file "$KEY" "$DOMAIN" 0.0.0.0:$SSH; then
        echo "⚠️ Échec lancement SlowDNS instance $i."
    fi
done

sleep 3

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

if ! sudo systemctl restart haproxy; then
    echo "⚠️ Échec redémarrage haproxy."
fi

for p in $VIP_PORT "${UDP_PORTS[@]}" "${SSH_PORTS[@]}"; do
    if ! sudo iptables -I INPUT -p udp --dport $p -j ACCEPT; then
        echo "⚠️ Erreur iptables udp $p"
    fi
    if ! sudo iptables -I INPUT -p tcp --dport $p -j ACCEPT; then
        echo "⚠️ Erreur iptables tcp $p"
    fi
done

if command -v ufw >/dev/null 2>&1; then
    sudo ufw allow "$VIP_PORT"/udp
    for p in "${UDP_PORTS[@]}"; do sudo ufw allow "$p"/udp; done
    for p in "${SSH_PORTS[@]}"; do sudo ufw allow "$p"/tcp; done
    sudo ufw reload
fi

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

if ! screen -dmS proxy_wss /usr/bin/python3 "$INSTALL_DIR/proxy_wss.py"; then
    echo "⚠️ Échec lancement proxy_wss.py dans screen."
fi

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
