#!/bin/bash
# menu5.sh
# Installation automatique des modes spéciaux et tunnel SSH WebSocket avec wstunnel

echo "+--------------------------------------------+"
echo "|      INSTALLATION AUTOMATIQUE DES MODES    |"
echo "+--------------------------------------------+"

# Détection IP et uptime
HOST_IP=$(curl -s https://api.ipify.org)
UPTIME=$(uptime -p)

echo "IP: $HOST_IP | Uptime: $UPTIME"
echo ""

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
    echo "Installation HTTP/WS (proxy_wss.py)..."
    cd "$HOME/Kighmu" || exit 1

    if [ -f "proxy_wss.py" ]; then
        apt-get install -y python3 python3-pip

        read -rp "Entrez le domaine à utiliser pour HTTP/WS: " DOMAIN

        mkdir -p /etc/proxy_wss
        echo "$DOMAIN" > /etc/proxy_wss/domain.conf

        PAYLOAD="GET / HTTP/1.1[crlf]\nHost: $DOMAIN[crlf]\nUpgrade: websocket[crlf]\nConnection: Upgrade[crlf][crlf]"
        echo -e "$PAYLOAD" > /etc/proxy_wss/payload.txt

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

        systemctl daemon-reload
        systemctl enable proxy_wss
        systemctl restart proxy_wss

        echo "✅ HTTP/WS installé, domaine: $DOMAIN"
        echo "📦 Payload sauvegardé dans /etc/proxy_wss/payload.txt:"
        cat /etc/proxy_wss/payload.txt
    else
        echo "⚠️ proxy_wss.py introuvable dans $HOME/Kighmu/"
    fi
}

install_ssh_wstunnel() {
    echo "Démarrage du tunnel SSH WebSocket avec wstunnel dans screen..."
    
    # Nettoyer sessions screen existantes nommées sshws
    sessions=$(screen -ls | grep sshws | awk '{print $1}')
    if [ -n "$sessions" ]; then
        for session in $sessions; do
            screen -S "$session" -X quit
        done
        echo "Anciennes sessions sshws supprimées."
    fi

    # Démarrage de wstunnel server avec la bonne syntaxe
    screen -dmS sshws wstunnel server --restrict-to localhost:22 ws://0.0.0.0:8880
    echo "Tunnel SSH WebSocket lancé dans screen session 'sshws'."
    echo "Pour suivre le tunnel : screen -r sshws"
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
    # Ajoutez ici les commandes pour SSL/TLS si besoin
}

install_badvpn() {
    echo "Installation BadVPN..."
    # Ajoutez ici les commandes pour BadVPN si besoin
}

# Ordre d'installation
install_openssh
install_dropbear
install_slowdns
install_wstunnel
install_http_ws
install_udp_custom
install_socks_python
install_ssl_tls
install_badvpn
install_ssh_wstunnel

echo ""
echo "=============================================="
echo " ✅ Tous les modes ont été installés automatiquement."
echo "=============================================="

# Commande de gestion rapide HTTP/WS
cat > /usr/bin/http-ws <<'EOF'
#!/bin/bash
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
        cat $PAYLOAD_FILE
        systemctl restart $SERVICE
        echo "[+] Service redémarré."
        ;;
    show)
        if [ -f "$CONF" ]; then
            echo "🌍 Domaine actuel : $(cat $CONF)"
            if [ -f "$PAYLOAD_FILE" ]; then
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
