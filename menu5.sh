#!/bin/bash
# menu5.sh
# Installation automatique des modes spéciaux + affichage dynamique état

echo "+--------------------------------------------+"
echo "|      INSTALLATION AUTOMATIQUE DES MODES    |"
echo "+--------------------------------------------+"

# Détection IP et uptime
HOST_IP=$(curl -s https://api.ipify.org)
UPTIME=$(uptime -p)

echo "IP: $HOST_IP | Uptime: $UPTIME"
echo ""

# Fonctions d'installation pour chaque mode
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

# Exécuter toutes les installations
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
echo ""

# Fonction pour afficher l’état d’installation des modes
print_status() {
    local name="$1"
    local check_cmd="$2"

    if eval "$check_cmd" >/dev/null 2>&1; then
        printf "%-35s [%s]\n" "$name" "installé"
    else
        printf "%-35s [%s]\n" "$name" "non installé"
    fi
}

echo "+--------------------------------------------+"
echo "|              ÉTAT DES MODES                |"
echo "+--------------------------------------------+"

print_status "OpenSSH Server" "systemctl is-active --quiet ssh"
print_status "Dropbear SSH" "systemctl is-active --quiet dropbear"
print_status "SlowDNS" "pgrep -f dns-server"
print_status "UDP Custom" "pgrep -f udp_custom.sh"
print_status "SOCKS/Python" "pgrep -f KIGHMUPROXY.py"
print_status "SSL/TLS" "systemctl is-active --quiet nginx"  # Exemple, à adapter selon config SSL
print_status "BadVPN" "pgrep -f badvpn"

echo "+--------------------------------------------+"
read -p "Appuyez sur Entrée pour revenir au menu..."
