#!/bin/bash
# menu5.sh - Panneau de contrôle installation/désinstallation amélioré

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
# Fonctions SlowDNS améliorées
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
# Fonctions OpenSSH
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
# Fonctions Dropbear
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
# Fonctions UDP Custom avec désinstallation améliorée
# =====================================================
install_udp_custom() {
    echo ">>> Nettoyage avant installation UDP Custom..."
    pkill -f udp_custom || true
    killall udp_custom 2>/dev/null || true
    rm -f $HOME/Kighmu/udp_custom.sh
    systemctl stop udp_custom.service 2>/dev/null || true
    systemctl disable udp_custom.service 2>/dev/null || true
    rm -f /etc/systemd/system/udp_custom.service
    systemctl daemon-reload
    ufw delete allow 54000/udp 2>/dev/null || true
    iptables -D INPUT -p udp --dport 54000 -j ACCEPT 2>/dev/null || true

    echo ">>> Installation/configuration UDP Custom..."
    bash "$HOME/Kighmu/udp_custom.sh" || echo "Script introuvable."

    ufw allow 54000/udp
    iptables -I INPUT -p udp --dport 54000 -j ACCEPT
}

uninstall_udp_custom() {
    echo ">>> Désinstallation complète UDP Custom..."

    pids=$(pgrep -f udp_custom)
    if [ ! -z "$pids" ]; then
        echo "Terminer processus UDP Custom : $pids"
        kill -15 $pids
        sleep 2
        pids=$(pgrep -f udp_custom)
        if [ ! -z "$pids" ]; then
            echo "Processus résistants kill -9 : $pids"
            kill -9 $pids
        fi
    else
        echo "Aucun processus UDP Custom actif."
    fi

    if systemctl list-units --full -all | grep -Fq 'udp_custom.service'; then
        systemctl stop udp_custom.service
        systemctl disable udp_custom.service
        rm -f /etc/systemd/system/udp_custom.service
        systemctl daemon-reload
        echo "Service UDP Custom arrêté et supprimé."
    else
        echo "Aucun service systemd UDP Custom trouvé."
    fi

    rm -f $HOME/Kighmu/udp_custom.sh

    ufw delete allow 54000/udp 2>/dev/null || true
    iptables -D INPUT -p udp --dport 54000 -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -p udp --sport 54000 -j ACCEPT 2>/dev/null || true

    echo "[OK] UDP Custom désinstallé."
}

# =====================================================
# Fonctions SOCKS Python avec désinstallation améliorée
# =====================================================
install_socks_python() {
    echo ">>> Nettoyage avant installation SOCKS Python..."
    pkill -f socks_python || true
    killall socks_python 2>/dev/null || true
    rm -f $HOME/Kighmu/socks_python.sh
    systemctl stop socks_python.service 2>/dev/null || true
    systemctl disable socks_python.service 2>/dev/null || true
    rm -f /etc/systemd/system/socks_python.service
    systemctl daemon-reload
    ufw delete allow 8080/tcp 2>/dev/null || true
    ufw delete allow 9090/tcp 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 9090 -j ACCEPT 2>/dev/null || true

    echo ">>> Installation/configuration SOCKS Python..."
    bash "$HOME/Kighmu/socks_python.sh" || echo "Script introuvable."

    ufw allow 8080/tcp
    ufw allow 9090/tcp
    iptables -I INPUT -p tcp --dport 8080 -j ACCEPT
    iptables -I INPUT -p tcp --dport 9090 -j ACCEPT
}

uninstall_socks_python() {
    echo ">>> Désinstallation complète SOCKS Python..."

    pids=$(pgrep -f socks_python)
    if [ ! -z "$pids" ]; then
        echo "Terminer processus SOCKS Python : $pids"
        kill -15 $pids
        sleep 2
        pids=$(pgrep -f socks_python)
        if [ ! -z "$pids" ]; then
            echo "Processus résistants kill -9 : $pids"
            kill -9 $pids
        fi
    else
        echo "Aucun processus SOCKS Python actif."
    fi

    if systemctl list-units --full -all | grep -Fq 'socks_python.service'; then
        systemctl stop socks_python.service
        systemctl disable socks_python.service
        rm -f /etc/systemd/system/socks_python.service
        systemctl daemon-reload
        echo "Service SOCKS Python arrêté et supprimé."
    else
        echo "Aucun service systemd SOCKS Python trouvé."
    fi

    rm -f $HOME/Kighmu/socks_python.sh

    ufw delete allow 8080/tcp 2>/dev/null || true
    ufw delete allow 9090/tcp 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -p tcp --sport 8080 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 9090 -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -p tcp --sport 9090 -j ACCEPT 2>/dev/null || true

    echo "[OK] SOCKS Python désinstallé."
}

# =====================================================
# Fonctions SSL/TLS et BadVPN à compléter plus tard
# =====================================================
install_ssl_tls() {
    echo ">>> Installation SSL/TLS (à compléter)"
}
uninstall_ssl_tls() {
    echo ">>> Désinstallation SSL/TLS (à compléter)"
}
install_badvpn() {
    echo ">>> Installation BadVPN (à compléter)"
}
uninstall_badvpn() {
    echo ">>> Désinstallation BadVPN (à compléter)"
}

# =====================================================
# Fonction générique gestion des modes
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
