#!/bin/bash
# menu5.sh - Panneau de contrôle avec nettoyage complet UDP Custom et SOCKS Python

clear
echo "+--------------------------------------------+"
echo "|      PANNEAU DE CONTROLE DES MODES         |"
echo "+--------------------------------------------+"

# Détection IP et uptime
HOST_IP=$(curl -s https://api.ipify.org)
UPTIME=$(uptime -p)
echo "IP: $HOST_IP | Uptime: $UPTIME"
echo ""

# ==============================================
# Fonctions UDP Custom avec nettoyage complet
# ==============================================
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
    pkill -f udp_custom || true
    killall udp_custom 2>/dev/null || true
    rm -f $HOME/Kighmu/udp_custom.sh
    systemctl stop udp_custom.service 2>/dev/null || true
    systemctl disable udp_custom.service 2>/dev/null || true
    rm -f /etc/systemd/system/udp_custom.service
    systemctl daemon-reload
    ufw delete allow 54000/udp 2>/dev/null || true
    iptables -D INPUT -p udp --dport 54000 -j ACCEPT 2>/dev/null || true

    echo "[OK] UDP Custom désinstallé et nettoyé."
}

# ==============================================
# Fonctions SOCKS Python avec nettoyage complet
# ==============================================
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

    echo "[OK] SOCKS Python désinstallé et nettoyé."
}

# =====================================================
# Ajoutez ici les autres fonctions install/uninstall...
# Exemple pour SlowDNS, OpenSSH, Dropbear à garder du script précédent.

# =====================================================
# Gestion des modes et menu principal restent identiques
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

while true; do
    echo ""
    echo "+================ MENU PRINCIPAL =================+"
    echo " [1] UDP Custom"
    echo " [2] SOCKS/Python"
    echo " [0] Quitter"
    echo "+================================================+"
    echo -n "👉 Choisissez un mode : "
    read choix

    case $choix in
        1) manage_mode "UDP Custom" install_udp_custom uninstall_udp_custom ;;
        2) manage_mode "SOCKS/Python" install_socks_python uninstall_socks_python ;;
        0) echo "🚪 Sortie du panneau de contrôle." ; exit 0 ;;
        *) echo "❌ Option invalide, réessayez." ;;
    esac
done
