#!/bin/bash
# menu5.sh
# Panneau de contrôle installation/désinstallation

clear
echo -e "\e[34m+--------------------------------------------+\e[0m"
echo -e "\e[34m|      PANNEAU DE CONTROLE DES MODES         |\e[0m"
echo -e "\e[34m+--------------------------------------------+\e[0m"

# Détection IP et uptime
HOST_IP=$(curl -s https://api.ipify.org)
UPTIME=$(uptime -p)
echo "IP: $HOST_IP | time: $UPTIME"
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
    bash "/root/Kighmu/slowdns.sh" > /tmp/slowdns_install.log 2>&1 || { echo "SlowDNS : script introuvable ou erreur."; tail -n 20 /tmp/slowdns_install.log; }
}

uninstall_slowdns() {
    echo ">>> Désinstallation complète de SlowDNS..."

    systemctl stop slowdns.service || true
    systemctl disable slowdns.service || true
    rm -f /etc/systemd/system/slowdns.service
    systemctl daemon-reload

    pkill -f sldns-server || true

    iptables -D INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null || true
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null || true
    iptables-save > /etc/iptables/rules.v4

    rm -rf /etc/slowdns
    rm -f /usr/local/bin/sldns-server

    if command -v ufw >/dev/null 2>&1; then
      ufw delete allow 5300/udp || true
      ufw reload
    fi

    echo "[OK] SlowDNS désinstallé et nettoyé."
}

# =====================================================
# Fonctions pour UDP Custom
# =====================================================
install_udp_custom() {
    echo ">>> Installation UDP Custom..."
    bash "/root/Kighmu/udp_custom.sh" > /tmp/udp_custom_install.log 2>&1 || { echo "UDP Custom : script introuvable ou erreur."; tail -n 20 /tmp/udp_custom_install.log; }
}

uninstall_udp_custom() { pkill -f udp_custom || echo "UDP Custom déjà arrêté."; }

# =====================================================
# Fonctions pour SOCKS/Python
# =====================================================
install_socks_python() {
    echo ">>> Installation SOCKS Python..."
    bash "/root/Kighmu/socks_python.sh" > /tmp/socks_python_install.log 2>&1 || { echo "SOCKS Python : script introuvable ou erreur."; tail -n 20 /tmp/socks_python_install.log; }
}

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
        echo -e "\e[34m+--------------------------------------------+\e[0m"
        echo -e "\e[34m   Gestion du mode : $MODE_NAME\e[0m"
        echo -e "\e[34m+--------------------------------------------+\e[0m"
        echo " [1] Installer"
        echo " [2] Désinstaller"
        echo " [0] Retour"
        echo -e "\e[34m----------------------------------------------\e[0m"
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
    echo -e "\e[34m+================ MENU PRINCIPAL =================+\e[0m"
    echo " [1] OpenSSH"
    echo " [2] Dropbear"
    echo " [3] SlowDNS"
    echo " [4] UDP Custom"
    echo " [5] SOCKS/Python"
    echo " [6] SSL/TLS"
    echo " [7] BadVPN"
    echo " [0] Retour"
    echo -e "\e[34m+================================================+\e[0m"
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
