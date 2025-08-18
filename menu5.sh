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
    # commandes d'installation Openssh ici, par exemple :
    apt-get install -y openssh-server
    systemctl enable ssh
    systemctl start ssh
}

install_dropbear() {
    echo "Installation / vérification Dropbear..."
    # commandes d'installation Dropbear ici
    apt-get install -y dropbear
    systemctl enable dropbear
    systemctl start dropbear
}

install_slowdns() {
    echo "Installation / configuration SlowDNS..."
    # Exécution du script slowdns.sh si présent
    bash "$HOME/Kighmu/slowdns.sh" || echo "SlowDNS : script non trouvé ou erreur."
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

# Appel séquentiel de toutes les installations
install_openssh
install_dropbear
install_slowdns
install_udp_custom
install_socks_python
install_ssl_tls
install_badvpn

echo ""
echo "=============================================="
echo " ✅ Tous les modes ont été installés automatiquement."
echo "=============================================="
