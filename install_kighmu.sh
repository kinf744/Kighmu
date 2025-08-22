#!/bin/bash
# ==============================================
# Kighmu VPS Manager - Script d'installation modifié
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
dnsutils net-tools wget sudo iptables ufw \
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

if ! command -v pip3 >/dev/null 2>&1; then
    echo "pip3 non trouvé, installation en cours..."
    apt update
    apt install -y python3-pip
fi

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

DNS_BIN="/usr/local/bin/sldns-server"
if [ ! -x "$DNS_BIN" ]; then
    echo "Téléchargement du binaire slowdns..."
    wget -q -O "$DNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
    chmod +x "$DNS_BIN"
fi

chmod +x "$DNS_BIN"
chmod 600 "$SLOWDNS_DIR/server.key"
chmod 644 "$SLOWDNS_DIR/server.pub"

cat > /etc/systemd/system/slowdns.service <<EOF
[Unit]
Description=SlowDNS Server
After=network.target

[Service]
ExecStart=$DNS_BIN -udp :5300 -privkey-file $SLOWDNS_DIR/server.key slowdns5.kighmup.ddns-ip.net 0.0.0.0:22
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable slowdns
systemctl restart slowdns

echo "Service SlowDNS systemd créé, activé et démarré."

# Application SSH config
echo "🚀 Application de la configuration SSH personnalisée..."
chmod +x "$INSTALL_DIR/setup_ssh_config.sh"
run_script "sudo $INSTALL_DIR/setup_ssh_config.sh"

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
echo " - Exécute manuellement : source ~/.bashrc"
echo
echo "Tentative de rechargement automatique de ~/.bashrc dans cette session..."
source ~/.bashrc || echo "Le rechargement automatique a échoué, merci de le faire manuellement."
echo "=============================================="
