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

# ================================================
# Fonctions spécifiques tunnel SSH HTTP WS
# ================================================
install_ssh_ws_tunnel() {
    echo ">>> Installation du tunnel SSH HTTP WS..."
    PROXYWS_PATH="$(dirname "$0")/proxyws.sh"
    if [ ! -f "$PROXYWS_PATH" ]; then
        echo "❌ Erreur : le script $PROXYWS_PATH est introuvable."
        echo "Veuillez vous assurer que proxyws.sh est présent dans le même dossier que ce script."
        return 1
    fi
    bash "$PROXYWS_PATH"
    echo "[OK] Tunnel SSH HTTP WS installé."
}

uninstall_ssh_ws_tunnel() {
    echo ">>> Désinstallation du tunnel SSH HTTP WS..."
    pids=$(lsof -ti tcp:80)
    if [ -n "$pids" ]; then
      kill -9 $pids
      echo "[OK] Processus sur port 80 terminés."
    else
      echo "Aucun processus sur port 80."
    fi

    if [ -f /etc/nginx/sites-enabled/ssh_ws_proxy ]; then
      rm /etc/nginx/sites-enabled/ssh_ws_proxy
      echo "Configuration NGINX désactivée."
      systemctl reload nginx
    fi
    echo "[OK] Tunnel SSH HTTP WS désinstallé."
}

# ================================================
# Sous-menu tunnel SSH HTTP WS
# ================================================
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

# ================================================
# Fonctions existantes (OpenSSH, Dropbear, etc.)
# ================================================
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

# Ajoutez vos autres fonctions install/uninstall ici (Dropbear, SlowDNS, etc.)

# ================================================
# Menu principal
# ================================================
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
    echo " [8] Tunnel SSH HTTP WS"
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
        8) manage_ssh_ws_tunnel ;;
        0) echo "🚪 Sortie du panneau de contrôle." ; exit 0 ;;
        *) echo "❌ Option invalide, réessayez." ;;
    esac
done


# Fonction générique manage_mode (si nécessaire)
manage_mode() {
    local mode_name="$1"
    local install_func="$2"
    local uninstall_func="$3"

    while true; do
        echo ""
        echo "+--------------------------------------------+"
        echo "   Gestion du mode : $mode_name"
        echo "+--------------------------------------------+"
        echo " [1] Installer"
        echo " [2] Désinstaller"
        echo " [0] Retour"
        echo "----------------------------------------------"
        echo -n "👉 Choisissez une action : "
        read action

        case $action in
            1) $install_func ;;
            2) $uninstall_func ;;
            0) break ;;
            *) echo "❌ Mauvais choix, réessayez." ;;
        esac
    done
}
