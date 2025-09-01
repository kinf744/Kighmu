#!/bin/bash

# ==============================================
# slowdns.sh - Installation et configuration SlowDNS optimisé
# Avec service systemd pour stabilité et relance auto
# ==============================================

SLOWDNS_DIR="/etc/slowdns"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"
SLOWDNS_BIN="/usr/local/bin/sldns-server"
PORT=5300
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
MTU=1280   # MTU par défaut optimisé

# Installation dépendances
install_dependencies() {
    sudo apt update
    for pkg in iptables tcpdump wget; do
        if ! command -v $pkg >/dev/null 2>&1; then
            echo "$pkg non trouvé. Installation..."
            sudo apt install -y $pkg
        fi
    done
}

install_dependencies

# Création dossier slowdns
[ ! -d "$SLOWDNS_DIR" ] && sudo mkdir -p "$SLOWDNS_DIR"

# Chargement ou saisie NameServer
if [ -f "$CONFIG_FILE" ]; then
    NAMESERVER=$(cat "$CONFIG_FILE")
    echo "Utilisation du NameServer existant : $NAMESERVER"
else
    read -p "Entrez le NameServer (NS) (ex: ns.example.com) : " NAMESERVER
    [[ -z "$NAMESERVER" ]] && { echo "NameServer invalide."; exit 1; }
    echo "$NAMESERVER" | sudo tee "$CONFIG_FILE" > /dev/null
fi

# Installation binaire SlowDNS si absent
if [ ! -x "$SLOWDNS_BIN" ]; then
    sudo mkdir -p /usr/local/bin
    sudo wget -q -O "$SLOWDNS_BIN" https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server
    sudo chmod +x "$SLOWDNS_BIN"
fi

# Génération automatique clés
generate_keys() {
    if [ ! -s "$SERVER_KEY" ] || [ ! -s "$SERVER_PUB" ]; then
        echo "Génération des clés SlowDNS..."
        sudo $SLOWDNS_BIN -gen-key -privkey-file "$SERVER_KEY" -pubkey-file "$SERVER_PUB"
        sudo chmod 600 "$SERVER_KEY"
        sudo chmod 644 "$SERVER_PUB"
    fi
}

generate_keys
PUB_KEY=$(cat "$SERVER_PUB")

# Optimisation réseau
interface=$(ip a | awk '/state UP/{print $2}' | cut -d: -f1 | head -1)
echo "Réglage MTU sur $interface à $MTU..."
sudo ip link set dev $interface mtu $MTU

# Buffers UDP
sudo sysctl -w net.core.rmem_max=8388608
sudo sysctl -w net.core.wmem_max=8388608
sudo sysctl -w net.ipv4.udp_rmem_min=16384
sudo sysctl -w net.ipv4.udp_wmem_min=16384
sudo sysctl -w net.ipv4.ip_local_port_range="1024 65535"
sudo sysctl -w net.ipv4.tcp_fin_timeout=15
sudo sysctl -w net.ipv4.tcp_tw_reuse=1

# Firewall (ajout ciblé)
sudo iptables -I INPUT -p udp --dport $PORT -j ACCEPT
sudo iptables -t nat -I PREROUTING -i $interface -p udp --dport 53 -j REDIRECT --to-ports $PORT

if command -v iptables-save >/dev/null 2>&1; then
    sudo iptables-save | sudo tee /etc/iptables/rules.v4 >/dev/null
fi

# IP forwarding
if [ "$(sysctl -n net.ipv4.ip_forward)" -ne 1 ]; then
    sudo sysctl -w net.ipv4.ip_forward=1
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
    fi
fi

ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)

# Création service systemd
SERVICE_FILE="/etc/systemd/system/slowdns.service"
sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=SlowDNS Server
After=network.target

[Service]
ExecStart=$SLOWDNS_BIN -udp ":$PORT" -privkey-file $SERVER_KEY $NAMESERVER 0.0.0.0:$ssh_port
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Activation du service
sudo systemctl daemon-reexec
sudo systemctl enable slowdns
sudo systemctl restart slowdns

# Firewall UFW si dispo
if command -v ufw >/dev/null 2>&1; then
    sudo ufw allow "$PORT"/udp
    sudo ufw reload
fi

# Résumé
clear
echo "+--------------------------------------------+"
echo "|         CONFIGURATION SLOWDNS OK           |"
echo "+--------------------------------------------+"
echo ""
echo "Clé publique :"
echo "$PUB_KEY"
echo ""
echo "NameServer  : $NAMESERVER"
echo ""
echo "Service systemd actif : systemctl status slowdns"
echo "Client (ex Termux) :"
echo "curl -sO https://github.com/khaledagn/DNS-AGN/raw/main/files/slowdns && chmod +x slowdns && ./slowdns $NAMESERVER $PUB_KEY"
echo ""
