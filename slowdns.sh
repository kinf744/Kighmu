#!/bin/bash
# ==============================================
# slowdns.sh - Installation & SlowDNS x3 + HAProxy (profil unique client)
# ==============================================

SLOWDNS_DIR="/etc/slowdns"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"

UDP_PORTS=(5301 5302 5303)
SSH_PORTS=(2201 2202 2203)
VIP_PORT=5300

# Installation des dépendances
install_dependencies() {
    sudo apt update
    for pkg in iptables screen tcpdump wget haproxy; do
        if ! command -v $pkg >/dev/null 2>&1; then
            sudo apt install -y $pkg
        fi
    done
}
install_dependencies

# Création du dossier slowdns si absent
sudo mkdir -p "$SLOWDNS_DIR"

# Chargement ou saisie du NameServer (NS)
if [ -f "$CONFIG_FILE" ]; then
    NAMESERVER=$(cat "$CONFIG_FILE")
else
    read -p "Entrez le NameServer (NS) (ex: ns.example.com) : " NAMESERVER
    echo "$NAMESERVER" | sudo tee "$CONFIG_FILE" > /dev/null
fi

# Installation du binaire SlowDNS si besoin
if [ ! -x "$SLOWDNS_BIN" ]; then
    sudo wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
    sudo chmod +x "$SLOWDNS_BIN"
fi

# Ajout des ports SSH custom
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
    # Génère clé si nécessaire
    if [ ! -s "$KEY" ] || [ ! -s "$PUB" ]; then
        sudo $SLOWDNS_BIN -gen-key -privkey-file "$KEY" -pubkey-file "$PUB"
        sudo chmod 600 "$KEY"
        sudo chmod 644 "$PUB"
    fi
    # Arrêt précédente
    sudo pkill -f "$SLOWDNS_BIN.*:$PORT" || true
    sleep 1
    # Lance SlowDNS instance
    sudo screen -dmS slowdns_$i $SLOWDNS_BIN -udp ":$PORT" -privkey-file "$KEY" "$NAMESERVER" 0.0.0.0:$SSH
done

sleep 3

# HAProxy config pour VIP unique côté client
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

# IPtables ports nécessaires
for p in $VIP_PORT "${UDP_PORTS[@]}" "${SSH_PORTS[@]}"; do
    sudo iptables -I INPUT -p udp --dport $p -j ACCEPT
    sudo iptables -I INPUT -p tcp --dport $p -j ACCEPT
done

# Optimisations kernel réseau (toujours utile)
for param in "net.ipv4.ip_forward=1" "net.core.rmem_max=26214400" "net.core.wmem_max=26214400" "net.ipv4.tcp_fastopen=3" "net.ipv4.tcp_tw_reuse=1"
do
    sudo sysctl -w ${param}
    if ! grep -q "$param" /etc/sysctl.conf; then
        echo "$param" | sudo tee -a /etc/sysctl.conf >/dev/null
    fi
done

# Firewall UFW (optionnel)
if command -v ufw >/dev/null 2>&1; then
    sudo ufw allow "$VIP_PORT"/udp
    for p in "${UDP_PORTS[@]}"; do sudo ufw allow "$p"/udp; done
    for p in "${SSH_PORTS[@]}"; do sudo ufw allow "$p"/tcp; done
    sudo ufw reload
fi

# Affichage et infos client
PUB_KEY=$(cat "$SLOWDNS_DIR/server1.pub")

echo "+--------------------------------------------+"
echo "|      CONFIG SLOWDNS x3 BOOST + HAProxy     |"
echo "+--------------------------------------------+"
echo ""
echo "Clé publique SlowDNS 1 :"
echo "$PUB_KEY"
echo ""
echo "NameServer   : $NAMESERVER"
echo ""
echo "Port UDP     : $VIP_PORT (un seul profil côté client)"
echo ""
echo "Commande client Termux :"
echo "curl -sO https://github.com/khaledagn/DNS-AGN/raw/main/files/slowdns && chmod +x slowdns"
echo "./slowdns $NAMESERVER $PUB_KEY"
echo ""
echo "Tunnel boosté ! 1 profil client, 3 instances côté VPS pour plus de stabilité."
echo ""

if pgrep -f "$SLOWDNS_BIN" > /dev/null; then
    echo "Service SlowDNS X3 démarré avec succès & Load Balanced !"
else
    echo "ERREUR : Le service SlowDNS X3 n'a pas pu démarrer."
    exit 1
fi
