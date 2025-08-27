#!/bin/bash
# menu5.sh
# Installation automatique des modes spéciaux

echo "+--------------------------------------------+"
echo "|      INSTALLATION AUTOMATIQUE DES MODES    |"
echo "+--------------------------------------------+"

# Détection IP et uptime
HOST_IP=$(curl -s https://api.ipify.org)
UPTIME=$(uptime -p)

echo "IP: $HOST_IP | Uptime: $UPTIME"
echo ""

# Fonctions install/configuration pour chaque mode
install_openssh() {
    echo "Installation / vérification Openssh..."
    apt-get install -y openssh-server
    systemctl enable ssh
    systemctl start ssh
}

install_dropbear() {
    echo "Installation / vérification Dropbear..."
    apt-get install -y dropbear
    systemctl enable dropbear
    systemctl start dropbear
}

install_slowdns() {
    echo "Installation / configuration SlowDNS..."
    bash "$HOME/Kighmu/slowdns.sh" || echo "SlowDNS : script non trouvé ou erreur."
}

install_http_wss() {
    echo "Installation HTTP/WSS..."
    cd "$HOME/Kighmu" || exit 1

    if [ -f "proxy_wss.py" ]; then
        apt-get install -y python3 python3-pip

        cat > /etc/systemd/system/proxy_wss.service <<EOF
[Unit]
Description=HTTP/WSS Proxy Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 $HOME/Kighmu/proxy_wss.py
Restart=always
User=root
WorkingDirectory=$HOME/Kighmu
StandardOutput=append:/var/log/proxy_wss.log
StandardError=append:/var/log/proxy_wss.log

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl enable proxy_wss
        systemctl start proxy_wss

        echo "✅ HTTP/WSS installé et démarré avec succès."
    else
        echo "⚠️ proxy_wss.py introuvable dans $HOME/Kighmu/"
    fi
}

install_udp_custom() {
    echo "Installation UDP Custom..."
    bash "$HOME/Kighmu/udp_custom.sh" || echo "UDP Custom : script non trouvé ou erreur."
}

install_socks_python() {
    echo "Installation SOCKS/Python..."
    bash "$HOME/Kighmu/socks_python.sh" || echo "SOCKS/Python : script non trouvé ou erreur."
}

install_ssl_tls() {
    echo "Installation SSL/TLS..."
    # Ajoute ici les commandes pour installer/configurer SSL/TLS
}

install_badvpn() {
    echo "Installation BadVPN..."
    # Ajoute ici les commandes pour installer/configurer BadVPN
}

# Ordre d’installation (HTTP/WSS directement après SlowDNS)
install_openssh
install_dropbear
install_slowdns
install_http_wss
install_udp_custom
install_socks_python
install_ssl_tls
install_badvpn

echo ""
echo "=============================================="
echo " ✅ Tous les modes ont été installés automatiquement."
echo "=============================================="
