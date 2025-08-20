#!/bin/bash

# ==============================================
# slowdns.sh - Installation et configuration SlowDNS avec stockage NS
# ==============================================

SLOWDNS_DIR="/etc/slowdns"
SERVER_KEY="$SLOWDNS_DIR/server.key"     # Clé privée serveur
SERVER_PUB="$SLOWDNS_DIR/server.pub"     # Clé publique serveur
SLOWDNS_BIN="/usr/local/bin/sldns-server" # Chemin du binaire SlowDNS
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"

# Installation automatique des dépendances iptables, screen, tcpdump
install_dependencies() {
    sudo apt update

    for pkg in iptables screen tcpdump; do
        if ! command -v $pkg >/dev/null 2>&1; then
            echo "$pkg non trouvé. Installation en cours..."
            sudo apt install -y $pkg
        else
            echo "$pkg est déjà installé."
        fi
    done
}

install_dependencies

# Création du dossier slowdns si absent
if [ ! -d "$SLOWDNS_DIR" ]; then
    sudo mkdir -p "$SLOWDNS_DIR"
fi

# Chargement ou saisie du NameServer (NS)
if [ -f "$CONFIG_FILE" ]; then
    NAMESERVER=$(cat "$CONFIG_FILE")
    echo "Utilisation du NameServer existant : $NAMESERVER"
else
    read -p "Entrez le NameServer (NS) (ex: ns.example.com) : " NAMESERVER
    if [[ -z "$NAMESERVER" ]]; then
        echo "NameServer invalide."
        exit 1
    fi
    echo "$NAMESERVER" | sudo tee "$CONFIG_FILE" > /dev/null
    echo "NameServer enregistré dans $CONFIG_FILE"
fi

# Installation du binaire SlowDNS si besoin
echo "Vérification et installation du binaire SlowDNS..."
if [ ! -x "$SLOWDNS_BIN" ]; then
    echo "Le binaire SlowDNS n'existe pas. Téléchargement en cours..."
    sudo mkdir -p /usr/local/bin
    sudo wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
    sudo chmod +x "$SLOWDNS_BIN"
    echo "Installation du binaire SlowDNS terminée."
else
    echo "Le binaire SlowDNS est déjà installé."
fi

# Fonction de gestion des clés (Génération désactivée)
generate_keys() {
    if [ ! -s "$SERVER_KEY" ]; then
        echo "Erreur : La clé privée SlowDNS est manquante dans $SERVER_KEY."
        echo "Merci de fournir une clé privée valide avant de lancer ce script."
        exit 1
    fi

    # Écriture de la clé publique personnalisée (remplacement)
    echo "7fbd1f8aa0abfe15a7903e837f78aba39cf61d36f183bd604daa2fe4ef3b7b59" | sudo tee "$SERVER_PUB" > /dev/null
    sudo chmod 644 "$SERVER_PUB"
    echo "Clé publique personnalisée SlowDNS ajoutée."
}

# Gestion des clés
generate_keys

# Lecture dynamique de la clé publique
PUB_KEY=$(cat "$SERVER_PUB")

# Arrêt de l’ancienne instance SlowDNS si existante
if pgrep -f "sldns-server" >/dev/null; then
    echo "Arrêt de l'ancienne instance SlowDNS..."
    sudo fuser -k ${PORT}/udp || true
    sleep 2
fi

# Configuration iptables pour redirection port 53 vers 5300 UDP
configure_iptables() {
    interface=$(ip a | awk '/state UP/{print $2}' | cut -d: -f1 | head -1)
    echo "Configuration iptables pour rediriger UDP port 53 vers $PORT (port SlowDNS)..."
    sudo iptables -I INPUT -p udp --dport $PORT -j ACCEPT
    sudo iptables -t nat -I PREROUTING -i $interface -p udp --dport 53 -j REDIRECT --to-ports $PORT

    # Sauvegarder règles iptables (Debian/Ubuntu)
    if command -v iptables-save >/dev/null 2>&1; then
        sudo iptables-save | sudo tee /etc/iptables/rules.v4 >/dev/null
    fi
}

configure_iptables

# Lancement du serveur SlowDNS dans screen détaché avec commande conforme à DarkSSH
echo "Démarrage du serveur SlowDNS sur UDP port $PORT avec NS $NAMESERVER..."
sudo screen -dmS slowdns_session $SLOWDNS_BIN -udp ":$PORT" -privkey-file "$SERVER_KEY" "$NAMESERVER" 0.0.0.0:22

sleep 3

# Vérification du démarrage
if pgrep -f "sldns-server" > /dev/null; then
    echo -e "\033[34mHTTP/1.1 200 OK Kighmu237 - Service SlowDNS démarré avec succès sur le port UDP $PORT.\033[0m"
    echo "Pour vérifier les logs, utilise : screen -r slowdns_session"
else
    echo "ERREUR : Le service SlowDNS n'a pas pu démarrer."
    exit 1
fi

# Activation IP forwarding si nécessaire
if [ "$(sysctl -n net.ipv4.ip_forward)" -ne 1 ]; then
    echo "Activation du routage IP..."
    sudo sysctl -w net.ipv4.ip_forward=1
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
    fi
fi

# Firewall UFW gestion
if command -v ufw >/dev/null 2>&1; then
    echo "Ouverture du port UDP $PORT dans le firewall (ufw)..."
    sudo ufw allow "$PORT"/udp
    sudo ufw reload
else
    echo "UFW non installé. Merci de vérifier manuellement l'ouverture du port UDP $PORT."
fi

echo "+--------------------------------------------+"
echo "|               CONFIG SLOWDNS               |"
echo "+--------------------------------------------+"
echo ""
echo "Clé publique :"
echo "$PUB_KEY"
echo ""
echo "NameServer  : $NAMESERVER"
echo ""
echo "Commande client Termux à utiliser :"
echo "curl -sO https://github.com/khaledagn/DNS-AGN/raw/main/files/slowdns && chmod +x slowdns && ./slowdns $NAMESERVER $PUB_KEY"
echo ""
echo "Installation et configuration SlowDNS terminées."
