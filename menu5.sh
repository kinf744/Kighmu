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
# Fonctions spécifiques tunnel SSH HTTP WS
# =====================================================
install_ssh_ws_tunnel() {
    echo ">>> Installation du tunnel SSH HTTP WS..."
    # Assurez-vous que le script proxyws.sh est dans le même dossier ou modifiez le chemin
    bash ./proxyws.sh
    echo "[OK] Tunnel SSH HTTP WS installé."
}

uninstall_ssh_ws_tunnel() {
    echo ">>> Désinstallation du tunnel SSH HTTP WS..."
    # Ici, vous pouvez par exemple tuer tous les processus python écoutant sur port 80 ou autre
    pids=$(lsof -ti tcp:80)
    if [ -n "$pids" ]; then
      kill -9 $pids
      echo "[OK] Processus sur port 80 terminés."
    else
      echo "Aucun processus sur port 80."
    fi
    # Facultatif : désactiver la config NGINX spécifique
    if [ -f /etc/nginx/sites-enabled/ssh_ws_proxy ]; then
      rm /etc/nginx/sites-enabled/ssh_ws_proxy
      echo "Configuration NGINX désactivée."
      systemctl reload nginx
    fi
    echo "[OK] Tunnel SSH HTTP WS désinstallé."
}

# =====================================================
# Fonction générique pour le sous-menu tunnel SSH WS
# =====================================================
manage_ssh_ws_tunnel() {
    while true; do
        echo ""
        echo "+--------------------------------------------+"
        echo "   Gestion du tunnel SSH HTTP WS"
        echo "+--------------------------------------------+"
        echo " [1] Installer"
        echo " [2] Désinstaller"
        echo " [0] Retour"
        echo "----------------------------------------------"
        echo -n "👉 Choisissez une action : "
        read action

        case $action in
            1) install_ssh_ws_tunnel ;;
            2) uninstall_ssh_ws_tunnel ;;
            0) break ;;
            *) echo "❌ Mauvais choix, réessayez." ;;
        esac
    done
}

# =====================================================
# Les autres fonctions install/uninstall existantes...

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

# (Vos autres fonctions ici...)

# =====================================================
# Menu principal incluant le tunnel SSH HTTP WS
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
    echo " [8] Tunnel SSH HTTP WS"   # <- Nouvelle entrée
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
        8) manage_ssh_ws_tunnel ;;   # <- Appel du nouveau sous-menu
        0) echo "🚪 Sortie du panneau de contrôle." ; exit 0 ;;
        *) echo "❌ Option invalide, réessayez." ;;
    esac
done
