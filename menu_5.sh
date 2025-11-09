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

# Affiche le menu avec titre dans cadre
afficher_menu() {
  clear
  echo -e "${CYAN}╔════════════════════════════════╗${RESET}"
  echo -e "${YELLOW}║       V2RAY PROTOCOLE${RESET}"
  echo -e "${YELLOW}║--------------------------------${RESET}"
}

# Affiche la ligne indiquant l'état du tunnel V2Ray WS
afficher_mode_v2ray_ws() {
  if systemctl is-active --quiet v2ray.service; then
    local v2ray_port=$(jq -r '.inbounds[0].port' /etc/v2ray/config.json 2>/dev/null || echo "8088")
    echo -e "${CYAN}Tunnel actif:${RESET}"
    echo -e "  - V2Ray WS sur le port TCP ${GREEN}$v2ray_port${RESET}"
  fi
}

# Affiche les options du menu
show_menu() {
  echo -e "${YELLOW}║--------------------------------${RESET}"
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

  creer_service_systemd_v2ray

  echo -e "${GREEN}V2Ray WS installé et lancé sur le port 8088 avec path /vmess-ws pour le domaine ${domaine}${RESET}"
  echo "N'oubliez pas d'ouvrir et rediriger le port 8088 sur votre VPS."
  read -p "Appuyez sur Entrée pour continuer..."
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
  echo -e "   NTLS  : 8088"
  echo -e "➤ UUID généré :"
  echo -e "   NTLS  : $uuid"
  echo -e "➤ Paths :"
  echo -e "   NTLS   : /vmess-ws"
  echo -e "➤ Validité : $duree jours (expire le $date_exp)"
  echo -e "●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●"
  echo ""
  echo -e "┃ Non‑TLS : vmess://$uuid@$domaine:8088?security=none&type=ws&host=$domaine&path=/vmess-ws&encryption=none#$nom"
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
  echo -n "Êtes-vous sûr de vouloir désinstaller V2Ray ? (o/N) : "
  read reponse
  if [[ "$reponse" =~ ^[Oo]$ ]]; then
    sudo systemctl stop v2ray.service
    sudo systemctl disable v2ray.service
    sudo rm -f /etc/systemd/system/v2ray.service
    sudo systemctl daemon-reload
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
  afficher_mode_v2ray_ws
  show_menu
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
