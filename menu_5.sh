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

    lien_vless="vless://${uuid}@${domaine}:${port}?type=tcp&encryption=none&host=${domaine}#${nom}-VLESS-TCP"
}

# ✅ AJOUTÉ: Fonction pour ajouter UUID dans V2Ray
ajouter_client_v2ray() {
    local uuid="$1"
    local nom="$2"
    local config="/etc/v2ray/config.json"

    [[ ! -f "$config" ]] && { echo "❌ config.json introuvable"; return 1; }

    # Vérification JSON AVANT
    if ! jq empty "$config" >/dev/null 2>&1; then
        echo "❌ config.json invalide AVANT modification"
        return 1
    fi

    # Vérifier doublon UUID (VLESS uniquement)
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

    # Ajout UNIQUEMENT dans VLESS
    jq --arg uuid "$uuid" --arg email "$nom" '
    .inbounds |= map(
        if .protocol=="vless" then
            .settings.clients += [{"id": $uuid, "email": $email}]
        else .
        end
    )
    ' "$config" > "$tmpfile"

    # Vérification JSON APRÈS
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
        echo "✅ Utilisateur ajouté (VLESS TCP)"
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
        echo -e "  - V2Ray TCP sur le port TCP ${GREEN}$v2ray_port${RESET}"
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
    echo -e "${YELLOW}║ 7) Bot telegram${RESET}"
    echo -e "${RED}║ 0) Quitter${RESET}"
    echo -e "${CYAN}╚═════════════════════════════════════════════════════╝${RESET}"
    echo -n "Choisissez une option : "
}

# Générer UUID v4
generer_uuid() {
    cat /proc/sys/kernel/random/uuid
}

basculer_mode_mix() {
    local config_src="/etc/v2ray/config-mix.json"
    local config_dst="/etc/v2ray/config.json"

    if [[ ! -f "$config_src" ]]; then
        echo "❌ $config_src introuvable. Réinstallez V2Ray."
        read -p "Appuyez sur Entrée pour continuer..."
        return 1
    fi

    echo "🔄 Test de la config MIX..."
    if ! /usr/local/bin/v2ray test -config "$config_src" >/dev/null 2>&1; then
        echo "❌ Config MIX invalide. Abandon."
        read -p "Appuyez sur Entrée pour continuer..."
        return 1
    fi

    sudo cp "$config_src" "$config_dst"
    sudo systemctl restart v2ray

    if systemctl is-active --quiet v2ray; then
        echo "✅ Mode MIX activé (SSH + V2Ray sur 5401)"
    else
        echo "❌ V2Ray n’a pas démarré en mode MIX"
    fi
    read -p "Appuyez sur Entrée pour continuer..."
}

basculer_mode_v2only() {
    local config_src="/etc/v2ray/config-v2only.json"
    local config_dst="/etc/v2ray/config.json"

    if [[ ! -f "$config_src" ]]; then
        echo "❌ $config_src introuvable. Réinstallez V2Ray."
        read -p "Appuyez sur Entrée pour continuer..."
        return 1
    fi

    echo "🔄 Test de la config V2ONLY..."
    if ! /usr/local/bin/v2ray test -config "$config_src" >/dev/null 2>&1; then
        echo "❌ Config V2ONLY invalide. Abandon."
        read -p "Appuyez sur Entrée pour continuer..."
        return 1
    fi

    sudo cp "$config_src" "$config_dst"
    sudo systemctl restart v2ray

    if systemctl is-active --quiet v2ray; then
        echo "✅ Mode V2RAY ONLY activé (sans SSH sur 5401)"
    else
        echo "❌ V2Ray n’a pas démarré en mode V2ONLY"
    fi
    read -p "Appuyez sur Entrée pour continuer..."
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
    echo -e "🧩 VLESS TCP + FASTDNS"
    echo -e "===================================================="
    echo -e "📄 Configuration pour : ${YELLOW}$nom${RESET}"
    echo -e "-------------------------------------------------------------"
    echo -e "➤ DOMAINE : ${GREEN}$domaine${RESET}"
    echo -e "➤ PORTS :"
    echo -e "   FastDNS UDP: ${GREEN}$FASTDNS_PORT${RESET}"
    echo -e "   V2Ray TCP  : ${GREEN}$V2RAY_INTER_PORT${RESET}"
    echo -e "➤ UUID / Password : ${GREEN}$uuid${RESET}"
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

    # 🔴 Suppression dans V2Ray (VLESS uniquement)
    if [[ -f /etc/v2ray/config.json ]]; then
        tmpfile=$(mktemp)

        jq --arg uuid "$uuid_supprime" '
        .inbounds |= map(
            if .protocol=="vless" then
                .settings.clients |= map(select(.id != $uuid))
            else .
            end
        )
        ' /etc/v2ray/config.json > "$tmpfile"

        if jq empty "$tmpfile" >/dev/null 2>&1; then
            mv "$tmpfile" /etc/v2ray/config.json
            systemctl restart v2ray
            echo "✅ Utilisateur supprimé de V2Ray (VLESS TCP)"
        else
            echo "❌ Erreur JSON après suppression V2Ray"
            rm -f "$tmpfile"
        fi
    fi

    echo "✅ Utilisateur « $nom_supprime » supprimé complètement."
    read -p "Appuyez sur Entrée pour continuer..."
}

desinstaller_v2ray() {
    echo -n "Êtes-vous sûr de désinstaller uniquement V2Ray ? o/N : "
    read reponse
    if [[ "$reponse" =~ ^[Oo]$ ]]; then
        echo -e "${YELLOW}🛑 Arrêt du service V2Ray...${RESET}"

        # Stop et disable du service V2Ray
        systemctl stop v2ray.service 2>/dev/null || true
        systemctl disable v2ray.service 2>/dev/null || true
        rm -f /etc/systemd/system/v2ray.service 2>/dev/null

        # Supprimer les fichiers V2Ray
        rm -rf /etc/v2ray 2>/dev/null
        rm -f /usr/local/bin/v2ray 2>/dev/null
        rm -f /usr/local/bin/v2ctl 2>/dev/null
        rm -f /var/log/v2ray.log 2>/dev/null
        [ -f "$USER_DB" ] && rm -f "$USER_DB"

        # Nettoyer iptables V2Ray (port 5401 TCP)
        iptables -D INPUT -p tcp --dport 5401 -j ACCEPT 2>/dev/null || true
        netfilter-persistent save 2>/dev/null || true

        # Recharger systemd
        systemctl daemon-reload

        echo -e "${GREEN}✅ V2Ray désinstallé et nettoyé.${RESET}"
        echo -e "${CYAN}📊 Vérification ports :${RESET}"
        ss -tuln | grep -E "(:5401)" || echo "✅ Port 5401 libre"
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
        1) bash "$HOME/Kighmu/install_v2ray.sh" ;;
        2) creer_utilisateur ;;
        3) supprimer_utilisateur ;;
        4) desinstaller_v2ray ;;
        5) basculer_mode_mix ;;
        6) basculer_mode_v2only ;;
        7) go run "$SCRIPT_DIR/bot2.go"
        0) echo "Au revoir"; exit 0 ;;
        *) echo "Option invalide."
           sleep 1 
           ;;
    esac
done
     
