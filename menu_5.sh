#!/bin/bash

# Fichier stockage utilisateurs (V2Ray)
USER_DB="/etc/v2ray/utilisateurs.json"

mkdir -p /etc/v2ray
touch "$USER_DB"
chmod 600 "$USER_DB"

# Initialiser JSON si corrompu ou vide
if ! jq empty "$USER_DB" >/dev/null 2>&1; then
    echo "[]" > "$USER_DB"
fi

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

# Générer lien vless au format adapter
generer_liens_v2ray() {
    local nom="$1"
    local domaine="$2"
    local port="$3"
    local uuid="$4"

    # VLESS
    lien_vless="vless://${uuid}@${domaine}:${port}?type=kcp&encryption=none&headerType=none&host=${domaine}#${nom}-VLESS"

    # VMESS (Base64 JSON)
    local vmess_json
    vmess_json=$(jq -nc \
        --arg v "2" \
        --arg ps "${nom}-VMESS" \
        --arg add "$domaine" \
        --arg port "$port" \
        --arg id "$uuid" \
        --arg aid "0" \
        --arg net "kcp" \
        --arg type "none" \
        --arg host "$domaine" \
        '{
            v: $v,
            ps: $ps,
            add: $add,
            port: $port,
            id: $id,
            aid: $aid,
            net: $net,
            type: $type,
            host: $host,
            tls: ""
        }'
    )
    lien_vmess="vmess://$(echo -n "$vmess_json" | base64 -w 0)"

    # TROJAN (UUID comme password)
    lien_trojan="trojan://${uuid}@${domaine}:${port}?type=kcp&headerType=none&host=${domaine}#${nom}-TROJAN"
}

# ✅ AJOUTÉ: Fonction pour ajouter UUID dans V2Ray
ajouter_client_v2ray() {
    local uuid="$1"
    local nom="$2"
    local config="/etc/v2ray/config.json"

    [[ ! -f "$config" ]] && { echo "❌ config.json introuvable"; return 1; }

    # Vérification JSON avant
    if ! jq empty "$config" >/dev/null 2>&1; then
        echo "❌ config.json invalide AVANT modification"
        return 1
    fi

    # Vérifier doublon (VLESS suffit car UUID commun)
    if jq -e --arg uuid "$uuid" '
        .inbounds[] 
        | select(.protocol=="vless") 
        | .settings.clients[]? 
        | select(.id==$uuid)
    ' "$config" >/dev/null; then
        echo "⚠️ UUID déjà existant"
        return 0
    fi

    tmpfile=$(mktemp)

    # Ajout VLESS + VMESS + TROJAN
    jq --arg uuid "$uuid" --arg email "$nom" '
    .inbounds |= map(
        if .protocol=="vless" then
            .settings.clients += [{"id": $uuid, "email": $email}]
        elif .protocol=="vmess" then
            .settings.clients += [{"id": $uuid, "alterId": 0, "email": $email}]
        elif .protocol=="trojan" then
            .settings.clients += [{"password": $uuid, "email": $email}]
        else .
        end
    )
    ' "$config" > "$tmpfile"

    # Vérification JSON après
    if ! jq empty "$tmpfile" >/dev/null 2>&1; then
        echo "❌ JSON cassé APRÈS modification"
        rm -f "$tmpfile"
        return 1
    fi

    mv "$tmpfile" "$config"

    # Test V2Ray
    if ! /usr/local/bin/v2ray test -config "$config" >/dev/null 2>&1; then
        echo "❌ V2Ray refuse la configuration"
        return 1
    fi

    systemctl restart v2ray

    if systemctl is-active --quiet v2ray; then
        echo "✅ Utilisateur ajouté (VLESS + VMESS + TROJAN)"
        return 0
    else
        echo "❌ V2Ray n’a pas redémarré"
        return 1
    fi
}

# Affiche le menu avec titre dans cadre
afficher_menu() {
    clear
    echo -e "${CYAN}╔═════════════════════════════════════════════════════╗${RESET}"
    echo -e "${YELLOW}║       V2RAY + FASTDNS TUNNEL${RESET}"
    echo -e "${YELLOW}║--------------------------------------------------${RESET}"
}

afficher_mode_v2ray_ws() {
    # 🔹 Statut du tunnel V2Ray
    if systemctl is-active --quiet v2ray.service; then
        local v2ray_port
        v2ray_port=$(jq -r '.inbounds[0].port' /etc/v2ray/config.json 2>/dev/null || echo "5401")
        echo -e "${CYAN}Tunnel V2Ray actif:${RESET}"
        echo -e "  - V2Ray WS sur le port TCP ${GREEN}$v2ray_port${RESET}"
    else
        echo -e "${RED}Tunnel V2Ray inactif${RESET}"
    fi

    # 🔹 Statut du tunnel SlowDNS
    if systemctl is-active --quiet slowdns.service; then
        echo -e "${CYAN}Tunnel FastDNS actif:${RESET}"
        echo -e "  - FastDNS sur le port UDP ${GREEN}5400${RESET} → V2Ray 5401"
    else
        echo -e "${RED}Tunnel FastDNS inactif${RESET}"
    fi

    # 🔹 Nombre total d'utilisateurs créés
    if [[ -f "$USER_DB" && -s "$USER_DB" ]]; then
        nb_utilisateurs=$(jq length "$USER_DB" 2>/dev/null)
        nb_utilisateurs=${nb_utilisateurs:-0}
    else
        nb_utilisateurs=0
    fi
    echo -e "${CYAN}Nombre total d'utilisateurs créés : ${GREEN}$nb_utilisateurs${RESET}"
}

# Affiche les options du menu
show_menu() {
    echo -e "${YELLOW}║--------------------------------------------------${RESET}"
    echo -e "${YELLOW}║ 1) Installer tunnel V2Ray WS${RESET}"
    echo -e "${YELLOW}║ 2) Créer nouvel utilisateur${RESET}"
    echo -e "${YELLOW}║ 3) Supprimer un utilisateur${RESET}"
    echo -e "${YELLOW}║ 4) Désinstaller V2Ray+FastDNS${RESET}"
    echo -e "${YELLOW}║ 5) Mode MIX (SSH + V2Ray)${RESET}"
    echo -e "${YELLOW}║ 6) Mode V2RAY ONLY${RESET}"
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

        # ✅ CONFIG V2RAY ONLY (SANS SSH)
    cat <<EOF | sudo tee /etc/v2ray/config-v2only.json > /dev/null
{
  "log": {
    "loglevel": "info"
  },
  "inbounds": [
    {
      "port": 5401,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "00000000-0000-0000-0000-000000000001",
            "email": "default@admin"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "kcp",
        "kcpSettings": {
          "mtu": 1350,
          "tti": 50,
          "uplinkCapacity": 5,
          "downlinkCapacity": 20,
          "congestion": false,
          "readBufferSize": 2,
          "writeBufferSize": 2,
          "header": {
            "type": "none"
          }
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "vless"
    },
    {
      "port": 5401,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "00000000-0000-0000-0000-000000000001",
            "alterId": 0,
            "email": "default@admin"
          }
        ]
      },
      "streamSettings": {
        "network": "kcp",
        "kcpSettings": {
          "mtu": 1350,
          "tti": 50,
          "uplinkCapacity": 5,
          "downlinkCapacity": 20,
          "congestion": false,
          "readBufferSize": 2,
          "writeBufferSize": 2,
          "header": {
            "type": "none"
          }
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "vmess"
    },
    {
      "port": 5401,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "00000000-0000-0000-0000-000000000001",
            "email": "default@admin"
          }
        ]
      },
      "streamSettings": {
        "network": "kcp",
        "kcpSettings": {
          "mtu": 1350,
          "tti": 50,
          "uplinkCapacity": 5,
          "downlinkCapacity": 20,
          "congestion": false,
          "readBufferSize": 2,
          "writeBufferSize": 2,
          "header": {
            "type": "none"
          }
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "trojan"
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

    # ✅ CONFIG MIX (AVEC SSH dokodemo-door)
    cat <<EOF | sudo tee /etc/v2ray/config-mix.json > /dev/null
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
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "00000000-0000-0000-0000-000000000001",
            "email": "default@admin"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "kcp",
        "kcpSettings": {
          "mtu": 1350,
          "tti": 50,
          "uplinkCapacity": 5,
          "downlinkCapacity": 20,
          "congestion": false,
          "readBufferSize": 2,
          "writeBufferSize": 2,
          "header": {
            "type": "none"
          }
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "vless"
    },
    {
      "port": 5401,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "00000000-0000-0000-0000-000000000001",
            "alterId": 0,
            "email": "default@admin"
          }
        ]
      },
      "streamSettings": {
        "network": "kcp",
        "kcpSettings": {
          "mtu": 1350,
          "tti": 50,
          "uplinkCapacity": 5,
          "downlinkCapacity": 20,
          "congestion": false,
          "readBufferSize": 2,
          "writeBufferSize": 2,
          "header": {
            "type": "none"
          }
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "vmess"
    },
    {
      "port": 5401,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "00000000-0000-0000-0000-000000000001",
            "email": "default@admin"
          }
        ]
      },
      "streamSettings": {
        "network": "kcp",
        "kcpSettings": {
          "mtu": 1350,
          "tti": 50,
          "uplinkCapacity": 5,
          "downlinkCapacity": 20,
          "congestion": false,
          "readBufferSize": 2,
          "writeBufferSize": 2,
          "header": {
            "type": "none"
          }
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "trojan"
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

    # ✅ PAR DÉFAUT : V2RAY ONLY
    sudo cp /etc/v2ray/config-v2only.json /etc/v2ray/config.json

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
    echo -e "${CYAN}📊 SUIVI LOGS V2Ray (5s)...${RESET}"
    timeout 5 sudo journalctl -u v2ray.service -f --no-pager | grep -E "(listener|transport|started|error)" || true

    # VÉRIFICATION FINALE
    sleep 2
    if systemctl is-active --quiet v2ray.service && ss -tuln | grep -q :5401; then
        echo -e "${GREEN}🎉 V2Ray 100% ACTIF !${RESET}"
        echo -e "${GREEN}✅ Service: $(systemctl is-active v2ray.service)${RESET}"
        echo -e "${GREEN}✅ Port: $(ss -tuln | grep :5401 | awk '{print $4" → "$5}')${RESET}"
        echo ""
        echo -e "${YELLOW}📱 CLIENT VLESS, VMESS, TROJAN :${RESET}"
        echo -e "${GREEN}IP:${RESET} $domaine:5401"
        echo -e "${GREEN}UUID:${RESET} 00000000-0000-0000-0000-000000000001"
        echo -e "${GREEN}Path:${RESET} /vless-ws | /vmess-ws | /trojan-ws"
        echo -e "${RED}⚠️ → TCP 5401 ALLOW !${RESET}"
    else
        echo -e "${RED}❌ V2Ray ÉCHEC !${RESET}"
        sudo journalctl -u v2ray.service -n 20 --no-pager
    fi

    read -p "Entrée pour continuer..."
}

basculer_mode_mix() {
    if [[ ! -f /etc/v2ray/config-mix.json ]]; then
        echo "❌ config-mix.json introuvable (réinstalle V2Ray)."
        read -p "Entrée pour continuer..."
        return
    fi

    sudo cp /etc/v2ray/config-mix.json /etc/v2ray/config.json

    if ! /usr/local/bin/v2ray test -config /etc/v2ray/config.json >/dev/null 2>&1; then
        echo "❌ V2Ray refuse la config MIX"
        read -p "Entrée pour continuer..."
        return
    fi

    sudo systemctl restart v2ray
    if systemctl is-active --quiet v2ray; then
        echo "✅ Mode MIX activé (SSH + V2Ray sur 5401)"
    else
        echo "❌ V2Ray n’a pas démarré en mode MIX"
    fi
    read -p "Entrée pour continuer..."
}

basculer_mode_v2only() {
    if [[ ! -f /etc/v2ray/config-v2only.json ]]; then
        echo "❌ config-v2only.json introuvable (réinstalle V2Ray)."
        read -p "Entrée pour continuer..."
        return
    fi

    sudo cp /etc/v2ray/config-v2only.json /etc/v2ray/config.json

    if ! /usr/local/bin/v2ray test -config /etc/v2ray/config.json >/dev/null 2>&1; then
        echo "❌ V2Ray refuse la config V2ONLY"
        read -p "Entrée pour continuer..."
        return
    fi

    sudo systemctl restart v2ray
    if systemctl is-active --quiet v2ray; then
        echo "✅ Mode V2RAY ONLY activé (sans SSH sur 5401)"
    else
        echo "❌ V2Ray n’a pas démarré en mode V2ONLY"
    fi
    read -p "Entrée pour continuer..."
}
    
# ✅ CORRIGÉ: Création utilisateur avec UUID auto-ajouté
creer_utilisateur() {
    local nom duree uuid date_exp domaine
    echo -n "Entrez un nom d'utilisateur : "
    read nom
    echo -n "Durée de validité (en jours) : "
    read duree

    # Charger base utilisateurs
    charger_utilisateurs

    # Génération UUID et date d'expiration
    uuid=$(generer_uuid)
    date_exp=$(date -d "+${duree} days" +%Y-%m-%d)

    # Sauvegarde utilisateur (UUID UNIQUE) en sécurité
    utilisateurs=$(echo "$utilisateurs" | jq --arg n "$nom" --arg u "$uuid" --arg d "$date_exp" \
        '. += [{"nom": $n, "uuid": $u, "expire": $d}]')

    local tmpfile=$(mktemp)          # créer fichier temporaire
    echo "$utilisateurs" > "$tmpfile"
    mv "$tmpfile" "$USER_DB"         # déplacer temp → utilisateur.json
    chmod 600 "$USER_DB"             # sécuriser

    # Ajout VLESS + VMESS + TROJAN (UUID = password)
    if [[ -f /etc/v2ray/config.json ]]; then
        if ! ajouter_client_v2ray "$uuid" "$nom"; then
            echo "❌ Erreur ajout utilisateur dans V2Ray"
            read -p "Entrée pour continuer..."
            return
        fi
    else
        echo "⚠️ V2Ray non installé – option 1 obligatoire"
        read -p "Entrée pour continuer..."
        return
    fi

    # Domaine
    if [[ -f /.v2ray_domain ]]; then
        domaine=$(cat /.v2ray_domain)
    else
        domaine="votre-domaine.com"
    fi

    local V2RAY_INTER_PORT="5401"
    local FASTDNS_PORT="${PORT:-5400}"

    # 🔹 FastDNS / SlowDNS
    SLOWDNS_DIR="/etc/slowdns"
    if [[ -f "$SLOWDNS_DIR/slowdns.env" ]]; then
        source "$SLOWDNS_DIR/slowdns.env"
    fi

    local PUB_KEY=${PUB_KEY:-$( [[ -f "$SLOWDNS_DIR/server.pub" ]] && cat "$SLOWDNS_DIR/server.pub" || echo "clé_non_disponible" )}
    local NAMESERVER=${NS:-$( [[ -f "$SLOWDNS_DIR/ns.conf" ]] && cat "$SLOWDNS_DIR/ns.conf" || echo "NS_non_defini" )}

    # Génération DES 3 LIENS (UUID UNIQUE)
    generer_liens_v2ray "$nom" "$domaine" "$V2RAY_INTER_PORT" "$uuid"

    # AFFICHAGE
    clear
    echo -e "${GREEN}============================================"
    echo -e "🧩 VLESS / VMESS / TROJAN + FASTDNS"
    echo -e "===================================================="
    echo -e "📄 Configuration pour : ${YELLOW}$nom${RESET}"
    echo -e "-------------------------------------------------------------"
    echo -e "➤ DOMAINE : ${GREEN}$domaine${RESET}"
    echo -e "➤ PORTS :"
    echo -e "   FastDNS UDP: ${GREEN}$FASTDNS_PORT${RESET}"
    echo -e "   V2Ray TCP  : ${GREEN}$V2RAY_INTER_PORT${RESET}"
    echo -e "➤ UUID / Password : ${GREEN}$uuid${RESET}"
    echo -e "➤ Paths : /vless-ws | /vmess-ws | /trojan-ws"
    echo -e "➤ Validité : ${YELLOW}$duree${RESET} jours (expire: $date_exp)"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━  CONFIGS SLOWDNS PORT 5400 ━━━━━━━━━━━━━●"
    echo -e "${CYAN}Clé publique FastDNS:${RESET}"
    echo -e "$PUB_KEY"
    echo -e "${CYAN}NameServer:${RESET} $NAMESERVER"
    echo ""
    echo -e "${GREEN}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●"
    echo -e "${YELLOW}┃ Lien VLESS  : $lien_vless${RESET}"
    echo -e "${YELLOW}┃${RESET}"
    echo -e "${YELLOW}┃ Lien VMESS  : $lien_vmess${RESET}"
    echo -e "${YELLOW}┃${RESET}"
    echo -e "${YELLOW}┃ Lien TROJAN : $lien_trojan${RESET}"
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
        uuid=$(echo "$utilisateurs" | jq -r ".[$i].uuid")
        echo "$((i+1))) $nom | expire le $expire | UUID: $uuid"
    done

    echo -n "Numéro à supprimer : "
    read choix

    if (( choix < 1 || choix > count )); then
        echo "Choix invalide."
        read -p "Appuyez sur Entrée pour continuer..."
        return
    fi

    index=$((choix - 1))
    uuid_supprime=$(echo "$utilisateurs" | jq -r ".[$index].uuid")
    nom_supprime=$(echo "$utilisateurs" | jq -r ".[$index].nom")

    # 🔴 Suppression dans la base utilisateurs
    utilisateurs=$(echo "$utilisateurs" | jq "del(.[${index}])")
    sauvegarder_utilisateurs

    # 🔴 Suppression dans V2Ray (VLESS + VMESS + TROJAN)
    if [[ -f /etc/v2ray/config.json ]]; then
        tmpfile=$(mktemp)

        jq --arg uuid "$uuid_supprime" '
        .inbounds |= map(
            if .protocol=="vless" then
                .settings.clients |= map(select(.id != $uuid))
            elif .protocol=="vmess" then
                .settings.clients |= map(select(.id != $uuid))
            elif .protocol=="trojan" then
                .settings.clients |= map(select(.password != $uuid))
            else .
            end
        )
        ' /etc/v2ray/config.json > "$tmpfile"

        if jq empty "$tmpfile" >/dev/null 2>&1; then
            mv "$tmpfile" /etc/v2ray/config.json
            systemctl restart v2ray
            echo "✅ Utilisateur supprimé de V2Ray (VLESS / VMESS / TROJAN)"
        else
            echo "❌ Erreur JSON après suppression V2Ray"
            rm -f "$tmpfile"
        fi
    fi

    echo "✅ Utilisateur « $nom_supprime » supprimé complètement."
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

        echo -e "${GREEN}✅ V2Ray + FastDNS V2Ray désinstallé.${RESET}"
        echo -e "${GREEN}✅ Tunnel SSH FastDNS préservé !${RESET}"
        echo -e "${CYAN}📊 Vérification ports fermés:${RESET}"
        ss -tuln | grep -E "(:5400|:5401)" || echo "✅ Ports 5400/5401 libres"
        echo -e "${GREEN}✅ SSH FastDNS toujours actif: $(systemctl is-active slowdns.service 2>/dev/null || echo "non installé")${RESET}"
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
        5) basculer_mode_mix ;;
        6) basculer_mode_v2only ;;
        0) echo "Au revoir"; exit 0 ;;
        *) echo "Option invalide."
           sleep 1 
           ;;
    esac
done
