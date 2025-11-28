#!/bin/bash

# Fichier stockage utilisateurs
USER_DB="./utilisateurs.json"

# Couleurs ANSI pour mise en forme
CYAN="\u001B[1;36m"
YELLOW="\u001B[1;33m"
GREEN="\u001B[1;32m"
RED="\u001B[1;31m"
WHITE="\u001B[1;37m"
RESET="\u001B[0m"

# === Configuration SlowDNS (modifiée pour DNS-AGN) ===
SLOWDNS_DIR="/etc/slowdns_v2ray"
SLOWDNS_BIN="/usr/local/bin/dns-server"
SLOWDNS_PORT=5400
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"

# Clés fixes (Option A — insérées en dur)
SLOWDNS_PRIVATE_KEY="4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa"
SLOWDNS_PUBLIC_KEY="2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c"

# Générer lien vmess au format base64 JSON (fonction globale)
generer_lien_vmess() {
    local nom="$1"
    local domaine="$2"
    local port="$3"
    local uuid="$4"

    local json_config=$(cat <<-EOF
{
"v": "2",
"ps": "$nom",
"add": "$domaine",
"port": "$port",
"id": "$uuid",
"aid": "0",
"net": "ws",
"type": "none",
"host": "$domaine",
"path": "/vmess-ws",
"tls": "none",
"scy": "auto"
}
EOF
    )

    echo "vmess://$(echo -n "$json_config" | base64 -w 0)"
}

# Affiche le menu avec titre dans cadre
afficher_menu() {
    clear
    echo -e "${CYAN}╔═════════════════════════════════════════════════════╗${RESET}"
    echo -e "${YELLOW}║       V2RAY PROTOCOLE${RESET}"
    echo -e "${YELLOW}║--------------------------------------------------${RESET}"
}

# Affiche la ligne indiquant l'état du tunnel V2Ray WS
afficher_mode_v2ray_ws() {
    if systemctl is-active --quiet v2ray.service; then
        local v2ray_port=$(jq -r '.inbounds[0].port' /etc/v2ray/config.json 2>/dev/null || echo "5401")
        echo -e "${CYAN}Tunnel actif:${RESET}"
        echo -e "  - V2Ray WS sur le port TCP ${GREEN}$v2ray_port${RESET}"
    fi
}

# Affiche les options du menu
show_menu() {
    echo -e "${YELLOW}║--------------------------------------------------${RESET}"
    echo -e "${YELLOW}║ 1) Installer tunnel V2Ray WS${RESET}"
    echo -e "${YELLOW}║ 2) Créer nouvel utilisateur${RESET}"
    echo -e "${YELLOW}║ 3) Supprimer un utilisateur${RESET}"
    echo -e "${YELLOW}║ 4) Désinstaller V2Ray${RESET}"
    echo -e "${YELLOW}║ 5) Installer tunnel SlowDNS (DNS-AGN)${RESET}"
    echo -e "${RED}║ 0) Quitter${RESET}"
    echo -e "${CYAN}╚═════════════════════════════════════════════════════╝${RESET}"
    echo -n "Choisissez une option : "
}

# Générer UUID v4
generer_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# Créer et démarrer le service systemd V2Ray
creer_service_systemd_v2ray() {
    echo "Création du service systemd pour V2Ray..."
    sudo tee /etc/systemd/system/v2ray.service > /dev/null <<EOF
[Unit]
Description=V2Ray Service
After=network.target
Wants=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/v2ray run -config /etc/v2ray/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=65536
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=v2ray

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable v2ray.service
    sudo systemctl start v2ray.service
    sudo systemctl status v2ray.service --no-pager
    echo "Service systemd V2Ray configuré et démarré."

    echo "Configuration des règles iptables pour le port V2Ray 8088..."
    sudo iptables -I INPUT -p tcp --dport 5401 -j ACCEPT
    sudo iptables -I INPUT -p udp --dport 5401 -j ACCEPT

    if ! command -v netfilter-persistent &>/dev/null; then
        sudo apt update
        sudo apt install -y netfilter-persistent
    fi

    sudo netfilter-persistent save
    echo "Règles iptables configurées et sauvegardées."
}

# Installer V2Ray WS sans TLS avec gestion avancée des logs
installer_v2ray() {
    echo -n "Entrez votre domaine (ex: example.com) : "
    read domaine

    LOGFILE="/var/log/v2ray_install.log"
    sudo touch $LOGFILE
    sudo chmod 640 $LOGFILE

    echo "Installation de V2Ray WS sans TLS... (logs: $LOGFILE)"

    set +e
    wget -q https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip -O /tmp/v2ray.zip 2>> $LOGFILE
    ret=$?
    set -e
    if [[ $ret -ne 0 ]]; then
        echo "Erreur: échec du téléchargement, voir $LOGFILE"
        return 1
    fi

    unzip -o /tmp/v2ray.zip -d /tmp/v2ray >> $LOGFILE 2>&1 || {
        echo "Erreur: échec de la décompression, voir $LOGFILE"
        return 1
    }

    if [[ -f /tmp/v2ray/v2ray ]]; then
        sudo mv /tmp/v2ray/v2ray /usr/local/bin/
        sudo chmod +x /usr/local/bin/v2ray
    else
        echo "Erreur: binaire v2ray non trouvé après décompression." | tee -a $LOGFILE
        return 1
    fi

    sudo mkdir -p /etc/v2ray

    cat <<EOF | sudo tee /etc/v2ray/config.json > /dev/null
{
  "inbounds": [
    {
      "port": 5401,
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess-ws",
          "headers": {
            "Host": "$domaine"
          }
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

    # Stockage du domaine pour réutilisation dans la création utilisateur
    echo "$domaine" | sudo tee /.v2ray_domain > /dev/null

    creer_service_systemd_v2ray

    echo -e "${GREEN}V2Ray WS installé et lancé sur le port 5401 avec path /vmess-ws pour le domaine ${domaine}${RESET}"
    echo "N'oubliez pas d'ouvrir et rediriger le port 5401 sur votre VPS."
    read -p "Appuyez sur Entrée pour continuer..."
}

# === Fonction d'installation SlowDNS (DNS-AGN - MODIFIÉE) ===
installer_slowdns() {
    echo "Installation SlowDNS (DNS-AGN) en cours..."

    sudo mkdir -p "$SLOWDNS_DIR"

    echo "Téléchargement du binaire DNS-AGN..."
    sudo wget -q -O "$SLOWDNS_BIN" https://github.com/khaledagn/DNS-AGN/raw/main/dns-server
    sudo chmod +x "$SLOWDNS_BIN"
    if [ ! -x "$SLOWDNS_BIN" ]; then
        echo "ERREUR : Échec du téléchargement du binaire DNS-AGN." >&2
        return 1
    fi

    echo "$SLOWDNS_PRIVATE_KEY" | sudo tee "$SERVER_KEY" > /dev/null
    echo "$SLOWDNS_PUBLIC_KEY"  | sudo tee "$SERVER_PUB" > /dev/null
    sudo chmod 600 "$SERVER_KEY"
    sudo chmod 644 "$SERVER_PUB"

    read -rp "Entrez le NameServer (NS) pour SlowDNS (ex: ns.example.com) : " NAMESERVER
    if [[ -z "$NAMESERVER" ]]; then
        echo "NameServer invalide." >&2
        return 1
    fi
    echo "$NAMESERVER" | sudo tee "$CONFIG_FILE" > /dev/null
    echo "NameServer enregistré dans $CONFIG_FILE"

    # Création du script wrapper de démarrage slowdns (adapté pour DNS-AGN)
    sudo tee /usr/local/bin/slowdns_v2ray-start.sh > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail

SLOWDNS_DIR="/etc/slowdns_v2ray"
SLOWDNS_BIN="/usr/local/bin/dns-server"
PORT=5400
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

wait_for_interface() {
    interface=""
    while [ -z "$interface" ]; do
        interface=$(ip -o link show up | awk -F': ' '{print $2}' \
            | grep -v '^lo$' \
            | grep -vE '^(docker|veth|br|virbr|tun|tap|wl|vmnet|vboxnet)' \
            | head -n1)
        [ -z "$interface" ] && sleep 2
    done
    echo "$interface"
}

# Définition des variables avant usage
PORT=5400                     # Port UDP pour SlowDNS
V2RAY_INTER_PORT=5401          # Port TCP intermédiaire vers V2Ray

setup_iptables() {
    interface="$1"
    # Ouvrir le port UDP SlowDNS
    if ! iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT &>/dev/null; then
        iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
    fi
    # Ouvrir le port TCP intermédiaire pour V2Ray
    if ! iptables -C INPUT -p tcp --dport "$V2RAY_INTER_PORT" -j ACCEPT &>/dev/null; then
        iptables -I INPUT -p tcp --dport "$V2RAY_INTER_PORT" -j ACCEPT
    fi
}

log "Attente de l'interface réseau..."
interface=$(wait_for_interface)
log "Interface détectée : $interface"

log "Réglage MTU à 1400 pour éviter la fragmentation DNS..."
ip link set dev "$interface" mtu 1400 || log "Échec réglage MTU, continuer"

log "Application des règles iptables..."
setup_iptables "$interface"

log "Démarrage du serveur SlowDNS (DNS-AGN)..."
NAMESERVER=$(cat "$CONFIG_FILE")

exec "$SLOWDNS_BIN" -udp :$PORT -privkey-file "$SERVER_KEY" "$NAMESERVER" 127.0.0.1:$V2RAY_INTER_PORT

    sudo chmod +x /usr/local/bin/slowdns_v2ray-start.sh

    # systemd service slowdns (modifié en slowdns_v2ray.service)
    sudo tee /etc/systemd/system/slowdns_v2ray.service > /dev/null <<EOF
[Unit]
Description=SlowDNS Server Tunnel (DNS-AGN)
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/khaledagn/DNS-AGN

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/slowdns_v2ray-start.sh
Restart=on-failure
RestartSec=3
StandardOutput=append:/var/log/slowdns_v2ray.log
StandardError=append:/var/log/slowdns_v2ray.log
SyslogIdentifier=slowdns_v2ray
LimitNOFILE=1048576
Nice=0
CPUSchedulingPolicy=other
IOSchedulingClass=best-effort
IOSchedulingPriority=4
TimeoutStartSec=20
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable slowdns_v2ray.service
    sudo systemctl restart slowdns_v2ray.service

    echo "Configuration iptables pour SlowDNS..."
    sudo iptables -I INPUT -p udp --dport $SLOWDNS_PORT -j ACCEPT
    sudo iptables -I INPUT -p tcp --dport $SLOWDNS_PORT -j ACCEPT
    if ! command -v netfilter-persistent &>/dev/null; then
        sudo apt update
        sudo apt install -y netfilter-persistent
    fi
    sudo netfilter-persistent save
    echo -e "${GREEN}SlowDNS (DNS-AGN) installé et démarré avec persistance iptables.${RESET}"
}

# Gestion utilisateurs (charger, sauvegarder, créer, supprimer)
charger_utilisateurs() {
    if [[ ! -f $USER_DB ]]; then
        echo "[]" > "$USER_DB"
    fi
    utilisateurs=$(cat "$USER_DB")
}

sauvegarder_utilisateurs() {
    echo "$utilisateurs" > "$USER_DB"
}

creer_utilisateur() {
    charger_utilisateurs
    echo -n "Entrez un nom d'utilisateur : "
    read nom
    echo -n "Durée de validité (en jours) : "
    read duree

    uuid=$(generer_uuid)
    date_exp=$(date -d "+${duree} days" +%Y-%m-%d)
    utilisateurs=$(echo "$utilisateurs" | jq --arg n "$nom" --arg u "$uuid" --arg d "$date_exp" '. += [{"nom": $n, "uuid": $u, "expire": $d}]')
    sauvegarder_utilisateurs

    # ← AJOUT AUTOMATIQUE UUID DANS V2RAY → 
    if [[ -f /etc/v2ray/config.json ]] && command -v jq >/dev/null 2>&1; then
        ajouter_client_v2ray "$uuid" "$nom"
    else
        echo "⚠️  Installez d'abord V2Ray (option 1) pour activer les clients"
    fi

    if [[ -f /.v2ray_domain ]]; then
        domaine=$(cat /.v2ray_domain)
    else
        domaine="votre-domaine.com"
    fi

    local V2RAY_INTER_PORT="5401"
    lien_vmess=$(generer_lien_vmess "$nom" "$domaine" "$V2RAY_INTER_PORT" "$uuid")

    PUB_KEY=$SLOWDNS_PUBLIC_KEY
    NAMESERVER=$(cat /etc/slowdns_v2ray/ns.conf 2>/dev/null || echo "NS_non_defini")

    clear
    echo -e "=============================="
    echo -e "🧩 VMESS"
    echo -e "=============================="
    echo -e "📄 Configuration générée pour : $nom"
    echo -e "--------------------------------------------------"
    echo -e "➤ DOMAINE : $domaine"
    echo -e "➤ PORTs :"
    echo -e "   NTLS  : $V2RAY_INTER_PORT"
    echo -e "➤ UUID généré :"
    echo -e "   NTLS  : $uuid"
    echo -e "➤ Paths :"
    echo -e "   NTLS   : /vmess-ws"
    echo -e "➤ Validité : $duree jours (expire le $date_exp)"
    echo ""
    echo "Clé publique : $PUB_KEY"
    echo "NameServer  : $NAMESERVER"
    echo ""
    echo -e "●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●"
    echo ""
    echo -e "┃ Non-TLS : $lien_vmess"
    echo -e "●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●"
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
}

supprimer_utilisateur() {
    charger_utilisateurs
    count=$(echo "$utilisateurs" | jq length)
    if [ "$count" -eq 0 ]; then
        echo "Aucun utilisateur à supprimer."
        read -p "Appuyez sur Entrée pour continuer..."
        return
    fi
    echo "Utilisateurs actuels :"
    for i in $(seq 0 $((count - 1))); do
        nom=$(echo "$utilisateurs" | jq -r ".[$i].nom")
        expire=$(echo "$utilisateurs" | jq -r ".[$i].expire")
        echo "$((i+1))) $nom (expire le $expire)"
    done
    echo -n "Entrez le numéro de l'utilisateur à supprimer : "
    read choix
    if (( choix < 1 || choix > count )); then
        echo "Choix invalide."
        read -p "Appuyez sur Entrée pour continuer..."
        return
    fi
    index=$((choix - 1))
    utilisateurs=$(echo "$utilisateurs" | jq "del(.[${index}])")
    sauvegarder_utilisateurs
    echo "Utilisateur supprimé."
    read -p "Appuyez sur Entrée pour continuer..."
}

desinstaller_v2ray() {
    echo -n "Êtes-vous sûr de vouloir désinstaller V2Ray et SlowDNS ? (o/N) : "
    read reponse
    if [[ "$reponse" =~ ^[Oo]$ ]]; then
        # Arrêt et désactivation V2Ray
        sudo systemctl stop v2ray.service
        sudo systemctl disable v2ray.service
        sudo rm -f /etc/systemd/system/v2ray.service
        sudo pkill v2ray 2>/dev/null
        sudo rm -rf /usr/local/bin/v2ray /usr/local/bin/v2ctl /etc/v2ray
        sudo rm -f /.v2ray_domain

        # Arrêt et désactivation SlowDNS
        sudo systemctl stop slowdns_v2ray.service
        sudo systemctl disable slowdns_v2ray.service
        sudo rm -f /etc/systemd/system/slowdns_v2ray.service
        sudo pkill dns-server 2>/dev/null
        sudo rm -rf /etc/slowdns_v2ray /usr/local/bin/dns-server

        # Recharger les services systemd
        sudo systemctl daemon-reload

        echo "V2Ray et SlowDNS désinstallés et nettoyés."
    else
        echo "Désinstallation annulée."
    fi
    read -p "Appuyez sur Entrée pour continuer..."
}

# Programme principal
while true; do
    afficher_menu
    afficher_mode_v2ray_ws
    show_menu
    read option
    case "$option" in
        1) installer_v2ray ;;
        2) creer_utilisateur ;;
        3) supprimer_utilisateur ;;
        4) desinstaller_v2ray ;;
        5) installer_slowdns ;;
        0) echo "Sortie..." ; exit 0 ;;
        *) echo "Option invalide." ; sleep 1 ;;
    esac
done
