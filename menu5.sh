#!/bin/bash
# menu5.sh
# Panneau de contrôle pour installation des modes

clear
echo "+--------------------------------------------+"
echo "|      PANNEAU DE CONTROLE D'INSTALLATION    |"
echo "+--------------------------------------------+"

# Détection IP et uptime
HOST_IP=$(curl -s https://api.ipify.org)
UPTIME=$(uptime -p)
echo "IP: $HOST_IP | Uptime: $UPTIME"
echo ""

# ==========================
# Définition des fonctions
# ==========================
install_openssh() {
    echo ">>> Installation / vérification Openssh..."
    apt-get install -y openssh-server
    systemctl enable ssh
    systemctl start ssh
    echo ">>> [OK] OpenSSH installé."
}

install_dropbear() {
    echo ">>> Installation / vérification Dropbear..."
    apt-get install -y dropbear
    systemctl enable dropbear
    systemctl start dropbear
    echo ">>> [OK] Dropbear installé."
}

install_slowdns() {
    echo ">>> Installation / configuration SlowDNS..."
    bash "$HOME/Kighmu/slowdns.sh" || echo "SlowDNS : script non trouvé ou erreur."
}

install_udp_custom() {
    echo ">>> Installation UDP Custom..."
    bash "$HOME/Kighmu/udp_custom.sh" || echo "UDP Custom : script non trouvé ou erreur."
}

install_socks_python() {
    echo ">>> Installation SOCKS/Python..."
    bash "$HOME/Kighmu/socks_python.sh" || echo "SOCKS/Python : script non trouvé ou erreur."
}

install_ssl_tls() {
    echo ">>> Installation SSL/TLS..."
    # Ajoute tes commandes ici
}

install_badvpn() {
    echo ">>> Installation BadVPN..."
    # Ajoute tes commandes ici
}

# ==========================
# Menu dynamique
# ==========================
while true; do
    echo ""
    echo "+================ MENU INSTALLATION ================+"
    echo " [1] Installer OpenSSH"
    echo " [2] Installer Dropbear"
    echo " [3] Installer SlowDNS"
    echo " [4] Installer UDP Custom"
    echo " [5] Installer SOCKS/Python"
    echo " [6] Installer SSL/TLS"
    echo " [7] Installer BadVPN"
    echo " [0] Quitter"
    echo "+==================================================+"
    echo -n "👉 Choisissez une option : "
    read choix

    case $choix in
        1) install_openssh ;;
        2) install_dropbear ;;
        3) install_slowdns ;;
        4) install_udp_custom ;;
        5) install_socks_python ;;
        6) install_ssl_tls ;;
        7) install_badvpn ;;
        0) echo "🚪 Sortie du panneau de contrôle." ; exit 0 ;;
        *) echo "❌ Option invalide, réessayez." ;;
    esac
done
