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
    # Vérification du service V2Ray
    if systemctl is-active --quiet v2ray.service; then
        local v2ray_port
        v2ray_port=$(jq -r '.inbounds[0].port' /etc/v2ray/config.json 2>/dev/null || echo "5401")
        echo -e "${CYAN}Tunnel V2Ray actif:${RESET}"
        echo -e "  - V2Ray WS sur le port TCP ${GREEN}$v2ray_port${RESET}"
    fi

    # Vérification du tunnel SlowDNS via screen
    if screen -list | grep -q "slowdns_v2ray"; then
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
    SLOWDNS_DIR="/etc/slowdns_v2ray"
    SLOWDNS_BIN="/usr/local/bin/dns-server"
    SERVER_KEY="$SLOWDNS_DIR/server.key"
    SERVER_PUB="$SLOWDNS_DIR/server.pub"
    PORT=5400
    V2RAY_PORT=5401
    CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
    LOG_FILE="/var/log/slowdns_v2ray.log"

    sudo mkdir -p "$SLOWDNS_DIR" /var/log
    sudo touch "$LOG_FILE" && sudo chmod 644 "$LOG_FILE"

    echo "📥 Téléchargement du binaire dns-server..."
    sudo wget -q -O "$SLOWDNS_BIN" "https://raw.githubusercontent.com/sbatrow/DARKSSH-MANAGER/main/Modulos/dns-server"
    sudo chmod +x "$SLOWDNS_BIN"

    # Générer la paire de clés si elle n'existe pas
    if [ ! -f "$SERVER_KEY" ] || [ ! -f "$SERVER_PUB" ]; then
        echo "🔑 Génération des clés SlowDNS..."
        $SLOWDNS_BIN -gen-key -privkey-file "$SERVER_KEY" -pubkey-file "$SERVER_PUB" >>"$LOG_FILE" 2>&1
        sudo chmod 600 "$SERVER_KEY"
        sudo chmod 644 "$SERVER_PUB"
    fi

    read -p "NameServer NS (ex: slowdns.pay.googleusercontent.kingdom.qzz.io) : " NAMESERVER
    echo "$NAMESERVER" | sudo tee "$CONFIG_FILE" >/dev/null

    # Arrêter session existante
    if screen -list | grep -q "slowdns_v2ray"; then
        echo "❗ Une session SlowDNS existante est active. Arrêt..."
        screen -S slowdns_v2ray -X quit
        sleep 1
    fi

    echo "🚀 Lancement SlowDNS → V2Ray sur UDP $PORT"
    screen -dmS slowdns_v2ray bash -c "
        echo '[INFO] SlowDNS démarrage...' >> $LOG_FILE
        exec $SLOWDNS_BIN -udp :$PORT -privkey-file $SERVER_KEY $NAMESERVER 0.0.0.0:$V2RAY_PORT >>$LOG_FILE 2>&1
    "

    echo "⏳ Vérification du tunnel et affichage des logs récents (10s)..."
    sleep 2
    timeout 10 tail -f "$LOG_FILE"

    # Vérification des ports
    if ss -ulnp | grep -q ":$PORT" && ss -tlnp | grep -q ":$V2RAY_PORT"; then
        echo -e "\n🎉 SLOWDNS + V2RAY actif !"
        echo "NS: $NAMESERVER"
        echo "PubKey: $(cat "$SERVER_PUB")"
        echo "SlowDNS UDP: $PORT → V2Ray TCP: $V2RAY_PORT"
        echo "Pour arrêter le tunnel: screen -S slowdns_v2ray -X quit"
    else
        echo -e "\n❌ ÉCHEC ! Vérifiez le log complet : $LOG_FILE"
    fi

    read -p "Appuyez sur Entrée pour continuer..."
}
    
# ✅ CORRIGÉ: Création utilisateur avec UUID auto-ajouté
creer_utilisateur() {
    echo -n "Entrez un nom d'utilisateur : "
    read nom
    echo -n "Durée de validité (en jours) : "
    read duree

    uuid=$(generer_uuid)
    date_exp=$(date -d "+${duree} days" +%Y-%m-%d)
    utilisateurs=$(echo "$utilisateurs" | jq --arg n "$nom" --arg u "$uuid" --arg d "$date_exp" '. += [{"nom": $n, "uuid": $u, "expire": $d}]')

    # ✅ sauvegarde directement
    echo "$utilisateurs" > "$USER_DB"

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
        sudo systemctl stop v2ray.service
        sudo systemctl disable v2ray.service
        sudo rm -f /etc/systemd/system/v2ray.service

        if screen -list | grep -q "slowdns_v2ray"; then
            screen -S slowdns_v2ray -X quit
        fi

        sudo pkill v2ray dns-server 2>/dev/null
        sudo rm -rf /usr/local/bin/v2ray /usr/local/bin/dns-server /etc/v2ray /etc/DARKssh/dns /.v2ray_domain
        sudo systemctl daemon-reload
        [ -f "$USER_DB" ] && sudo rm -f "$USER_DB"

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
