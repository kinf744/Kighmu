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

# === Configuration SlowDNS (DNS-AGN) ===
SLOWDNS_DIR="/etc/slowdns_v2ray"
SLOWDNS_BIN="/usr/local/bin/dns-server"
SLOWDNS_PORT=5400
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"

# Clés fixes SlowDNS
SLOWDNS_PRIVATE_KEY="4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa"
SLOWDNS_PUBLIC_KEY="2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c"

# Générer lien vmess au format base64 JSON
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

# ✅ AJOUTÉ: Fonction pour ajouter UUID dans V2Ray
ajouter_client_v2ray() {
    local uuid="$1"
    local nom="$2"
    
    if ! command -v jq >/dev/null 2>&1 || [[ ! -f /etc/v2ray/config.json ]]; then
        echo "⚠️  V2Ray non installé ou jq manquant"
        return 1
    fi
    
    jq --arg id "$uuid" --arg email "$nom" \
       '.inbounds[0].settings.clients += [{"id": $id, "alterId": 0, "level": 1, "email": $email}]' \
       /etc/v2ray/config.json | sudo tee /etc/v2ray/config.json >/dev/null
    
    sudo systemctl reload v2ray.service 2>/dev/null || sudo systemctl restart v2ray.service
    echo "✅ UUID $uuid ajouté à V2Ray (service rechargé)"
}

# Affiche le menu avec titre dans cadre
afficher_menu() {
    clear
    echo -e "${CYAN}╔═════════════════════════════════════════════════════╗${RESET}"
    echo -e "${YELLOW}║       V2RAY + SLOWDNS TUNNEL${RESET}"
    echo -e "${YELLOW}║--------------------------------------------------${RESET}"
}

# Affiche l'état du tunnel V2Ray WS
afficher_mode_v2ray_ws() {
    if systemctl is-active --quiet v2ray.service; then
        local v2ray_port=$(jq -r '.inbounds[0].port' /etc/v2ray/config.json 2>/dev/null || echo "5401")
        echo -e "${CYAN}Tunnel V2Ray actif:${RESET}"
        echo -e "  - V2Ray WS sur le port TCP ${GREEN}$v2ray_port${RESET}"
    fi
    if systemctl is-active --quiet slowdns_v2ray.service; then
        echo -e "${CYAN}Tunnel SlowDNS actif:${RESET}"
        echo -e "  - SlowDNS sur le port UDP ${GREEN}5400${RESET} → V2Ray 5401"
    fi
}

# Affiche les options du menu
show_menu() {
    echo -e "${YELLOW}║--------------------------------------------------${RESET}"
    echo -e "${YELLOW}║ 1) Installer tunnel V2Ray WS${RESET}"
    echo -e "${YELLOW}║ 2) Créer nouvel utilisateur${RESET}"
    echo -e "${YELLOW}║ 3) Supprimer un utilisateur${RESET}"
    echo -e "${YELLOW}║ 4) Désinstaller V2Ray + SlowDNS${RESET}"
    echo -e "${YELLOW}║ 5) Installer tunnel SlowDNS (DNSTT)${RESET}"
    echo -e "${RED}║ 0) Quitter${RESET}"
    echo -e "${CYAN}╚═════════════════════════════════════════════════════╝${RESET}"
    echo -n "Choisissez une option : "
}

# Générer UUID v4
generer_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# ✅ INSTALL V2RAY - AVEC VOTRE CONFIG PRÉCISE
installer_v2ray() {
    echo -e "${CYAN}=== Installation V2Ray WS (Port 5401) ===${RESET}"
    echo -n "Domaine/IP VPS : "; read domaine

    LOGFILE="/var/log/v2ray_install.log"
    sudo touch "$LOGFILE" && sudo chmod 640 "$LOGFILE"
    
    echo "📥 Téléchargement V2Ray... (logs: $LOGFILE)"

    # Dépendances + binaire (code robuste)
    sudo apt update && sudo apt install -y jq unzip netfilter-persistent 2>/dev/null || true
    set +e
    wget -q "https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip" -O /tmp/v2ray.zip 2>>"$LOGFILE"
    [[ $? -ne 0 ]] && { echo -e "${RED}❌ Échec téléchargement${RESET}"; return 1; }
    set -e
    unzip -o /tmp/v2ray.zip -d /tmp/v2ray >>"$LOGFILE" 2>&1 || { echo -e "${RED}❌ Échec décompression${RESET}"; return 1; }
    sudo mv /tmp/v2ray/v2ray /usr/local/bin/ && sudo chmod +x /usr/local/bin/v2ray || { echo -e "${RED}❌ Binaire manquant${RESET}"; return 1; }

    sudo mkdir -p /etc/v2ray
    echo "$domaine" | sudo tee /.v2ray_domain > /dev/null

    # ✅ VOTRE CONFIG EXACTE (copiée-collée)
    cat <<EOF | sudo tee /etc/v2ray/config.json > /dev/null
{
  "log": {
    "loglevel": "info"
  },
  "inbounds": [{
    "port": 5401,
    "protocol": "vmess",
    "settings": {
      "clients": [
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "alterId": 0,
          "level": 1,
          "email": "default@admin"
        }
      ]
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": {
        "path": "/vmess-ws"
      }
    },
    "sniffing": {
      "enabled": true,
      "destOverride": ["http", "tls"]
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {
      "domainStrategy": "UseIP"
    }
  }]
}
EOF

    # ✅ SERVICE SYSTEMD MODERNE
    sudo tee /etc/systemd/system/v2ray.service > /dev/null <<EOF
[Unit]
Description=V2Ray Service (WS 5401)
After=network.target
Wants=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/v2ray run -config /etc/v2ray/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    # 🚀 DÉMARRAGE + LOGS TEMPS RÉEL
    echo -e "${YELLOW}🔄 Démarrage V2Ray + LOGS TEMPS RÉEL...${RESET}"
    sudo iptables -I INPUT -p tcp --dport 5401 -j ACCEPT
    sudo netfilter-persistent save 2>/dev/null || true

    sudo systemctl daemon-reload
    sudo systemctl enable v2ray.service
    sudo systemctl restart v2ray.service &

    # LOGS TEMPS RÉEL 10s
    echo -e "${CYAN}📊 SUIVI LOGS V2Ray (10s)...${RESET}"
    timeout 10 sudo journalctl -u v2ray.service -f --no-pager | grep -E "(listener|transport|started|error)" || true

    # VÉRIFICATION FINALE
    sleep 2
    if systemctl is-active --quiet v2ray.service && ss -tuln | grep -q :5401; then
        echo -e "${GREEN}🎉 V2Ray 100% ACTIF !${RESET}"
        echo -e "${GREEN}✅ Service: $(systemctl is-active v2ray.service)${RESET}"
        echo -e "${GREEN}✅ Port: $(ss -tuln | grep :5401 | awk '{print $4" → "$5}')${RESET}"
        echo ""
        echo -e "${YELLOW}📱 CLIENT VMESS:${RESET}"
        echo -e "${GREEN}IP:${RESET} $domaine:5401"
        echo -e "${GREEN}UUID:${RESET} 00000000-0000-0000-0000-000000000001"
        echo -e "${GREEN}Path:${RESET} /vmess-ws"
        echo -e "${RED}⚠️ → TCP 5401 ALLOW !${RESET}"
    else
        echo -e "${RED}❌ V2Ray ÉCHEC !${RESET}"
        sudo journalctl -u v2ray.service -n 20 --no-pager
    fi

    read -p "Entrée pour continuer..."
}

# ✅ CORRIGÉ: Installer SlowDNS avec NAMESERVER fixe
installer_slowdns() {
    sudo mkdir -p "$SLOWDNS_DIR"

    echo "Téléchargement DNS-AGN..."
    sudo wget -q -O "$SLOWDNS_BIN" https://github.com/khaledagn/DNS-AGN/raw/main/dns-server
    sudo chmod +x "$SLOWDNS_BIN"

    echo "$SLOWDNS_PRIVATE_KEY" | sudo tee "$SERVER_KEY" > /dev/null
    echo "$SLOWDNS_PUBLIC_KEY"  | sudo tee "$SERVER_PUB" > /dev/null
    sudo chmod 600 "$SERVER_KEY"
    sudo chmod 644 "$SERVER_PUB"

    read -p "NameServer NS (ex: slowdns.pay.googleusercontent.kingdom.qzz.io) : " NAMESERVER
    echo "$NAMESERVER" | sudo tee "$CONFIG_FILE" > /dev/null

    # ✅ SCRIPT CORRIGÉ AVEC -forward 127.0.0.1:5401
    sudo tee /usr/local/bin/slowdns_v2ray-start.sh > /dev/null <<'EOF'
#!/bin/bash
SLOWDNS_DIR="/etc/slowdns_v2ray"
SLOWDNS_BIN="/usr/local/bin/dns-server"
PORT=5400
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
LOG="/var/log/slowdns_v2ray.log"

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

echo "[$(timestamp)] Démarrage SlowDNS → V2Ray..." | tee -a "$LOG"
NAMESERVER=$(cat "$CONFIG_FILE" 2>/dev/null || echo "8.8.8.8")
echo "[$(timestamp)] NS: $NAMESERVER" | tee -a "$LOG"

interface=$(ip -o link show up | awk -F': ' '{print $2}' | grep -E '^(eth|ens)' | head -1)
[ -z "$interface" ] && interface="eth0"
echo "[$(timestamp)] Interface: $interface" | tee -a "$LOG"

ip link set "$interface" mtu 1400 2>/dev/null && echo "[$(timestamp)] MTU OK" | tee -a "$LOG"

iptables -I INPUT -p udp --dport 5400 -j ACCEPT 2>/dev/null
iptables -I INPUT -p tcp --dport 5401 -j ACCEPT 2>/dev/null

echo "[$(timestamp)] Lancement: $SLOWDNS_BIN -udp :$PORT -forward 127.0.0.1:5401" | tee -a "$LOG"

# ✅ SYNTAXE CORRIGÉE AVEC -forward
exec "$SLOWDNS_BIN" -udp :$PORT -forward 127.0.0.1:5401 -privkey-file "$SERVER_KEY" "$NAMESERVER"
EOF

    sudo chmod +x /usr/local/bin/slowdns_v2ray-start.sh

    sudo tee /etc/systemd/system/slowdns_v2ray.service > /dev/null <<EOF
[Unit]
Description=SlowDNS → V2Ray (UDP 5400 → TCP 5401)
After=network-online.target v2ray.service
Wants=v2ray.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/slowdns_v2ray-start.sh
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
TimeoutStartSec=20

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl restart slowdns_v2ray.service
    sudo iptables -I INPUT -p udp --dport 5400 -j ACCEPT
    sudo netfilter-persistent save 2>/dev/null || true

    sleep 3
    echo "✅ SlowDNS + V2Ray COMBO ACTIF !"
    echo "UDP 5400 → TCP 5401 (V2Ray)"
    echo "NS: $NAMESERVER"
    echo "PubKey: $SLOWDNS_PUBLIC_KEY"
    ps aux | grep dns-server | grep 5400
}

# Gestion utilisateurs
charger_utilisateurs() {
    if [[ ! -f $USER_DB ]]; then
        echo "[]" > "$USER_DB"
    fi
    utilisateurs=$(cat "$USER_DB")
}

sauvegarder_utilisateurs() {
    echo "$utilisateurs" > "$USER_DB"
}

# ✅ CORRIGÉ: Création utilisateur avec UUID auto-ajouté
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

    if [[ -f /etc/v2ray/config.json ]] && command -v jq >/dev/null 2>&1; then
        ajouter_client_v2ray "$uuid" "$nom"
    else
        echo "⚠️  Installez d'abord V2Ray option 1"
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
    echo -e "${GREEN}=============================="
    echo -e "🧩 VMESS + SLOWDNS"
    echo -e "=============================="
    echo -e "📄 Configuration pour : ${YELLOW}$nom${RESET}"
    echo -e "--------------------------------------------------"
    echo -e "➤ DOMAINE : ${GREEN}$domaine${RESET}"
    echo -e "➤ PORTS :"
    echo -e "   SlowDNS UDP: ${GREEN}5400${RESET}"
    echo -e "   V2Ray TCP  : ${GREEN}$V2RAY_INTER_PORT${RESET}"
    echo -e "➤ UUID      : ${GREEN}$uuid${RESET}"
    echo -e "➤ Path      : /vmess-ws"
    echo -e "➤ Validité  : ${YELLOW}$duree${RESET} jours expire: $date_exp"
    echo ""
    echo -e "${CYAN}Clé publique SlowDNS:${RESET} $PUB_KEY"
    echo -e "${CYAN}NameServer:${RESET} $NAMESERVER"
    echo ""
    echo -e "${GREEN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●"
    echo ""
    echo -e "${YELLOW}┃ Lien VMess copiez-collez : $lien_vmess${RESET}"
    echo -e "${GREEN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●"
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
        echo "$((i+1)) $nom expire le $expire"
    done
    echo -n "Numéro à supprimer : "
    read choix
    if (( choix < 1 || choix > count )); then
        echo "Choix invalide."
        read -p "Appuyez sur Entrée pour continuer..."
        return
    fi
    index=$((choix - 1))
    utilisateurs=$(echo "$utilisateurs" | jq "del(.[${index}])")
    sauvegarder_utilisateurs
    echo "✅ Utilisateur supprimé."
    read -p "Appuyez sur Entrée pour continuer..."
}

desinstaller_v2ray() {
    echo -n "Êtes-vous sûr ? o/N : "
    read reponse
    if [[ "$reponse" =~ ^[Oo]$ ]]; then
        sudo systemctl stop v2ray.service slowdns_v2ray.service
        sudo systemctl disable v2ray.service slowdns_v2ray.service
        sudo rm -f /etc/systemd/system/v2ray.service /etc/systemd/system/slowdns_v2ray.service
        sudo pkill v2ray dns-server 2>/dev/null
        sudo rm -rf /usr/local/bin/v2ray /usr/local/bin/dns-server /etc/v2ray /etc/slowdns_v2ray /.v2ray_domain
        sudo systemctl daemon-reload
        sudo rm -f $USER_DB
        echo "✅ Tout désinstallé et nettoyé."
    else
        echo "Annulé."
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
        0) echo "Au revoir"; exit 0 ;;
        *) echo "Option invalide."
           sleep 1 
           ;;
    esac
done
