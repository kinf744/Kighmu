#!/bin/bash
# menu5.sh
# Panneau de contrôle installation/désinstallation

clear
echo "+--------------------------------------------+"
echo "|      PANNEAU DE CONTROLE DES MODES         |"
echo "+--------------------------------------------+"

# Détection IP et uptime
HOST_IP=$(curl -s https://api.ipify.org)
UPTIME=$(uptime -p)
echo "IP: $HOST_IP | Uptime: $UPTIME"
echo ""

# =====================================================
# Fonctions pour OpenSSH
# =====================================================
install_openssh() {
    echo ">>> Installation d'OpenSSH..."
    apt-get install -y openssh-server
    systemctl enable ssh
    systemctl start ssh
    echo "[OK] OpenSSH installé."
}

uninstall_openssh() {
    echo ">>> Désinstallation d'OpenSSH..."
    apt-get remove -y openssh-server
    systemctl disable ssh
    echo "[OK] OpenSSH supprimé."
}

# =====================================================
# Fonctions pour Dropbear
# =====================================================
install_dropbear() {
    echo ">>> Installation de Dropbear..."
    apt-get install -y dropbear
    systemctl enable dropbear
    systemctl start dropbear
    echo "[OK] Dropbear installé."
}

uninstall_dropbear() {
    echo ">>> Désinstallation de Dropbear..."
    apt-get remove -y dropbear
    systemctl disable dropbear
    echo "[OK] Dropbear supprimé."
}

# =====================================================
# Fonctions pour SlowDNS
# =====================================================
install_slowdns() {
    echo ">>> Installation/configuration de SlowDNS..."
    bash "$HOME/Kighmu/slowdns.sh" || echo "SlowDNS : script introuvable."
}

uninstall_slowdns() {
    echo ">>> Désinstallation de SlowDNS..."
    pkill -f slowdns || true
    echo "[OK] SlowDNS désinstallé (processus tués)."
}

# =====================================================
# Fonctions pour UDP Custom
# =====================================================
install_udp_custom() { bash "$HOME/Kighmu/udp_custom.sh" || echo "Script introuvable."; }
uninstall_udp_custom() { pkill -f udp_custom || echo "UDP Custom déjà arrêté."; }

# =====================================================
# Fonctions pour UDP Request (ajouté)
# =====================================================
install_udp_request() { bash "$HOME/Kighmu/udp_request.sh" || echo "Script introuvable."; }
uninstall_udp_request() { pkill -f udp_request || echo "UDP Request déjà arrêté."; }

# =====================================================
# Fonctions pour SOCKS/Python
# =====================================================
install_socks_python() { bash "$HOME/Kighmu/socks_python.sh" || echo "Script introuvable."; }
uninstall_socks_python() { pkill -f socks_python || echo "SOCKS déjà arrêté."; }

# =====================================================
# Fonctions pour SSL/TLS
# =====================================================
install_ssl_tls() { echo ">>> Installation SSL/TLS (à compléter)"; }
uninstall_ssl_tls() { echo ">>> Désinstallation SSL/TLS (à compléter)"; }

# =====================================================
# Fonctions pour BadVPN
# =====================================================
install_badvpn() { echo ">>> Installation BadVPN (à compléter)"; }
uninstall_badvpn() { echo ">>> Désinstallation BadVPN (à compléter)"; }

# =====================================================
# Fonction générique qui affiche le sous-menu
# =====================================================
manage_mode() {
    MODE_NAME=$1
    INSTALL_FUNC=$2
    UNINSTALL_FUNC=$3

    while true; do
        echo ""
        echo "+--------------------------------------------+"
        echo "   Gestion du mode : $MODE_NAME"
        echo "+--------------------------------------------+"
        echo " [1] Installer"
        echo " [2] Désinstaller"
        echo " [0] Retour"
        echo "----------------------------------------------"
        echo -n "👉 Choisissez une action : "
        read action

        case $action in
            1) $INSTALL_FUNC ;;
            2) $UNINSTALL_FUNC ;;
            0) break ;;
            *) echo "❌ Mauvais choix, réessayez." ;;
        esac
    done
}

# =====================================================
# Menu principal
# =====================================================
while true; do
    echo ""
    echo "+================ MENU PRINCIPAL =================+"
    echo " [1] OpenSSH"
    echo " [2] Dropbear"
    echo " [3] SlowDNS"
    echo " [4] UDP Custom"
    echo " [5] UDP Request"
    echo " [6] SOCKS/Python"
    echo " [7] SSL/TLS"
    echo " [8] BadVPN"
    echo " [0] Quitter"
    echo "+================================================+"
    echo -n "👉 Choisissez un mode : "
    read choix

    case $choix in
        1) manage_mode "OpenSSH" install_openssh uninstall_openssh ;;
        2) manage_mode "Dropbear" install_dropbear uninstall_dropbear ;;
        3) manage_mode "SlowDNS" install_slowdns uninstall_slowdns ;;
        4) manage_mode "UDP Custom" install_udp_custom uninstall_udp_custom ;;
        5) manage_mode "UDP Request" install_udp_request uninstall_udp_request ;;
        6) manage_mode "SOCKS/Python" install_socks_python uninstall_socks_python ;;
        7) manage_mode "SSL/TLS" install_ssl_tls uninstall_ssl_tls ;;
        8) manage_mode "BadVPN" install_badvpn uninstall_badvpn ;;
        0) echo "🚪 Sortie du panneau de contrôle." ; exit 0 ;;
        *) echo "❌ Option invalide, réessayez." ;;
    esac
done
