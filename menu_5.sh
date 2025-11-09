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

# Fonction d’affichage du menu
afficher_menu() {
  clear
  echo -e "${CYAN}╔════════════════════════════════╗${RESET}"
  echo -e "${YELLOW}║       V2RAY PROTOCOLE${RESET}"
  echo -e "${YELLOW}║--------------------------------${RESET}"
afficher_mode_v2ray_ws() {
    # Vérifie si V2Ray est lancé avec config run
    if pgrep -f "v2ray run -config" >/dev/null 2>&1; then
        # Essaye de lire le port configuré dans /etc/v2ray/config.json
        local v2ray_port=$(jq -r '.inbounds[0].port' /etc/v2ray/config.json 2>/dev/null || echo "8088")
        echo -e "${CYAN}Tunnel actif:${RESET}"
        echo -e "  - V2Ray WS sur le port TCP ${GREEN}$v2ray_port${RESET}"
    fi
}

  echo -e "${YELLOW}║ 1) Installer tunnel V2Ray WS${RESET}"
  echo -e "${YELLOW}║ 2) Créer nouvel utilisateur${RESET}"
  echo -e "${YELLOW}║ 3) Supprimer un utilisateur${RESET}"
  echo -e "${YELLOW}║ 4) Désinstaller V2Ray${RESET}"
  echo -e "${RED}║ 0) Quitter${RESET}"
  echo -e "${CYAN}╚════════════════════════════════╝${RESET}"
  echo -n "Choisissez une option : "
}

# Générer UUID v4
generer_uuid() {
  cat /proc/sys/kernel/random/uuid
}

# Installer V2Ray WS sans TLS (demande domaine)
installer_v2ray() {
  echo -n "Entrez votre domaine (ex: example.com) : "
  read domaine

  echo "Installation de V2Ray WS sans TLS..."
  # Téléchargement et installation de V2Ray
  wget -q https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip -O /tmp/v2ray.zip
  unzip -q /tmp/v2ray.zip -d /tmp/v2ray
  sudo mv /tmp/v2ray/v2ray /usr/local/bin/
  sudo mv /tmp/v2ray/v2ctl /usr/local/bin/
  sudo chmod +x /usr/local/bin/v2ray /usr/local/bin/v2ctl
  sudo mkdir -p /etc/v2ray

  # Config basique WS sans TLS, port 8088 (modifié via port inclus dans la config), path /vmess-ws
  cat <<EOF | sudo tee /etc/v2ray/config.json > /dev/null
{
  "inbounds": [
    {
      "port": 8088,
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

  sudo pkill v2ray 2>/dev/null
  sudo /usr/local/bin/v2ray run -config /etc/v2ray/config.json &

  echo -e "${GREEN}V2Ray WS installé et lancé sur le port 8088 avec path /vmess-ws pour le domaine ${domaine}${RESET}"
  echo "N'oubliez pas d'ouvrir et rediriger le port 8088 sur votre VPS."
  read -p "Appuyez sur Entrée pour continuer..."
}

# Charger utilisateurs JSON
charger_utilisateurs() {
  if [[ ! -f $USER_DB ]]; then
    echo "[]" > "$USER_DB"
  fi
  utilisateurs=$(cat "$USER_DB")
}

# Sauvegarder utilisateurs JSON
sauvegarder_utilisateurs() {
  echo "$utilisateurs" > "$USER_DB"
}

# Ajouter un utilisateur
creer_utilisateur() {
  charger_utilisateurs

  echo -n "Entrez un nom d'utilisateur : "
  read nom
  echo -n "Durée de validité (en jours) : "
  read duree

  uuid=$(generer_uuid)
  date_exp=$(date -d "+${duree} days" +%Y-%m-%d)

  # Ajouter dans JSON
  utilisateurs=$(echo "$utilisateurs" | jq --arg n "$nom" --arg u "$uuid" --arg d "$date_exp" '. += [{"nom": $n, "uuid": $u, "expire": $d}]')
  sauvegarder_utilisateurs

  domaine_default="votre-domaine.com"
  domaine="$domaine_default"

  clear
  echo -e "=============================="
  echo -e "🧩 VMESS"
  echo -e "=============================="
  echo -e "📄 Configuration générée pour : $nom"
  echo -e "--------------------------------------------------"
  echo -e "➤ DOMAINE : $domaine"
  echo -e "➤ PORTs :"
  echo -e "   NTLS  : 80"
  echo -e "➤ UUID généré :"
  echo -e "   NTLS  : $uuid"
  echo -e "➤ Paths :"
  echo -e "   NTLS   : /vmess-ws"
  echo -e "➤ Validité : $duree jours (expire le $date_exp)"
  echo -e "●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●"
  echo ""
  echo -e "┃ Non‑TLS : vmess://$uuid@$domaine:80?security=none&type=ws&host=$domaine&path=/vmess-ws&encryption=none#$nom"
  echo -e "●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●"
  echo ""
  read -p "Appuyez sur Entrée pour continuer..."
}

# Supprimer utilisateur
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

# Désinstaller V2Ray avec confirmation
desinstaller_v2ray() {
  echo -n "Êtes-vous sûr de vouloir désinstaller V2Ray ? (o/N) : "
  read reponse
  if [[ "$reponse" =~ ^[Oo]$ ]]; then
    sudo pkill v2ray 2>/dev/null
    sudo rm -rf /usr/local/bin/v2ray /usr/local/bin/v2ctl /etc/v2ray
    echo "V2Ray désinstallé et nettoyé."
  else
    echo "Désinstallation annulée."
  fi
  read -p "Appuyez sur Entrée pour continuer..."
}

# Programme principal
while true; do
  afficher_menu
  read option
  case "$option" in
    1) installer_v2ray ;;
    2) creer_utilisateur ;;
    3) supprimer_utilisateur ;;
    4) desinstaller_v2ray ;;
    0) echo "Sortie..." ; exit 0 ;;
    *) echo "Option invalide." ; sleep 1 ;;
  esac
done
