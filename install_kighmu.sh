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
    "proxy_wss.py"      # Utilisation du proxy WebSocket Python asynchrone
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
echo " 🚀 Déploiement et activation de la configuration Nginx pour WebSocket asynchrone..."
echo "=============================================="

LISTEN_PORT=81
PROXY_PORT=8090

NGINX_PROXY_CONF="/etc/nginx/sites-available/kighmu_ws.conf"

cat > /tmp/kighmu_ws.conf <<EOF
server {
    listen $LISTEN_PORT;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$PROXY_PORT;
        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;

        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

sudo cp /tmp/kighmu_ws.conf "$NGINX_PROXY_CONF"
sudo ln -sf "$NGINX_PROXY_CONF" /etc/nginx/sites-enabled/kighmu_ws.conf

if ! sudo nginx -t; then
    echo "Erreur dans la configuration nginx. Installation annulée."
    exit 1
fi

sudo systemctl reload nginx

sudo ufw allow $LISTEN_PORT/tcp

# Nettoyer les anciennes sessions screen du proxy WebSocket python asynchrone
for session in $(screen -ls | grep proxy_wss_async | awk '{print $1}'); do
    screen -S "$session" -X quit
done

echo "=============================================="
echo " 🚀 Lancement du proxy WebSocket Python asynchrone dans screen..."
echo "=============================================="

screen -dmS proxy_wss python3 "$INSTALL_DIR/proxy_wss.py"

sleep 2

if screen -ls | grep -q proxy_wss; then
    echo "Proxy WebSocket python asynchrone lancé avec succès."
else
    echo "Erreur : le proxy WebSocket python asynchrone n'a pas pu démarrer."
fi

echo "=============================================="
echo " 🚀 Lancement du serveur Node.js (server.js) dans screen..."
echo "=============================================="

# Nettoyer sessions écran existantes nommées serverjs
for session in $(screen -ls | grep serverjs | awk '{print $1}'); do
    screen -S "$session" -X quit
done

screen -dmS serverjs node "$INSTALL_DIR/server.js"

sleep 2

if screen -ls | grep -q serverjs; then
    echo "Le serveur Node.js server.js est démarré et fonctionne dans screen."
else
    echo "Erreur : le serveur Node.js server.js n'a pas pu démarrer."
fi

# Le reste de votre script (SlowDNS, config ssh, alias, etc.) reste inchangé

echo "=============================================="
echo " ✅ Installation terminée !"
echo " Pour lancer Kighmu, utilisez la commande : kighmu"
echo " ⚠️ Pensez à relancer votre terminal ou faire 'source ~/.bashrc' pour prendre en compte les alias."
echo "=============================================="
