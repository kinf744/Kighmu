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

# Demander le NS (nom de serveur DNS) à utiliser
read -p "Veuillez entrer le NS (nom de serveur DNS) à utiliser : " NS
if [ -z "$NS" ]; then
  echo "Erreur : le NS ne peut pas être vide."
  exit 1
fi

export DOMAIN
export NS

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
software-properties-common socat jq curl unzip sudo snapd

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
    "xray_installe.sh"  # Ajout du script d'installation Xray
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

# --- Ajout du proxy SOCKS KIGHMUSSH ---

echo "=============================================="
echo " 🚀 Installation du proxy SOCKS KIGHMUSSH..."
echo "=============================================="

PROXY_SCRIPT_PATH="/usr/local/bin/KIGHMUPROXY.py"
PROXY_SCRIPT_URL="https://raw.githubusercontent.com/kinf744/Kighmu/main/KIGHMUPROXY.py"

wget -q -O "$PROXY_SCRIPT_PATH" "$PROXY_SCRIPT_URL"
chmod +x "$PROXY_SCRIPT_PATH"
echo "Script proxy SOCKS KIGHMUSSH installé dans $PROXY_SCRIPT_PATH"

# Génération du script local socks_python.sh dans le dossier d'installation
cat > "$INSTALL_DIR/socks_python.sh" <<'EOF'
#!/bin/bash

PROXY_PORT=8080
SCRIPT_PATH="/usr/local/bin/KIGHMUPROXY.py"
LOG_FILE="/var/log/kighmuproxy.log"

echo "Arrêt d'un ancien proxy SOCKS KIGHMUSSH..."
sudo pkill -f "$SCRIPT_PATH" || true

echo "Démarrage du proxy SOCKS KIGHMUSSH sur le port $PROXY_PORT..."
nohup sudo python3 "$SCRIPT_PATH" $PROXY_PORT > "$LOG_FILE" 2>&1 &

sleep 3

if pgrep -f "$SCRIPT_PATH" > /dev/null; then
    echo "Proxy SOCKS KIGHMUSSH lancé avec succès."
else
    echo "Erreur lors du démarrage du proxy SOCKS. Consultez $LOG_FILE"
fi
EOF

chmod +x "$INSTALL_DIR/socks_python.sh"

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
screen -dmS slowdns "$DNS_BIN" -udp :5300 -privkey-file "$SLOWDNS_DIR/server.key" "$NS" 0.0.0.0:$ssh_port

echo "+--------------------------------------------+"
echo " SlowDNS installé et lancé avec succès !"
echo " Clé publique (à utiliser côté client) :"
cat "$SLOWDNS_DIR/server.pub"
echo ""
echo "Commande client SlowDNS à utiliser :"
echo "curl -sO https://github.com/khaledagn/DNS-AGN/raw/main/files/slowdns && chmod +x slowdns && ./slowdns $NS $(cat $SLOWDNS_DIR/server.pub)"
echo "+--------------------------------------------+"

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

# --- Génération automatique du fichier ~/.kighmu_info ---

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

# Redémarrage automatique à la fin
echo "Redémarrage du serveur dans 5 secondes..."
sleep 5
sudo reboot
