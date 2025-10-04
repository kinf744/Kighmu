#!/bin/bash
set -euo pipefail

domain=""
port_tls=443
port_none=80

function draw_header {
  clear
  echo "===== Panneau de contrôle XRAY ====="
  echo "  Domaine : ${domain:-Non défini}"
  echo "===================================="
}

function clean_git_repo() {
  if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "[INFO] Nettoyage automatique du dépôt git (reset hard + clean)."
    branch=$(git rev-parse --abbrev-ref HEAD)
    git fetch --all
    git reset --hard origin/"$branch"
    git clean -fd
    echo "[INFO] Dépôt git remis à l'état propre."
  else
    echo "[INFO] Pas un dépôt git, nettoyage git ignoré."
  fi
}

function install_dependencies() {
  echo "[INFO] Installation dépendances..."
  apt update
  apt install -y curl wget unzip socat cron ntpdate jq nginx certbot
}

function install_xray() {
  clean_git_repo
  echo "[INFO] Installation de Xray..."
  latest=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.tag_name')
  url="https://github.com/XTLS/Xray-core/releases/download/${latest}/xray-linux-64.zip"
  wget -qO xray.zip "$url"
  unzip -q xray.zip
  rm -f xray.zip
  if [[ -f xray ]]; then
    mv -f xray /usr/local/bin/xray
  elif [[ -f xray-linux-64 ]]; then
    mv -f xray-linux-64 /usr/local/bin/xray
  else
    echo "Binaire Xray introuvable après extraction"
    exit 1
  fi
  chmod +x /usr/local/bin/xray

  mkdir -p /usr/local/etc/xray /var/log/xray /home/vps/public_html
  chown -R www-data:www-data /usr/local/etc/xray /var/log/xray /home/vps/public_html
  echo "[OK] Xray installé."
}

function setup_ssl() {
  echo "[INFO] Configuration certificat SSL pour $domain..."

  mkdir -p /etc/xray
  mkdir -p /home/vps/public_html/.well-known/acme-challenge
  chown -R www-data:www-data /home/vps/public_html/.well-known

  if ! command -v acme.sh &>/dev/null; then
    curl https://get.acme.sh | sh
  fi

  ~/.acme.sh/acme.sh --register-account -m adrienyourie@gmail.com || true
  ~/.acme.sh/acme.sh --issue -d "$domain" --webroot /home/vps/public_html --keylength ec-256 --force
  ~/.acme.sh/acme.sh --install-cert -d "$domain" --ecc --fullchain-file /etc/xray/xray.crt --key-file /etc/xray/xray.key --force

  chown www-data:www-data /etc/xray/xray.crt /etc/xray/xray.key
  chmod 644 /etc/xray/xray.crt /etc/xray/xray.key

  echo "[OK] Certificat SSL généré et installé."
}

function configure_nginx() {
  cat > /etc/nginx/conf.d/xray.conf <<EOF
server {
  listen 80;
  listen [::]:80;
  server_name $domain;

  location / {
    return 301 https://\$host\$request_uri;
  }

  location ^~ /.well-known/acme-challenge/ {
    root /home/vps/public_html;
    default_type "text/plain";
    allow all;
  }

  location = /vless {
    proxy_pass http://127.0.0.1:10000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }

  location = /vmess {
    proxy_pass http://127.0.0.1:10001;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }

  location = /trojan-ws {
    proxy_pass http://127.0.0.1:10002;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
}

server {
  listen 443 ssl http2;
  server_name $domain;

  ssl_certificate /etc/xray/xray.crt;
  ssl_certificate_key /etc/xray/xray.key;

  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_ciphers EECDH+AESGCM:EECDH+CHACHA20;

  location = /vless {
    proxy_pass http://127.0.0.1:10000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }

  location = /vmess {
    proxy_pass http://127.0.0.1:10001;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }

  location = /trojan-ws {
    proxy_pass http://127.0.0.1:10002;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
}
EOF

  systemctl enable nginx
  systemctl restart nginx
  echo "[OK] Nginx configuré."
}

function configure_xray() {
  echo "[INFO] Configuration Xray..."

  mkdir -p /usr/local/etc/xray

  uuid_vless=$(uuidgen)
  uuid_vmess=$(uuidgen)
  password_trojan=$(openssl rand -base64 12)

  cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "info"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $port_tls,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$uuid_vless",
            "flow": "xtls-rprx-vision",
            "email": "vless_user"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "xtls",
        "xtlsSettings": {
          "alpn": [ "h2", "http/1.1" ],
          "certificates": [
            {
              "certificateFile": "/etc/xray/xray.crt",
              "keyFile": "/etc/xray/xray.key"
            }
          ]
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 10001,
      "protocol": "vmess",
      "settings": {
        "clients": [{ "id": "$uuid_vmess", "alterId": 0, "email": "vmess_user" }]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vmess" }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 10002,
      "protocol": "trojan",
      "settings": {
        "clients": [{ "password": "$password_trojan", "email": "trojan_user" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/trojan-ws" }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom", "settings": {} }]
}
EOF

  cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target network-online.target
Wants=network-online.target

StartLimitIntervalSec=500
StartLimitBurst=5

[Service]
Type=simple
User=www-data
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
StandardOutput=append:/var/log/xray/access.log
StandardError=append:/var/log/xray/error.log

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable xray
  systemctl restart xray
  echo "[OK] Xray configuré et démarré avec flow xtls-rprx-vision et TLS activé."
}

function add_user_vmess() {
  echo "[INFO] Ajout utilisateur VMESS"
  if [[ ! -f /usr/local/etc/xray/config.json ]]; then
    echo "[ERREUR] Le fichier /usr/local/etc/xray/config.json est absent. Veuillez d'abord installer Xray."
    return
  fi
  read -rp "Nom utilisateur : " user
  if jq --arg user "$user" '.inbounds[].settings.clients[] | select(.email==$user)' /usr/local/etc/xray/config.json | grep -q .; then
    echo "[ERREUR] L'utilisateur existe déjà."
    return
  fi
  uuid=$(uuidgen)
  tmpfile=$(mktemp)
  jq --arg uuid "$uuid" --arg user "$user" '
    (.inbounds[] | select(.protocol=="vmess").settings.clients) += [{"id":$uuid,"alterId":0,"email":$user}]
  ' /usr/local/etc/xray/config.json > "$tmpfile" && mv "$tmpfile" /usr/local/etc/xray/config.json

  if ! jq empty /usr/local/etc/xray/config.json; then
    echo "[ERREUR] Fichier config.json non valide après modification !"
    return
  fi

  systemctl restart xray

  exp_date=$(date -d "+30 days" +%Y-%m-%d)
  vmess_json_none="{\"v\":\"2\",\"ps\":\"$user\",\"add\":\"$domain\",\"port\":\"$port_none\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"/vmess\",\"type\":\"none\",\"host\":\"$domain\",\"tls\":\"none\"}"
  vmess_json_tls="{\"v\":\"2\",\"ps\":\"$user TLS\",\"add\":\"$domain\",\"port\":\"$port_tls\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"/vmess\",\"type\":\"none\",\"host\":\"$domain\",\"tls\":\"tls\"}"
  vmess_link_none="vmess://$(echo -n "$vmess_json_none" | base64 -w 0)"
  vmess_link_tls="vmess://$(echo -n "$vmess_json_tls" | base64 -w 0)"

  echo -e "\n(*NOUVEAU UTILISATEUR XRAY*)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DOMAIN        : $domain
UTILISATEUR   : $user
UUID          : $uuid
Path          : /vmess
DATE EXPIRÉE  : $exp_date
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Lien TLS      : $vmess_link_tls
Lien Non-TLS  : $vmess_link_none
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"
}

function add_user_vless() {
  echo "[INFO] Ajout utilisateur VLESS"
  if [[ ! -f /usr/local/etc/xray/config.json ]]; then
    echo "[ERREUR] Le fichier /usr/local/etc/xray/config.json est absent. Veuillez d'abord installer Xray."
    return
  fi
  read -rp "Nom utilisateur : " user
  if jq --arg user "$user" '.inbounds[].settings.clients[] | select(.email==$user)' /usr/local/etc/xray/config.json | grep -q .; then
    echo "[ERREUR] L'utilisateur existe déjà."
    return
  fi
  uuid=$(uuidgen)
  tmpfile=$(mktemp)
  jq --arg uuid "$uuid" --arg user "$user" '
    (.inbounds[] | select(.protocol=="vless").settings.clients) += [{"id":$uuid,"email":$user}]
  ' /usr/local/etc/xray/config.json > "$tmpfile" && mv "$tmpfile" /usr/local/etc/xray/config.json

  if ! jq empty /usr/local/etc/xray/config.json; then
    echo "[ERREUR] Fichier config.json non valide après modification !"
    return
  fi

  systemctl restart xray

  exp_date=$(date -d "+30 days" +%Y-%m-%d)
  vless_link_tls="vless://$uuid@$domain:$port_tls?path=/vless&security=tls&type=ws#$user"
  vless_link_none="vless://$uuid@$domain:$port_none?path=/vless&security=none&type=ws#$user"

  echo -e "\n(*NOUVEAU UTILISATEUR XRAY*)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DOMAIN        : $domain
UTILISATEUR   : $user
UUID          : $uuid
Path          : /vless
DATE EXPIRÉE  : $exp_date
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Lien TLS      : $vless_link_tls
Lien Non-TLS  : $vless_link_none
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"
}

function add_user_trojan() {
  echo "[INFO] Ajout utilisateur TROJAN"
  if [[ ! -f /usr/local/etc/xray/config.json ]]; then
    echo "[ERREUR] Le fichier /usr/local/etc/xray/config.json est absent. Veuillez d'abord installer Xray."
    return
  fi
  read -rp "Nom utilisateur : " user
  if jq --arg user "$user" '.inbounds[].settings.clients[] | select(.email==$user)' /usr/local/etc/xray/config.json | grep -q .; then
    echo "[ERREUR] L'utilisateur existe déjà."
    return
  fi
  password=$(openssl rand -base64 12)
  tmpfile=$(mktemp)
  jq --arg password "$password" --arg user "$user" '
    (.inbounds[] | select(.protocol=="trojan").settings.clients) += [{"password":$password,"email":$user}]
  ' /usr/local/etc/xray/config.json > "$tmpfile" && mv "$tmpfile" /usr/local/etc/xray/config.json

  if ! jq empty /usr/local/etc/xray/config.json; then
    echo "[ERREUR] Fichier config.json non valide après modification !"
    return
  fi

  systemctl restart xray

  exp_date=$(date -d "+30 days" +%Y-%m-%d)
  trojan_link_tls="trojan://$password@$domain:$port_tls?path=/trojan-ws&security=tls&type=ws#$user"
  trojan_link_none="trojan://$password@$domain:$port_none?path=/trojan-ws&security=none&type=ws#$user"

  echo -e "\n(*NOUVEAU UTILISATEUR XRAY*)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DOMAIN        : $domain
UTILISATEUR   : $user
Password      : $password
Path          : /trojan-ws
DATE EXPIRÉE  : $exp_date
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Lien TLS      : $trojan_link_tls
Lien Non-TLS  : $trojan_link_none
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"
}

function delete_user() {
  echo "[INFO] Suppression utilisateur XRAY"
  if [[ ! -f /usr/local/etc/xray/config.json ]]; then
    echo "[ERREUR] Le fichier /usr/local/etc/xray/config.json est absent. Veuillez d'abord installer Xray."
    return
  fi
  users=$(jq -r '.inbounds[].settings.clients[].email' /usr/local/etc/xray/config.json | sort -u)
  if [[ -z "$users" ]]; then
    echo "Aucun utilisateur à supprimer."
    return
  fi

  mapfile -t arr <<< "$users"
  echo "Utilisateurs XRAY :"
  for i in "${!arr[@]}"; do
    echo "$((i+1))) ${arr[i]}"
  done

  read -rp "Numéro utilisateur à supprimer: " choice
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#arr[@]} )); then
    echo "Choix invalide."
    return
  fi

  userdel="${arr[choice-1]}"
  tmpfile=$(mktemp)
  jq "(.inbounds[].settings.clients) |= map(select(.email != \"$userdel\"))" /usr/local/etc/xray/config.json > "$tmpfile" && mv "$tmpfile" /usr/local/etc/xray/config.json

  if ! jq empty /usr/local/etc/xray/config.json; then
    echo "[ERREUR] Fichier config.json non valide après suppression !"
    return
  fi

  systemctl restart xray
  echo "Utilisateur $userdel supprimé."
}

function uninstall_services() {
  echo "[INFO] Désinstallation complète de Xray et services associés"
  read -rp "Confirmer la désinstallation complète ? (o/N) : " confirm
  if [[ "${confirm,,}" != "o" ]]; then
    echo "Annulation de la désinstallation."
    return
  fi

  if systemctl is-active --quiet xray.service; then
    systemctl stop xray.service
  else
    echo "[INFO] Service xray non démarré, arrêt ignoré."
  fi

  if systemctl is-enabled --quiet xray.service; then
    systemctl disable xray.service
  else
    echo "[INFO] Service xray non activé, désactivation ignorée."
  fi

  rm -f /usr/local/bin/xray
  rm -rf /usr/local/etc/xray /var/log/xray /home/vps/public_html

  if [[ -f /etc/nginx/conf.d/xray.conf ]]; then
    rm -f /etc/nginx/conf.d/xray.conf
    systemctl restart nginx
  fi

  apt purge -y nginx certbot || echo "[INFO] nginx ou certbot peut ne pas être installé."
  apt autoremove -y || true

  systemctl daemon-reload
  echo "Désinstallation terminée."
}

function menu() {
  draw_header
  echo "1) Installer tout (dépendances, Xray, SSL, Nginx)"
  echo "2) Ajouter utilisateur VMESS"
  echo "3) Ajouter utilisateur VLESS"
  echo "4) Ajouter utilisateur TROJAN"
  echo "5) Supprimer un utilisateur"
  echo "6) Désinstaller XRAY"
  echo "7) Quitter"
  echo

  read -rp "Choix: " choice

  case "$choice" in
    1)
      read -rp "Veuillez entrer votre nom de domaine (doit pointer vers ce serveur) : " domain
      if [[ -z "$domain" ]]; then
        echo "Erreur : domaine invalide."
        read -n1 -s -r -p "Appuyez sur une touche pour revenir au menu..."
        menu
        return
      fi
      export domain
      install_dependencies
      install_xray
      setup_ssl
      configure_nginx
      configure_xray
      ;;
    2) add_user_vmess ;;
    3) add_user_vless ;;
    4) add_user_trojan ;;
    5) delete_user ;;
    6) uninstall_services ;;
    7) exit 0 ;;
    *) echo "Choix invalide."; sleep 1 ;;
  esac
  read -n1 -s -r -p "Appuyez sur une touche pour revenir au menu..."
  menu
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  menu
fi
