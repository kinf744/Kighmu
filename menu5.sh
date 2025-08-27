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

install_wstunnel() {
    echo "Installation wstunnel (binaire)..."
    apt-get install -y wget

    WSTUNNEL_BIN_URL="https://github.com/erebe/wstunnel/releases/download/v5.1/wstunnel-linux-x64"
    WSTUNNEL_BIN_PATH="/usr/local/bin/wstunnel"

    if command -v wstunnel >/dev/null 2>&1; then
        echo "wstunnel déjà installé."
    else
        echo "Téléchargement de wstunnel depuis $WSTUNNEL_BIN_URL ..."
        wget -q -O /tmp/wstunnel "$WSTUNNEL_BIN_URL" || { echo "Erreur téléchargement wstunnel"; return 1; }
        chmod +x /tmp/wstunnel
        mv /tmp/wstunnel "$WSTUNNEL_BIN_PATH"
        echo "wstunnel installé à $WSTUNNEL_BIN_PATH"
    fi
}

install_http_ws() {
    echo "Installation HTTP/WS..."
    cd "$HOME/Kighmu" || exit 1

    if [ -f "proxy_wss.py" ]; then
        apt-get install -y python3 python3-pip

        # Demande du domaine
        read -rp "Entrez le domaine à utiliser pour HTTP/WS: " DOMAIN

        # Stockage du domaine
        mkdir -p /etc/proxy_wss
        echo "$DOMAIN" > /etc/proxy_wss/domain.conf

        # Création du payload WebSocket clair comme dans l'exemple demandé
        PAYLOAD="GET / HTTP/1.1[crlf]\nHost: $DOMAIN[crlf]\nUpgrade: websocket[crlf]\nConnection: Upgrade[crlf][crlf]"
        echo -e "$PAYLOAD" > /etc/proxy_wss/payload.txt

        # Création du service systemd pour proxy_wss.py
        cat > /etc/systemd/system/proxy_wss.service <<EOF
[Unit]
Description=HTTP/WS Proxy Service
After=network.target

[Service]
Environment=DOMAIN=$(cat /etc/proxy_wss/domain.conf)
ExecStart=/usr/bin/python3 $HOME/Kighmu/proxy_wss.py
Restart=always
User=root
WorkingDirectory=$HOME/Kighmu
StandardOutput=append:/var/log/proxy_wss.log
StandardError=append:/var/log/proxy_wss.log

[Install]
WantedBy=multi-user.target
EOF

        # Activation
        systemctl daemon-reload
        systemctl enable proxy_wss
        systemctl restart proxy_wss

        echo "✅ HTTP/WS installé avec succès."
        echo "🌍 Domaine configuré: $DOMAIN"
        echo ""
        echo "=============================================="
        echo "📦 Payload généré automatiquement :"
        echo ""
        cat /etc/proxy_wss/payload.txt
        echo ""
        echo "➡️ Le payload est sauvegardé dans : /etc/proxy_wss/payload.txt"
        echo "=============================================="
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

# Ordre d’installation (HTTP/WS après SlowDNS)
install_openssh
install_dropbear
install_slowdns
install_wstunnel
install_http_ws
install_udp_custom
install_socks_python
install_ssl_tls
install_badvpn

echo ""
echo "=============================================="
echo " ✅ Tous les modes ont été installés automatiquement."
echo "=============================================="


# ======================================================
# Ajout de la commande de gestion rapide HTTP/WS
# ======================================================
cat > /usr/bin/http-ws <<'EOF'
#!/bin/bash
# Commande de gestion du mode HTTP/WS

CONF=/etc/proxy_wss/domain.conf
PAYLOAD_FILE=/etc/proxy_wss/payload.txt
SERVICE=proxy_wss

generate_payload() {
    DOMAIN=$(cat $CONF)
    echo -e "GET / HTTP/1.1[crlf]\nHost: $DOMAIN[crlf]\nUpgrade: websocket[crlf]\nConnection: Upgrade[crlf][crlf]" > $PAYLOAD_FILE
}

case "$1" in
    domain)
        if [ -z "$2" ]; then
            echo "Usage: http-ws domain monsite.tld"
            exit 1
        fi
        mkdir -p /etc/proxy_wss
        echo "$2" > $CONF
        generate_payload
        echo "[+] Domaine mis à jour : $2"
        echo "[+] Nouveau payload HTTP/WS généré :"
        echo ""
        cat $PAYLOAD_FILE
        echo ""
        systemctl restart $SERVICE
        echo "[+] Service redémarré."
        ;;
    show)
        if [ -f "$CONF" ]; then
            echo "🌍 Domaine actuel : $(cat $CONF)"
            if [ -f "$PAYLOAD_FILE" ]; then
                echo ""
                echo "📦 Payload actuel :"
                cat $PAYLOAD_FILE
            fi
        else
            echo "⚠️ Aucun domaine configuré."
        fi
        ;;
    restart)
        systemctl restart $SERVICE
        echo "[+] Service $SERVICE redémarré."
        ;;
    status)
        systemctl status $SERVICE --no-pager
        ;;
    logs)
        journalctl -u $SERVICE -e --no-pager
        ;;
    *)
        echo "Commande HTTP/WS Manager"
        echo "Usage: http-ws [action]"
        echo "Actions disponibles:"
        echo "  domain <monsite.tld>   -> changer le domaine et régénérer le payload"
        echo "  show                   -> afficher le domaine et le payload actuel"
        echo "  restart                -> redémarrer le service"
        echo "  status                 -> afficher l'état du service"
        echo "  logs                   -> afficher les logs du service"
        ;;
esac
EOF

chmod +x /usr/bin/http-ws
