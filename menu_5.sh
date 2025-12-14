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
PORT=5400
CONFIG_FILE="$SLOWDNS_DIR/ns.conf"
SERVER_KEY="$SLOWDNS_DIR/server.key"
SERVER_PUB="$SLOWDNS_DIR/server.pub"

charger_utilisateurs() {
    if [[ -f "$USER_DB" && -s "$USER_DB" ]]; then
        utilisateurs=$(cat "$USER_DB")
    else
        utilisateurs="[]"
    fi
}

sauvegarder_utilisateurs() {
    echo "$utilisateurs" > "$USER_DB"
}

# Générer lien vmess au format base64 JSON
generer_lien_vmess() {
    local nom="$1"
    local domaine="$2"
    local port="$3"
    local uuid="$4"

    local json=$(cat <<EOF
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
  "tls": "none"
}
EOF
)

    # encodage base64 propre (sans retour à la ligne)
    echo -n "vmess://$(echo -n "$json" | base64 -w 0)"
}

# ✅ AJOUTÉ: Fonction pour ajouter UUID dans V2Ray
ajouter_client_v2ray() {
    local uuid="$1"
    local nom="$2"
    local config="/etc/v2ray/config.json"

    if [[ ! -f "$config" ]]; then
        echo "❌ Fichier V2Ray introuvable : $config"
        return 1
    fi

    # Vérification structure JSON
    if ! jq empty "$config" 2>/dev/null; then
        echo "❌ config.json est invalide — V2Ray ne peut pas démarrer."
        return 1
    fi

    # Ajout de l'utilisateur dans la liste des clients
    tmpfile=$(mktemp)

    jq --arg uuid "$uuid" --arg email "$nom" '
        (.inbounds[] | select(.protocol=="vmess").settings.clients) +=
        [{"id": $uuid, "alterId": 0, "email": $email}]
    ' "$config" > "$tmpfile"

    if jq empty "$tmpfile" 2>/dev/null; then
        mv "$tmpfile" "$config"
        systemctl restart v2ray
        echo "✅ Utilisateur ajouté dans V2Ray"
        return 0
    else
        echo "❌ Erreur lors de la modification de config.json"
        rm -f "$tmpfile"
        return 1
    fi
}

# Affiche le menu avec titre dans cadre
afficher_menu() {
    clear
    echo -e "${CYAN}╔═════════════════════════════════════════════════════╗${RESET}"
    echo -e "${YELLOW}║       V2RAY + SLOWDNS TUNNEL${RESET}"
    echo -e "${YELLOW}║--------------------------------------------------${RESET}"
}

afficher_mode_v2ray_ws() {
    if systemctl is-active --quiet v2ray.service; then
        local v2ray_port
        v2ray_port=$(jq -r '.inbounds[0].port' /etc/v2ray/config.json 2>/dev/null || echo "5401")
        echo -e "${CYAN}Tunnel V2Ray actif:${RESET}"
        echo -e "  - V2Ray WS sur le port TCP ${GREEN}$v2ray_port${RESET}"
    fi

    if systemctl is-active --quiet slowdns-v2ray.service; then
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
  "inbounds": [
    {
      "port": 5401,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1",
        "port": 22,
        "network": "tcp"
      },
      "tag": "ssh"
    },
    {
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
      },
      "tag": "v2ray"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIP"
      }
    }
  ]
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
    
# ✅ CORRIGÉ: Création utilisateur avec UUID auto-ajouté
creer_utilisateur() {
    echo -n "Entrez un nom d'utilisateur : "
    read nom
    echo -n "Durée de validité (en jours) : "
    read duree

    # Charger base utilisateurs (sécurisé)
    if [[ -f "$USER_DB" && -s "$USER_DB" ]]; then
        utilisateurs=$(cat "$USER_DB")
    else
        utilisateurs="[]"
    fi

    # Génération
    uuid=$(generer_uuid)
    date_exp=$(date -d "+${duree} days" +%Y-%m-%d)

    # Ajout sécurisé dans JSON
    utilisateurs=$(echo "$utilisateurs" | jq --arg n "$nom" --arg u "$uuid" --arg d "$date_exp" \
        '. += [{"nom": $n, "uuid": $u, "expire": $d}]')

    echo "$utilisateurs" > "$USER_DB"

    # Mise à jour V2Ray
    if [[ -f /etc/v2ray/config.json ]]; then
        if ! ajouter_client_v2ray "$uuid" "$nom"; then
            echo "❌ Erreur ajout utilisateur dans V2Ray"
        fi
    else
        echo "⚠️ V2Ray non installé – option 1 obligatoire"
    fi

    # Domaine
    if [[ -f /.v2ray_domain ]]; then
        domaine=$(cat /.v2ray_domain)
    else
        domaine="votre-domaine.com"
    fi

    # Ports
    local V2RAY_INTER_PORT="5401"

    # Clé publique SlowDNS
    if [[ -f "$SLOWDNS_DIR/server.pub" ]]; then
        PUB_KEY=$(cat "$SLOWDNS_DIR/server.pub")
    else
        PUB_KEY="clé_non_disponible"
    fi

    # NS
    if [[ -f /etc/slowdns_v2ray/ns.conf ]]; then
        NAMESERVER=$(cat /etc/slowdns_v2ray/ns.conf)
    else
        NAMESERVER="NS_non_defini"
    fi

    lien_vmess=$(generer_lien_vmess "$nom" "$domaine" "$V2RAY_INTER_PORT" "$uuid")

    clear
    echo -e "${GREEN}=============================="
    echo -e "🧩 VMESS + SLOWDNS"
    echo -e "=============================="
    echo -e "📄 Utilisateur : ${YELLOW}$nom${RESET}"
    echo -e "➤ DÉLAI : ${YELLOW}$duree${RESET} jours (expire : $date_exp)"
    echo -e "➤ UUID : ${GREEN}$uuid${RESET}"
    echo -e "➤ Domaine : ${GREEN}$domaine${RESET}"
    echo -e "➤ SlowDNS : UDP 5400"
    echo -e "➤ V2Ray interne : ${GREEN}$V2RAY_INTER_PORT${RESET}"
    echo ""
    echo -e "Clé publique : $PUB_KEY"
    echo -e "NS : $NAMESERVER"
    echo ""
    echo -e "${YELLOW}Lien VMess :${RESET}"
    echo "$lien_vmess"
    echo ""
    read -p "Appuyez sur Entrée..."
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
        echo -e "${YELLOW}🛑 Arrêt des services...${RESET}"
        
        sudo systemctl stop v2ray.service 2>/dev/null || true
        sudo systemctl disable v2ray.service 2>/dev/null || true
        sudo rm -f /etc/systemd/system/v2ray.service

        sudo systemctl stop slowdns-v2ray.service 2>/dev/null || true
        sudo systemctl disable slowdns-v2ray.service 2>/dev/null || true
        
        SLOWDNS_PID=$(sudo systemctl show slowdns-v2ray.service --property=MainPID --value 2>/dev/null || echo "")
        [ -n "$SLOWDNS_PID" ] && sudo kill $SLOWDNS_PID 2>/dev/null || true

        if screen -list | grep -q "slowdns_v2ray"; then
            screen -S slowdns_v2ray -X quit 2>/dev/null || true
        fi

        sudo iptables -D INPUT -p tcp --dport 5401 -j ACCEPT 2>/dev/null || true
        sudo iptables -D INPUT -p udp --dport 5400 -j ACCEPT 2>/dev/null || true
        sudo netfilter-persistent save 2>/dev/null || true

        sudo rm -rf /etc/slowdns_v2ray 
        sudo rm -f /usr/local/bin/slowdns-v2ray-start.sh
        sudo rm -f /var/log/slowdns_v2ray.log
        sudo rm -rf /.v2ray_domain
        sudo rm -rf /etc/v2ray 
        [ -f "$USER_DB" ] && sudo rm -f "$USER_DB"

        sudo systemctl daemon-reload
        sudo rm -f /etc/systemd/system/slowdns-v2ray.service

        echo -e "${GREEN}✅ V2Ray + SlowDNS V2Ray désinstallé.${RESET}"
        echo -e "${GREEN}✅ Tunnel SSH SlowDNS préservé !${RESET}"
        echo -e "${CYAN}📊 Vérification ports fermés:${RESET}"
        ss -tuln | grep -E "(:5400|:5401)" || echo "✅ Ports 5400/5401 libres"
        echo -e "${GREEN}✅ SSH SlowDNS toujours actif: $(systemctl is-active slowdns.service 2>/dev/null || echo "non installé")${RESET}"
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
        0) echo "Au revoir"; exit 0 ;;
        *) echo "Option invalide."
           sleep 1 
           ;;
    esac
done
