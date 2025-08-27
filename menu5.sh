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

        # Demande du domaine
        read -rp "Entrez le domaine à utiliser pour HTTP/WSS: " DOMAIN

        # Stockage
        mkdir -p /etc/proxy_wss
        echo "$DOMAIN" > /etc/proxy_wss/domain.conf

        # Création du service systemd
        cat > /etc/systemd/system/proxy_wss.service <<EOF
[Unit]
Description=HTTP/WSS Proxy Service
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

        echo "✅ HTTP/WSS installé avec succès."
        echo "🌍 Domaine configuré: $DOMAIN"
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


# ======================================================
# Ajout de la commande de gestion rapide HTTP/WSS
# ======================================================
cat > /usr/bin/http-wss <<'EOF'
#!/bin/bash
# Commande de gestion du mode HTTP/WSS

CONF=/etc/proxy_wss/domain.conf
SERVICE=proxy_wss

case "$1" in
    domain)
        if [ -z "$2" ]; then
            echo "Usage: http-wss domain monsite.tld"
            exit 1
        fi
        mkdir -p /etc/proxy_wss
        echo "$2" > $CONF
        echo "[+] Domaine mis à jour : $2"
        systemctl restart $SERVICE
        echo "[+] Service redémarré."
        ;;
    show)
        if [ -f "$CONF" ]; then
            echo "🌍 Domaine actuel : $(cat $CONF)"
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
        echo "Commande HTTP/WSS Manager"
        echo "Usage: http-wss [action]"
        echo "Actions disponibles:"
        echo "  domain <monsite.tld>   -> changer le domaine"
        echo "  show                   -> afficher le domaine actuel"
        echo "  restart                -> redémarrer le service"
        echo "  status                 -> afficher l'état du service"
        echo "  logs                   -> afficher les logs du service"
        ;;
esac
EOF

chmod +x /usr/bin/http-wss
