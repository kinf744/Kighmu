#!/bin/bash
# ==============================================
# menu5.sh - Gestion complète des modes (installation/désinstallation)
# ==============================================

INSTALL_DIR="$HOME/Kighmu"
WIDTH=60
CYAN="\e[36m"
RESET="\e[0m"

# Fonctions d'affichage
line_full() { echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
content_line() { printf "| %-56s |\n" "$1"; }
center_line() {
    local text="$1"
    local clean_text=$(echo -e "$text" | sed 's/\x1B\[[0-9;]*[mK]//g')
    local padding=$(( (WIDTH - ${#clean_text}) / 2 ))
    printf "|%*s%s%*s|\n" "$padding" "" "$text" "$padding" ""
}

# Fonction pour créer un service systemd
create_service() {
    local name="$1"
    local exec="$2"
    local service_file="/etc/systemd/system/${name}.service"

    echo "[Unit]
Description=$name Service
After=network.target

[Service]
ExecStart=$exec
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target" > "$service_file"

    systemctl daemon-reload
    systemctl enable --now "$name"
    echo "✔️ Service $name installé et démarré"
}

# Vérification du statut des services
service_status() {
    local svc="$1"
    case "$svc" in
        "socks-python")
            pgrep -f "KIGHMUPROXY.py" >/dev/null && echo "[ACTIF]" || echo "[INACTIF]"
            ;;
        *)
            if systemctl list-unit-files | grep -q "^$svc.service"; then
                systemctl is-active --quiet "$svc" && echo "[ACTIF]" || echo "[INACTIF]"
            else
                echo "[NON INSTALLÉ]"
            fi
            ;;
    esac
}

show_modes_status() {
    clear
    line_full
    center_line "GESTION DES MODES"
    line_full
    center_line "Statut des modes installés et ports"
    line_simple
    content_line "OpenSSH     : 22 $(service_status ssh)"
    content_line "Dropbear    : 90 $(service_status dropbear)"
    content_line "SlowDNS     : 5300 $(service_status slowdns)"
    content_line "UDP Custom  : 54000 $(service_status udp-custom)"
    content_line "SOCKS/Python: 8080 $(service_status socks-python)"
    content_line "SSL/TLS     : 443 $(service_status nginx)"
    content_line "BadVPN      : 7303 $(service_status badvpn)"
    line_simple
}

install_mode() {
    case $1 in
        1) apt-get install -y openssh-server && systemctl enable --now ssh && echo "✔️ OpenSSH installé" ;;
        2) apt-get install -y dropbear && systemctl enable --now dropbear && echo "✔️ Dropbear installé" ;;
        3) [[ -x "$INSTALL_DIR/slowdns.sh" ]] && bash "$INSTALL_DIR/slowdns.sh" || echo "❌ slowdns.sh introuvable" ;;
        4) [[ -x "$INSTALL_DIR/udp_custom.sh" ]] && bash "$INSTALL_DIR/udp_custom.sh" || echo "❌ udp_custom.sh introuvable" ;;
        5) [[ -x "$INSTALL_DIR/socks_python.sh" ]] && bash "$INSTALL_DIR/socks_python.sh" || echo "❌ socks_python.sh introuvable" ;;
        6) apt-get install -y nginx && systemctl enable --now nginx && echo "✔️ Nginx/SSL installé" ;;
        7) create_service "badvpn" "/usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7303 --max-clients 500" ;;
        *) echo "❌ Choix invalide" ;;
    esac
}

uninstall_mode() {
    case $1 in
        1) systemctl disable --now ssh && apt-get remove -y openssh-server && echo "✔️ OpenSSH désinstallé" ;;
        2) systemctl disable --now dropbear && apt-get remove -y dropbear && echo "✔️ Dropbear désinstallé" ;;
        3) systemctl disable --now slowdns && echo "✔️ SlowDNS désinstallé" ;;
        4) systemctl disable --now udp-custom && echo "✔️ UDP-Custom désinstallé" ;;
        5)
            pkill -f "KIGHMUPROXY.py" 2>/dev/null
            echo "✔️ SOCKS-Python désinstallé"
            ;;
        6) systemctl disable --now nginx && apt-get remove -y nginx && echo "✔️ Nginx/SSL désinstallé" ;;
        7) 
            systemctl disable --now badvpn
            rm -f /etc/systemd/system/badvpn.service
            systemctl daemon-reload
            echo "✔️ BadVPN désinstallé" 
            ;;
        *) echo "❌ Choix invalide" ;;
    esac
}

# Menu principal des modes
while true; do
    show_modes_status
    line_full
    content_line "1) Installer un mode"
    content_line "2) Désinstaller un mode"
    content_line "0) Retour au menu principal"
    line_simple

    read -p "Votre choix : " action
    case $action in
        1)
            echo "Choisissez un mode à installer :"
            echo "1) OpenSSH Server"
            echo "2) Dropbear SSH"
            echo "3) SlowDNS"
            echo "4) UDP Custom"
            echo "5) SOCKS/Python"
            echo "6) SSL/TLS"
            echo "7) BadVPN"
            read -p "Numéro du mode : " choix
            install_mode "$choix"
            ;;
        2)
            echo "Choisissez un mode à désinstaller :"
            echo "1) OpenSSH Server"
            echo "2) Dropbear SSH"
            echo "3) SlowDNS"
            echo "4) UDP Custom"
            echo "5) SOCKS/Python"
            echo "6) SSL/TLS"
            echo "7) BadVPN"
            read -p "Numéro du mode : " choix
            uninstall_mode "$choix"
            ;;
        0) break ;;
        *) echo "❌ Choix invalide" ; read -p "Appuyez sur Entrée pour continuer..." ;;
    esac
done
