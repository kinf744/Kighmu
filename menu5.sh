#!/bin/bash
# menu5.sh - Panneau de contrôle installation/désinstallation amélioré

# Définition des couleurs
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

afficher_modes_ports() {
    local any_active=0

    if systemctl is-active --quiet ssh || pgrep -x sshd >/dev/null 2>&1; then any_active=1; fi
    if systemctl is-active --quiet dropbear || pgrep -x dropbear >/dev/null 2>&1; then any_active=1; fi
    if systemctl is-active --quiet slowdns.service || pgrep -f "sldns-server" >/dev/null 2>&1 || screen -list | grep -q slowdns_session; then any_active=1; fi
    if systemctl is-active --quiet udp_custom.service || pgrep -f udp-custom-linux-amd64 >/dev/null 2>&1 || screen -list | grep -q udp_custom; then any_active=1; fi
    if systemctl is-active --quiet socks_python.service || pgrep -f KIGHMUPROXY.py >/dev/null 2>&1 || screen -list | grep -q socks_python; then any_active=1; fi
    if systemctl is-active --quiet socks_python_ws.service || pgrep -f ws2_proxy.py >/dev/null 2>&1; then any_active=1; fi
    if systemctl is-active --quiet stunnel4.service || pgrep -f stunnel >/dev/null 2>&1; then any_active=1; fi
    if systemctl is-active --quiet badvpn.service || pgrep -f "badvpn-udpgw" >/dev/null 2>&1 || screen -list | grep -q badvpn_session; then any_active=1; fi
    if systemctl is-active --quiet hysteria.service || pgrep -f hysteria >/dev/null 2>&1; then any_active=1; fi
    if systemctl is-active --quiet ws_wssr.service || pgrep -f ws_wss_server.py >/dev/null 2>&1; then any_active=1; fi

    if [[ $any_active -eq 0 ]]; then
        return
    fi

    echo -e "${CYAN}Modes actifs et ports utilisés:${RESET}"

    if systemctl is-active --quiet ssh || pgrep -x sshd >/dev/null 2>&1; then
        echo -e "  - OpenSSH: ${GREEN}port 22${RESET}"
    fi
    if systemctl is-active --quiet dropbear || pgrep -x dropbear >/dev/null 2>&1; then
        DROPBEAR_PORT=$(grep -oP '(?<=-p )\d+' /etc/default/dropbear 2>/dev/null || echo "22")
        echo -e "  - Dropbear: ${GREEN}port $DROPBEAR_PORT${RESET}"
    fi
    if systemctl is-active --quiet slowdns.service || pgrep -f "sldns-server" >/dev/null 2>&1 || screen -list | grep -q slowdns_session; then
        echo -e "  - SlowDNS: ${GREEN}ports UDP 5300${RESET}"
    fi
    if systemctl is-active --quiet udp_custom.service || pgrep -f udp-custom-linux-amd64 >/dev/null 2>&1 || screen -list | grep -q udp_custom; then
        echo -e "  - UDP Custom: ${GREEN}port UDP 54000${RESET}"
    fi
    if systemctl is-active --quiet socks_python.service || pgrep -f KIGHMUPROXY.py >/dev/null 2>&1 || screen -list | grep -q socks_python; then
        echo -e "  - SOCKS Python: ${GREEN}ports TCP 8080${RESET}"
    fi
    if systemctl is-active --quiet socks_python_ws.service || pgrep -f ws2_proxy.py >/dev/null 2>&1; then
        if [ -f /etc/systemd/system/socks_python_ws.service ]; then
            PROXY_WS_PORT=$(grep "ExecStart=" /etc/systemd/system/socks_python_ws.service | awk '{print $NF}')
        else
            PROXY_WS_PORT=$(sudo lsof -Pan -p $(pgrep -f ws2_proxy.py | head -n1) -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $9}' | cut -d: -f2)
        fi
        PROXY_WS_PORT=${PROXY_WS_PORT:-9090}
        echo -e "  - proxy ws: ${GREEN}port TCP $PROXY_WS_PORT${RESET}"
    fi
    if systemctl is-active --quiet stunnel4.service || pgrep -f stunnel >/dev/null 2>&1; then
        echo -e "  - Stunnel SSL/TLS: ${GREEN}port TCP 444${RESET}"
    fi
    if systemctl is-active --quiet badvpn.service || pgrep -f stunnel >/dev/null 2>&1; then
        echo -e "  - badvpn: ${GREEN}port UDP 7300${RESET}"
    fi
    if systemctl is-active --quiet hysteria.service || pgrep -f hysteria >/dev/null 2>&1; then
        echo -e "  - Hysteria UDP : ${GREEN}port UDP 22000${RESET}"
    fi
    if systemctl is-active --quiet ws_wssr.service || pgrep -f ws_wss_server.py >/dev/null 2>&1 || screen -list | grep -q ws_wssr; then
        echo -e "  - WS/WSS Tunnel: ${GREEN}WS port 8880 | WSS port 443${RESET}"
    fi
}

# --- Fonctions d'installation et désinstallation existantes ---
install_slowdns() {
    echo ">>> Nettoyage avant installation SlowDNS..."
    pkill -f slowdns || true
    rm -rf "$HOME/.slowdns"
    rm -f /usr/local/bin/slowdns
    systemctl stop slowdns.service 2>/dev/null || true
    systemctl disable slowdns.service 2>/dev/null || true
    rm -f /etc/systemd/system/slowdns.service
    systemctl daemon-reload

    # Suppression éventuelle des règles iptables existantes
    iptables -D INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null || true
    iptables-save > /etc/iptables/rules.v4
    systemctl restart netfilter-persistent

    echo ">>> Installation/configuration SlowDNS..."
    bash "$HOME/Kighmu/slowdns.sh" || echo "SlowDNS : script introuvable."
}

uninstall_slowdns() {
    echo ">>> Désinstallation complète SlowDNS..."
    pkill -f slowdns || true
    rm -rf "$HOME/.slowdns"
    rm -f /usr/local/bin/slowdns
    systemctl stop slowdns.service 2>/dev/null || true
    systemctl disable slowdns.service 2>/dev/null || true
    rm -f /etc/systemd/system/slowdns.service
    systemctl daemon-reload

    # Suppression des règles iptables
    iptables -D INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null || true
    iptables-save > /etc/iptables/rules.v4
    systemctl restart netfilter-persistent

    echo -e "${GREEN}[OK] SlowDNS désinstallé.${RESET}"
}

install_openssh() {
    echo ">>> Installation d'OpenSSH..."
    apt-get install -y openssh-server
    systemctl enable ssh
    systemctl start ssh
    echo -e "${GREEN}[OK] OpenSSH installé.${RESET}"
}

uninstall_openssh() {
    echo ">>> Désinstallation d'OpenSSH..."
    apt-get remove -y openssh-server
    systemctl disable ssh
    echo -e "${GREEN}[OK] OpenSSH supprimé.${RESET}"
}

install_dropbear() {
    echo ">>> Installation de Dropbear..."
    apt-get install -y dropbear
    systemctl enable dropbear
    systemctl start dropbear
    echo -e "${GREEN}[OK] Dropbear installé.${RESET}"
}

uninstall_dropbear() {
    echo ">>> Désinstallation de Dropbear..."
    apt-get remove -y dropbear
    systemctl disable dropbear
    echo -e "${GREEN}[OK] Dropbear supprimé.${RESET}"
}

install_udp_custom() {
    echo ">>> Installation UDP Custom via script..."
    bash "$HOME/Kighmu/udp_custom.sh" || echo "Script introuvable."
}

uninstall_udp_custom() {
    echo ">>> Désinstallation UDP Custom..."

    # Arrêt des processus
    pids=$(pgrep -f udp-custom-linux-amd64 || true)
    if [ -n "$pids" ]; then
        kill -15 $pids
        sleep 2
        pids=$(pgrep -f udp-custom-linux-amd64 || true)
        if [ -n "$pids" ]; then
            kill -9 $pids
        fi
    fi

    # Arrêt et suppression du service systemd
    if systemctl list-units --full -all | grep -Fq 'udp_custom.service'; then
        systemctl stop udp_custom.service || true
        systemctl disable udp_custom.service || true
        rm -f /etc/systemd/system/udp_custom.service
        systemctl daemon-reload
    fi

    # Suppression des fichiers d’installation
    rm -rf /root/udp-custom

    # Suppression des règles iptables persistantes
    iptables -D INPUT -p udp --dport 54000 -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -p udp --sport 54000 -j ACCEPT 2>/dev/null || true
    iptables-save > /etc/iptables/rules.v4
    systemctl restart netfilter-persistent || true

    echo -e "${GREEN}[OK] UDP Custom désinstallé.${RESET}"
}

install_socks_python() {
    echo ">>> Installation SOCKS Python via script..."
    bash "$HOME/Kighmu/socks_python.sh" || echo "Script introuvable."
}

uninstall_socks_python() {
    echo ">>> Désinstallation complète SOCKS Python..."
    
    # Arrêt des processus proxy
    pids=$(pgrep -f KIGHMUPROXY.py)
    if [ -n "$pids" ]; then
        echo "Arrêt des processus proxy (PID: $pids)..."
        kill -15 $pids
        sleep 2
        pids=$(pgrep -f KIGHMUPROXY.py)
        [ -n "$pids" ] && kill -9 $pids
    fi

    # Arrêt et suppression du service systemd
    if systemctl list-units --full -all | grep -Fq 'socks_python.service'; then
        systemctl stop socks_python.service
        systemctl disable socks_python.service
        rm -f /etc/systemd/system/socks_python.service
        systemctl daemon-reload
    fi

    # Suppression du script
    rm -f /usr/local/bin/KIGHMUPROXY.py

    # Suppression des règles iptables persistantes pour les ports 8080 et 9090
    for port in 8080 9090; do
        iptables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null || true
    done
    iptables-save | tee /etc/iptables/rules.v4
    systemctl restart netfilter-persistent

    echo -e "${GREEN}[OK] SOCKS Python désinstallé.${RESET}"
}

install_proxy_ws() {
    echo ">>> Installation proxy WS via script sockspy.sh..."
    bash "$HOME/Kighmu/sockspy.sh" || echo "Script sockspy introuvable."
}

uninstall_proxy_ws() {
    echo ">>> Désinstallation proxy WS..."

    # Arrêt et suppression des processus existants
    PIDS=$(pgrep -f ws2_proxy.py || true)
    if [ -n "$PIDS" ]; then
        echo "Arrêt des processus proxy WS existants (PID: $PIDS)..."
        kill -15 $PIDS
        sleep 2
        PIDS=$(pgrep -f ws2_proxy.py || true)
        if [ -n "$PIDS" ]; then
            kill -9 $PIDS
        fi
    fi

    # Arrêt et suppression du service systemd
    if systemctl list-units --full -all | grep -Fq 'socks_python_ws.service'; then
        systemctl stop socks_python_ws.service || true
        systemctl disable socks_python_ws.service || true
        rm -f /etc/systemd/system/socks_python_ws.service
        systemctl daemon-reload
    fi

    # Suppression du script
    rm -f /usr/local/bin/ws2_proxy.py

    # Nettoyage des règles iptables seulement
    iptables -D INPUT -p tcp --dport 9090 -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -p tcp --sport 9090 -j ACCEPT 2>/dev/null || true

    echo -e "${GREEN}[OK] Proxy WS désinstallé.${RESET}"
}

install_ssl_tls() {
    echo ">>> Lancement du script d'installation SSL/TLS externe..."
    bash "$HOME/Kighmu/ssl.sh" || echo "Script SSL/TLS introuvable ou erreur."
}

uninstall_ssl_tls() {
    echo ">>> Désinstallation complète de Stunnel SSL/TLS..."
    systemctl stop stunnel4 2>/dev/null || true
    systemctl disable stunnel4 2>/dev/null || true
    rm -f /etc/stunnel/stunnel.conf
    systemctl daemon-reload

    # Fermeture du port TCP 444 via iptables
    iptables -D INPUT -p tcp --dport 444 -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -p tcp --sport 444 -j ACCEPT 2>/dev/null || true

    echo -e "${GREEN}[OK] Stunnel SSL/TLS désinstallé proprement.${RESET}"
}

install_badvpn() {
    echo ">>> Installation BadVPN via script..."
    bash "$HOME/Kighmu/badvpn.sh" || echo "Script introuvable."
}

uninstall_badvpn() {
    echo ">>> Désinstallation complète BadVPN..."

    # Arrêt et suppression du service systemd
    if systemctl list-units --full -all | grep -Fq 'badvpn.service'; then
        echo "Arrêt et désactivation du service badvpn.service..."
        systemctl stop badvpn.service || true
        systemctl disable badvpn.service || true
        rm -f "$SYSTEMD_UNIT"
        systemctl daemon-reload
    fi

    # Suppression du binaire
    if [ -f "$BIN_PATH" ]; then
        echo "Suppression du binaire BadVPN..."
        rm -f "$BIN_PATH"
    fi

    # Nettoyage des règles iptables persistantes pour le port
    echo "Suppression des règles iptables pour le port UDP $PORT..."
    iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -p udp --sport "$PORT" -j ACCEPT 2>/dev/null || true
    iptables-save | tee /etc/iptables/rules.v4
    systemctl restart netfilter-persistent || true

    echo -e "${GREEN}[OK] BadVPN désinstallé.${RESET}"
}

HYST_PORT=22000

install_hysteria() {
    echo ">>> Installation Hysteria..."

    local SCRIPT_PATH="$HOME/Kighmu/hysteria.sh"

    # Vérification de la présence du script
    if [ ! -f "$SCRIPT_PATH" ]; then
        echo "❌ Script hysteria.sh introuvable à l’emplacement attendu : $SCRIPT_PATH"
        return 1
    fi

    # Exécution sécurisée du script externe
    bash "$SCRIPT_PATH" || {
        echo "❌ Erreur lors de l’exécution du script hysteria.sh."
        return 1
    }

    # Vérification du service systemd
    if systemctl is-active --quiet hysteria; then
        echo -e "${GREEN}[OK] Hysteria installé et lancé.${RESET}"
    else
        echo -e "${RED}❌ Hysteria ne s’est pas lancé correctement.${RESET}"
        systemctl status hysteria --no-pager
        journalctl -u hysteria -n 20 --no-pager
    fi
}

uninstall_hysteria() {
    echo ">>> Désinstallation Hysteria..."

    # Arrêt et suppression du service systemd
    if systemctl list-units --full -all | grep -Fq 'hysteria.service'; then
        echo "==> Arrêt et désactivation du service systemd..."
        systemctl stop hysteria.service 2>/dev/null || true
        systemctl disable hysteria.service 2>/dev/null || true
        rm -f /etc/systemd/system/hysteria.service
        systemctl daemon-reload
    fi

    # Arrêt des processus encore en mémoire
    if pgrep -f hysteria >/dev/null 2>&1; then
        echo "==> Arrêt des processus Hysteria en cours..."
        pkill -f hysteria || true
        sleep 1
    fi

    # Nettoyage du port UDP 22000
    echo "==> Nettoyage des règles iptables pour le port 22000..."
    iptables -D INPUT -p udp --dport 22000 -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -p udp --sport 22000 -j ACCEPT 2>/dev/null || true

    # Suppression optionnelle de la configuration
    read -rp "Souhaitez-vous supprimer la configuration (/etc/hysteria) ? [y/N] : " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        rm -rf /etc/hysteria
        echo "==> Configuration supprimée."
    else
        echo "==> Configuration conservée."
    fi

    echo -e "${GREEN}[OK] Hysteria désinstallé proprement.${RESET}"
}

# --- AJOUT WS/WSS SSH ---
install_ws_wss() {
    echo ">>> Installation du tunnel WS/WSS SSH..."
    if [ -f /usr/local/bin/ws_wssr.sh ]; then
        bash /usr/local/bin/ws_wssr.sh
    elif [ -f "$HOME/Kighmu/ws_wssr.sh" ]; then
        bash "$HOME/Kighmu/ws_wssr.sh"
    else
        echo "❌ Script ws_wssr.sh introuvable."
        return 1
    fi
    echo -e "${GREEN}[OK] Tunnel WS/WSS SSH installé et lancé.${RESET}"
}

uninstall_ws_wss() {
    echo ">>> Désinstallation complète du tunnel WS/WSS SSH..."
    systemctl stop ws_wss_server.service 2>/dev/null || true
    systemctl disable ws_wss_server.service 2>/dev/null || true
    rm -f /etc/systemd/system/ws_wss_server.service
    rm -f /usr/local/bin/ws_wss_server.py /usr/local/bin/ws_wssr.sh
    systemctl daemon-reload
    # Suppression ports sans UFW
    iptables -D INPUT -p tcp --dport 8880 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -p tcp --sport 8880 -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -p tcp --sport 443 -j ACCEPT 2>/dev/null || true
    echo -e "${GREEN}[OK] Tunnel WS/WSS SSH désinstallé.${RESET}"
}

install_ws_slowdns() {
    echo ">>> Lancement du script d'installation WS+SlowDNS..."
    bash "$HOME/Kighmu/slowdns_wsproxy.sh" || echo "Script WS+SlowDNS introuvable ou erreur."
}

uninstall_ws_slowdns() {
    echo ">>> Désinstallation complète du tunnel WS+SlowDNS..."
    systemctl stop wsproxy.service slowdns.service 2>/dev/null || true
    systemctl disable wsproxy.service slowdns.service 2>/dev/null || true
    rm -f /usr/local/bin/slowdns_wsproxy.py /usr/local/bin/sldns-server
    rm -f /etc/systemd/system/wsproxy.service /etc/systemd/system/slowdns.service
    systemctl daemon-reload
    iptables -D INPUT -p tcp --dport 9900 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null || true
    iptables-save > /etc/iptables/rules.v4
    systemctl restart netfilter-persistent

    echo "[OK] Tunnel WS+SlowDNS désinstallé proprement."
}

# --- Interface utilisateur ---
manage_mode() {
    MODE_NAME=$1; INSTALL_FUNC=$2; UNINSTALL_FUNC=$3
    while true; do
        clear
        echo -e "${CYAN}+======================================================+${RESET}"
        echo -e "|          🚀 Gestion du mode : $MODE_NAME 🚀          |"
        echo -e "${CYAN}+======================================================+${RESET}"
        echo -e "${GREEN}${BOLD}[1]${RESET} ${YELLOW}Installer${RESET}"
        echo -e "${GREEN}${BOLD}[2]${RESET} ${YELLOW}Désinstaller${RESET}"
        echo -e "${GREEN}${BOLD}[0]${RESET} ${YELLOW}Retour${RESET}"
        echo -e "${CYAN}+======================================================+${RESET}"
        echo -ne "${BOLD}${YELLOW}👉 Choisissez une action : ${RESET}"
        read action
        case $action in
            1) $INSTALL_FUNC; read -p "Appuyez sur Entrée..." ;;
            2) $UNINSTALL_FUNC; read -p "Appuyez sur Entrée..." ;;
            0) break ;;
            *) echo -e "${RED}❌ Mauvais choix.${RESET}"; sleep 1 ;;
        esac
    done
}

while true; do
    clear
    HOST_IP=$(curl -s https://api.ipify.org)
    UPTIME=$(uptime -p)
    echo -e "${CYAN}+=====================================================+${RESET}"
    echo -e "|           🚀 PANNEAU DE CONTROLE DES MODES 🚀       |"
    echo -e "${CYAN}+=====================================================+${RESET}"
    echo -e "${CYAN} IP: ${GREEN}$HOST_IP${RESET} | ${CYAN}Up: ${GREEN}$UPTIME${RESET}"
    afficher_modes_ports
    echo -e "${CYAN}+======================================================+${RESET}"
    echo -e "${GREEN}${BOLD}[01]${RESET} ${YELLOW}OpenSSH${RESET}"
    echo -e "${GREEN}${BOLD}[02]${RESET} ${YELLOW}Dropbear${RESET}"
    echo -e "${GREEN}${BOLD}[03]${RESET} ${YELLOW}SlowDNS${RESET}"
    echo -e "${GREEN}${BOLD}[04]${RESET} ${YELLOW}UDP Custom${RESET}"
    echo -e "${GREEN}${BOLD}[05]${RESET} ${YELLOW}SOCKS/Python${RESET}"
    echo -e "${GREEN}${BOLD}[06]${RESET} ${YELLOW}SSL/TLS${RESET}"
    echo -e "${GREEN}${BOLD}[07]${RESET} ${YELLOW}BadVPN${RESET}"
    echo -e "${GREEN}${BOLD}[08]${RESET} ${YELLOW}proxy ws${RESET}"
    echo -e "${GREEN}${BOLD}[09]${RESET} ${YELLOW}Hysteria${RESET}"
    echo -e "${GREEN}${BOLD}[10]${RESET} ${YELLOW}Tunnel WS/WSS SSH${RESET}"
    echo -e "${GREEN}${BOLD}[11]${RESET} ${YELLOW} Slowdns_ws${RESET}"
    echo -e "${GREEN}${BOLD}[00]${RESET} ${YELLOW}Quitter${RESET}"
    echo -e "${CYAN}+======================================================+${RESET}"
    echo -ne "${BOLD}${YELLOW}👉 Choisissez un mode : ${RESET}"
    read choix
    case $choix in
        1) manage_mode "OpenSSH" install_openssh uninstall_openssh ;;
        2) manage_mode "Dropbear" install_dropbear uninstall_dropbear ;;
        3) manage_mode "SlowDNS" install_slowdns uninstall_slowdns ;;
        4) manage_mode "UDP Custom" install_udp_custom uninstall_udp_custom ;;
        5) manage_mode "SOCKS/Python" install_socks_python uninstall_socks_python ;;
        6) manage_mode "SSL/TLS" install_ssl_tls uninstall_ssl_tls ;;
        7) manage_mode "BadVPN" install_badvpn uninstall_badvpn ;;
        8) manage_mode "proxy ws" install_proxy_ws uninstall_proxy_ws ;;
        9) manage_mode "Hysteria" install_hysteria uninstall_hysteria ;;
        10) manage_mode "Tunnel WS/WSS SSH" install_ws_wss uninstall_ws_wss ;;
        11) manage_mode "Slowdns_ws" install_ws_slowdns uninstall_ws_slowdns ;;
        0) echo -e "${RED}🚪 Sortie du panneau de contrôle.${RESET}" ; exit 0 ;;
        *) echo -e "${RED}❌ Option invalide, réessayez.${RESET}" ;;
    esac
done
