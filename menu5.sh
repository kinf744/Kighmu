#!/bin/bash
# menu5.sh - Panneau de contrôle installation/désinstallation, nettoyage complet pour chaque mode

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
# Fonctions pour SlowDNS améliorées
# =====================================================
install_slowdns() {
    echo ">>> Nettoyage avant installation SlowDNS..."
    pkill -f slowdns || true
    rm -rf $HOME/.slowdns
    rm -f /usr/local/bin/slowdns
    systemctl stop slowdns.service 2>/dev/null || true
    systemctl disable slowdns.service 2>/dev/null || true
    rm -f /etc/systemd/system/slowdns.service
    systemctl daemon-reload
    ufw delete allow 5300/udp 2>/dev/null || true

    echo ">>> Installation/configuration de SlowDNS..."
    bash "$HOME/Kighmu/slowdns.sh" || echo "SlowDNS : script introuvable."

    ufw allow 5300/udp
}

uninstall_slowdns() {
    echo ">>> Désinstallation de SlowDNS complète..."
    pkill -f slowdns || true
    rm -rf $HOME/.slowdns
    rm -f /usr/local/bin/slowdns
    systemctl stop slowdns.service 2>/dev/null || true
    systemctl disable slowdns.service 2>/dev/null || true
    rm -f /etc/systemd/system/slowdns.service
    systemctl daemon-reload
    ufw delete allow 5300/udp 2>/dev/null || true
    echo "[OK] SlowDNS désinstallé et nettoyé."
}

# =====================================================
# Fonctions pour OpenSSH améliorées
# =====================================================
install_openssh() {
    echo ">>> Nettoyage avant installation OpenSSH..."
    pkill -f sshd || true
    systemctl stop ssh 2>/dev/null || true
    systemctl disable ssh 2>/dev/null || true
    apt-get remove -y openssh-server
    apt-get install -y openssh-server
    systemctl enable ssh
    systemctl start ssh
    echo "[OK] OpenSSH installé."
}

uninstall_openssh() {
    echo ">>> Désinstallation d'OpenSSH complète..."
    systemctl stop ssh 2>/dev/null || true
    systemctl disable ssh 2>/dev/null || true
    apt-get remove -y openssh-server
    echo "[OK] OpenSSH désinstallé."
}

# =====================================================
# Fonctions pour Dropbear améliorées
# =====================================================
install_dropbear() {
    echo ">>> Nettoyage avant installation Dropbear..."
    pkill -f dropbear || true
    systemctl stop dropbear 2>/dev/null || true
    systemctl disable dropbear 2>/dev/null || true
    apt-get remove -y dropbear
    apt-get install -y dropbear
    systemctl enable dropbear
    systemctl start dropbear
    echo "[OK] Dropbear installé."
}

uninstall_dropbear() {
    echo ">>> Désinstallation de Dropbear complète..."
    systemctl stop dropbear 2>/dev/null || true
    systemctl disable dropbear 2>/dev/null || true
    apt-get remove -y dropbear
    echo "[OK] Dropbear désinstallé."
}

# =====================================================
# Fonctions pour UDP Custom
# =====================================================
install_udp_custom() {
    echo ">>> Nettoyage avant installation UDP Custom..."
    pkill -f udp_custom || true
    # Ajoutez ici suppression de fichiers et services si utilisés
    bash "$HOME/Kighmu/udp_custom.sh" || echo "Script introuvable."
}

uninstall_udp_custom() {
    echo ">>> Désinstallation complète UDP Custom..."
    pkill -f udp_custom || true
    # Ajoutez ici nettoyage fichiers/services liés udp_custom
    echo "[OK] UDP Custom désinstallé."
}

# =====================================================
# Fonctions pour SOCKS Python
# =====================================================
install_socks_python() {
    echo ">>> Nettoyage avant installation SOCKS Python..."
    pkill -f socks_python || true
    # Nettoyage fichiers/services si nécessaire
    bash "$HOME/Kighmu/socks_python.sh" || echo "Script introuvable."
}

uninstall_socks_python() {
    echo ">>> Désinstallation complète SOCKS Python..."
    pkill -f socks_python || true
    # Nettoyage fichiers/services si nécessaire
    echo "[OK] SOCKS Python désinstallé."
}

# =====================================================
# Fonctions pour SSL/TLS (à compléter)
# =====================================================
install_ssl_tls() {
    echo ">>> Nettoyage avant installation SSL/TLS..."
    # Arrêtez, désactivez services, supprimez fichiers si nécessaires
    echo ">>> Installation SSL/TLS (à compléter)"
}

uninstall_ssl_tls() {
    echo ">>> Désinstallation SSL/TLS complète..."
    # Arrêtez, désactivez services, supprimez fichiers
    echo ">>> Désinstallation SSL/TLS (à compléter)"
}

# =====================================================
# Fonctions pour BadVPN (à compléter)
# =====================================================
install_badvpn() {
    echo ">>> Nettoyage avant installation BadVPN..."
    pkill -f badvpn || true
    # Nettoyage fichiers/services si nécessaire
    echo ">>> Installation BadVPN (à compléter)"
}

uninstall_badvpn() {
    echo ">>> Désinstallation complète BadVPN..."
    pkill -f badvpn || true
    # Nettoyage fichiers/services si nécessaire
    echo ">>> Désinstallation BadVPN (à compléter)"
}

# =====================================================
# Fonction générique de gestion des modes
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
    echo " [5] SOCKS/Python"
    echo " [6] SSL/TLS"
    echo " [7] BadVPN"
    echo " [0] Quitter"
    echo "+================================================+"
    echo -n "👉 Choisissez un mode : "
    read choix

    case $choix in
        1) manage_mode "OpenSSH" install_openssh uninstall_openssh ;;
        2) manage_mode "Dropbear" install_dropbear uninstall_dropbear ;;
        3) manage_mode "SlowDNS" install_slowdns uninstall_slowdns ;;
        4) manage_mode "UDP Custom" install_udp_custom uninstall_udp_custom ;;
        5) manage_mode "SOCKS/Python" install_socks_python uninstall_socks_python ;;
        6) manage_mode "SSL/TLS" install_ssl_tls uninstall_ssl_tls ;;
        7) manage_mode "BadVPN" install_badvpn uninstall_badvpn ;;
        0) echo "🚪 Sortie du panneau de contrôle." ; exit 0 ;;
        *) echo "❌ Option invalide, réessayez." ;;
    esac
done
