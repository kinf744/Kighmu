#!/bin/bash
set -euo pipefail
# Panneau XRAY unifié (VLESS + VMESS + TROJAN)
# Fusion des scripts NevermoreSSH (VLESS/TROJAN) et panneau d'installation.
#
# Usage: en root:
#   wget -O /usr/local/bin/xray-panel-unified.sh '...'
#   chmod +x /usr/local/bin/xray-panel-unified.sh
#   /usr/local/bin/xray-panel-unified.sh

# ------------------ colors ------------------
BIBlack='\033[1;90m'; BIRed='\033[1;91m'; BIGreen='\033[1;92m'
BIYellow='\033[1;93m'; BIBlue='\033[1;94m'; BIPurple='\033[1;95m'
BICyan='\033[1;96m'; BIWhite='\033[1;97m'; UWhite='\033[4;37m'
NC='\e[0m'
green() { echo -e "\\033[32;1m${*}\\033[0m"; }
red()   { echo -e "\\033[31;1m${*}\\033[0m"; }

export RED='\033[0;31m'; export GREEN='\033[0;32m'; export YELLOW='\033[0;33m'
export EROR="[${RED} EROR ${NC}]"; export INFO="[${YELLOW} INFO ${NC}]"; export OKEY="[${GREEN} OKEY ${NC}]"

# ------------------ defaults ------------------
domain=""
port_tls=443
port_none=80
xray_bin="/usr/local/bin/xray"
config_file="/usr/local/etc/xray/config.json"
systemd_unit="/etc/systemd/system/xray.service"

# ensure root
if [[ $EUID -ne 0 ]]; then
  echo -e "${EROR} Run this script as root."
  exit 1
fi

# ------------------ helpers ------------------
log_info(){ echo -e "${INFO} $*"; }
log_ok(){ echo -e "${OKEY} $*"; }
err_exit(){ echo -e "${EROR} $*"; exit 1; }

# Validate config JSON
validate_json(){
  if [[ -f "$config_file" ]]; then
    if ! jq empty "$config_file" >/dev/null 2>&1; then
      echo "[ERROR] $config_file contient du JSON invalide."
      return 1
    fi
  fi
  return 0
}

# Find the client object start line for a given id in the file and insert comment(s) before it.
# Args: <client_id> <marker_line1> [<marker_line2>]
insert_marker_before_client() {
  local cid="$1"; shift
  local markers=("$@")
  # find line number that contains the id (exact)
  local lineno
  lineno=$(nl -ba "$config_file" | grep -F "\"$cid\"" | awk '{print $1}' | head -n1 || true)
  if [[ -z "$lineno" ]]; then
    return 1
  fi
  # find start of enclosing object: search upwards for a line that begins with whitespace*{
  local start
  start=$(nl -ba "$config_file" | sed -n "1,${lineno}p" | awk '/^[[:space:]]*{[[:space:]]*$/ {l=NR} END{print l}')
  if [[ -z "$start" || "$start" -eq 0 ]]; then
    # fallback: put marker above the id line
    start=$((lineno-1))
  else
    start=$((start))
  fi
  # Insert markers before start
  local tmp=$(mktemp)
  nl -ba "$config_file" > "$tmp".nl
  # We will build new file: lines 1..start-1, then markers, then rest
  local before=$(mktemp)
  local after=$(mktemp)
  sed -n "1,$((start-1))p" "$config_file" > "$before"
  sed -n "$start,999999p" "$config_file" > "$after"
  # write combined
  {
    cat "$before"
    for m in "${markers[@]}"; do echo "$m"; done
    cat "$after"
  } > "$config_file"
  rm -f "$tmp" "$tmp".nl "$before" "$after"
  return 0
}

# Insert marker lines adjacent to the recently-created client.
# For VLESS: use "#vls user expiry" and "#vlsg user expiry"
# For VMESS: "#vms user expiry" and "#vmsg user expiry"
# For TROJAN: "#tr user expiry" and "#trg user expiry"
# Args: <client_id> <type> <user> <expiry>
insert_client_markers() {
  local cid="$1"; local type="$2"; local user="$3"; local expiry="$4"
  case "$type" in
    vless) insert_marker_before_client "$cid" "#vls $user $expiry" "#vlsg $user $expiry" ;;
    vmess) insert_marker_before_client "$cid" "#vms $user $expiry" "#vmsg $user $expiry" ;;
    trojan) insert_marker_before_client "$cid" "#tr $user $expiry" "#trg $user $expiry" ;;
    *) return 1 ;;
  esac
}

# ------------------ install functions ------------------
install_dependencies() {
  log_info "Installing packages..."
  apt update -y
  DEBIAN_FRONTEND=noninteractive apt install -y curl wget unzip socat cron ntpdate jq nginx \
    openssl uuid-runtime ca-certificates cron bash-completion iproute2 apt-transport-https gnupg
  # install acme.sh will be used later
  log_ok "Dependencies installed."
}

install_xray_binary() {
  log_info "Installing Xray binary..."
  # Try GitHub latest release
  latest=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.tag_name' 2>/dev/null || true)
  tmpd=$(mktemp -d)
  if [[ -n "$latest" ]]; then
    url="https://github.com/XTLS/Xray-core/releases/download/${latest}/xray-linux-64.zip"
    curl -sL "$url" -o "$tmpd/xray.zip" || true
    if unzip -o -q "$tmpd/xray.zip" -d "$tmpd" >/dev/null 2>&1; then
      if [[ -f "$tmpd/xray" ]]; then mv -f "$tmpd/xray" "$xray_bin"; fi
      if [[ -f "$tmpd/xray-linux-64" ]]; then mv -f "$tmpd/xray-linux-64" "$xray_bin"; fi
    fi
  fi
  # fallback: try official installer
  if [[ ! -x "$xray_bin" ]]; then
    log_info "Fallback: tenter install script officiel..."
    curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh | bash -s -- install || true
  fi
  rm -rf "$tmpd"
  if [[ ! -x "$xray_bin" ]]; then
    err_exit "Xray binary not found ($xray_bin)."
  fi
  chmod +x "$xray_bin"
  # allow binding low ports for non-root user
  if command -v setcap >/dev/null 2>&1; then
    setcap 'cap_net_bind_service=+ep' "$xray_bin" || true
  fi
  mkdir -p /usr/local/etc/xray /var/log/xray /home/vps/public_html
  chown -R www-data:www-data /usr/local/etc/xray /var/log/xray /home/vps/public_html || true
  log_ok "Xray installed."
}

setup_acme_and_cert() {
  if [[ -z "${domain:-}" ]]; then err_exit "domain not set for certificate generation."; fi
  log_info "Preparing webroot..."
  mkdir -p /home/vps/public_html/.well-known/acme-challenge
  chown -R www-data:www-data /home/vps/public_html

  # stop nginx to avoid port 80 conflicts (acme.sh can use webroot but ensure no conflict)
  if systemctl is-active --quiet nginx; then
    systemctl stop nginx || true
  fi

  if ! command -v acme.sh >/dev/null 2>&1; then
    curl -sSfL https://get.acme.sh | sh || true
  fi
  export PATH="$HOME/.acme.sh:$PATH"
  ~/.acme.sh/acme.sh --register-account -m admin@"${domain}" || true

  # try webroot, fallback to standalone
  if [[ -d /home/vps/public_html ]]; then
    ~/.acme.sh/acme.sh --issue -d "$domain" --webroot /home/vps/public_html --keylength ec-256 --force --debug 2 --log || \
      ~/.acme.sh/acme.sh --issue -d "$domain" --standalone --keylength ec-256 --force --debug 2 --log
  else
    ~/.acme.sh/acme.sh --issue -d "$domain" --standalone --keylength ec-256 --force --debug 2 --log
  fi

  ~/.acme.sh/acme.sh --install-cert -d "$domain" --ecc \
    --fullchain-file /etc/xray/xray.crt --key-file /etc/xray/xray.key --force

  chown root:root /etc/xray/xray.crt /etc/xray/xray.key || true
  chmod 644 /etc/xray/xray.crt /etc/xray/xray.key || true

  # restart nginx
  systemctl start nginx || true
  log_ok "Certificate installed for $domain"
}

configure_nginx() {
  if [[ -z "${domain:-}" ]]; then err_exit "domain not set for nginx configuration."; fi

  cat > /etc/nginx/conf.d/xray.conf <<EOF
server {
  listen 80;
  listen [::]:80;
  server_name $domain;

  location ^~ /.well-known/acme-challenge/ {
    root /home/vps/public_html;
    default_type "text/plain";
    allow all;
  }

  location / {
    return 301 https://\$host\$request_uri;
  }

  location = /vless { proxy_pass http://127.0.0.1:10000; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; }
  location = /vmess { proxy_pass http://127.0.0.1:10001; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; }
  location = /trojan-ws { proxy_pass http://127.0.0.1:10002; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; }
}

server {
  listen 443 ssl http2;
  server_name $domain;
  ssl_certificate /etc/xray/xray.crt;
  ssl_certificate_key /etc/xray/xray.key;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_ciphers EECDH+AESGCM:EECDH+CHACHA20;

  location = /vless { proxy_pass http://127.0.0.1:10000; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; }
  location = /vmess { proxy_pass http://127.0.0.1:10001; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; }
  location = /trojan-ws { proxy_pass http://127.0.0.1:10002; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; }
}
EOF

  systemctl enable nginx || true
  systemctl restart nginx || true
  log_ok "Nginx configured."
}

create_default_xray_config() {
  mkdir -p "$(dirname "$config_file")"
  uuid_vless=$(uuidgen)
  uuid_vmess=$(uuidgen)
  password_trojan=$(openssl rand -base64 12)

  cat > "$config_file" <<EOF
{
  "log": { "access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log", "loglevel": "info" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $port_tls,
      "protocol": "vless",
      "settings": { "clients": [ { "id": "$uuid_vless", "flow": "xtls-rprx-vision", "email": "vless_user" } ], "decryption": "none" },
      "streamSettings": { "network": "tcp", "security": "xtls", "xtlsSettings": { "alpn": [ "h2", "http/1.1" ], "certificates": [ { "certificateFile": "/etc/xray/xray.crt", "keyFile": "/etc/xray/xray.key" } ] } }
    },
    {
      "listen": "127.0.0.1",
      "port": 10001,
      "protocol": "vmess",
      "settings": { "clients": [{ "id": "$uuid_vmess", "alterId": 0, "email": "vmess_user" }] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/vmess" } }
    },
    {
      "listen": "127.0.0.1",
      "port": 10002,
      "protocol": "trojan",
      "settings": { "clients": [{ "password": "$password_trojan", "email": "trojan_user" }], "decryption": "none" },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/trojan-ws" } }
    }
  ],
  "outbounds": [{ "protocol": "freedom", "settings": {} }]
}
EOF

  validate_json || err_exit "config.json created is invalid"
  log_ok "Default Xray config created."
}

install_systemd_service() {
  cat > "$systemd_unit" <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target network-online.target

[Service]
Type=simple
User=www-data
ExecStart=$xray_bin run -config $config_file
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
  systemctl enable xray || true
  systemctl restart xray || true
  sleep 2
  if ! systemctl is-active --quiet xray; then
    journalctl -u xray --no-pager -n 50 || true
    err_exit "Xray failed to start (voir logs)."
  fi
  log_ok "xray systemd service installed and started."
}

# ------------------ user management ------------------
# Add VLESS user
add_vless() {
  if [[ ! -f "$config_file" ]]; then echo "Config absent. Installe d'abord."; return 1; fi
  read -rp "Nom utilisateur : " user
  if [[ -z "$user" ]]; then echo "Annulé."; return 1; fi
  if jq --arg u "$user" '.inbounds[]?.settings.clients[]? | select(.email==$u)' "$config_file" | grep -q .; then
    echo "Utilisateur existe déjà."; return 1
  fi
  uuid=$(uuidgen)
  exp=$(date -d "+30 days" +%Y-%m-%d)
  tmp=$(mktemp)
  jq --arg id "$uuid" --arg email "$user" '.inbounds[] |= (if .protocol=="vless" then (.settings.clients += [{"id":$id,"flow":"xtls-rprx-vision","email":$email}) ) else . end)' "$config_file" > "$tmp" && mv "$tmp" "$config_file"
  validate_json || { echo "JSON invalide après ajout"; return 1; }
  # insert comment markers before the new client object
  insert_client_markers "$uuid" "vless" "$user" "$exp" || true
  systemctl restart xray || true
  echo "VLESS ajouté: $user, UUID: $uuid, Expire: $exp"
  echo "TLS: vless://$uuid@$domain:$port_tls?path=/vless&security=tls&type=ws#$user"
  echo "NoTLS: vless://$uuid@$domain:$port_none?path=/vless&security=none&type=ws#$user"
}

# Add VMESS user
add_vmess() {
  if [[ ! -f "$config_file" ]]; then echo "Config absent. Installe d'abord."; return 1; fi
  read -rp "Nom utilisateur : " user
  if [[ -z "$user" ]]; then echo "Annulé."; return 1; fi
  if jq --arg u "$user" '.inbounds[]?.settings.clients[]? | select(.email==$u)' "$config_file" | grep -q .; then
    echo "Utilisateur existe déjà."; return 1
  fi
  uuid=$(uuidgen)
  exp=$(date -d "+30 days" +%Y-%m-%d)
  tmp=$(mktemp)
  jq --arg id "$uuid" --arg email "$user" '.inbounds[] |= (if .protocol=="vmess" then (.settings.clients += [{"id":$id,"alterId":0,"email":$email}]) else . end)' "$config_file" > "$tmp" && mv "$tmp" "$config_file"
  validate_json || { echo "JSON invalide après ajout"; return 1; }
  insert_client_markers "$uuid" "vmess" "$user" "$exp" || true
  systemctl restart xray || true
  vmess_json_none="{\"v\":\"2\",\"ps\":\"$user\",\"add\":\"$domain\",\"port\":\"$port_none\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"/vmess\",\"type\":\"none\",\"host\":\"$domain\",\"tls\":\"none\"}"
  vmess_json_tls="{\"v\":\"2\",\"ps\":\"$user TLS\",\"add\":\"$domain\",\"port\":\"$port_tls\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"/vmess\",\"type\":\"none\",\"host\":\"$domain\",\"tls\":\"tls\"}"
  vmess_link_none="vmess://$(echo -n "$vmess_json_none" | base64 -w 0)"
  vmess_link_tls="vmess://$(echo -n "$vmess_json_tls" | base64 -w 0)"
  echo "VMESS ajouté: $user, UUID: $uuid, Exp: $exp"
  echo "TLS: $vmess_link_tls"
  echo "NoTLS: $vmess_link_none"
}

# Add Trojan user
add_trojan() {
  if [[ ! -f "$config_file" ]]; then echo "Config absent. Installe d'abord."; return 1; fi
  read -rp "Nom utilisateur : " user
  if [[ -z "$user" ]]; then echo "Annulé."; return 1; fi
  if jq --arg u "$user" '.inbounds[]?.settings.clients[]? | select(.email==$u)' "$config_file" | grep -q .; then
    echo "Utilisateur existe déjà."; return 1
  fi
  password=$(openssl rand -base64 12)
  exp=$(date -d "+30 days" +%Y-%m-%d)
  tmp=$(mktemp)
  jq --arg pw "$password" --arg email "$user" '.inbounds[] |= (if .protocol=="trojan" then (.settings.clients += [{"password":$pw,"email":$email}]) else . end)' "$config_file" > "$tmp" && mv "$tmp" "$config_file"
  validate_json || { echo "JSON invalide après ajout"; return 1; }
  # find the created client by password - note: passwords may contain chars, but we search for exact substring
  insert_client_markers "$password" "trojan" "$user" "$exp" || true
  systemctl restart xray || true
  echo "TROJAN ajouté: $user, Password: $password, Exp: $exp"
  echo "TLS: trojan://$password@$domain:$port_tls?path=/trojan-ws&security=tls&type=ws#$user"
  echo "NoTLS: trojan://$password@$domain:$port_none?path=/trojan-ws&security=none&type=ws#$user"
}

# Delete user generic: type in {vless,vmess,trojan}
delete_user_type() {
  local typ="$1"
  case "$typ" in
    vless) marker='^#vls ' ;;
    vmess) marker='^#vms ' ;;
    trojan) marker='^#tr ' ;;
    *) echo "Type invalide"; return 1 ;;
  esac
  if [[ ! -f "$config_file" ]]; then echo "Config absent"; return 1; fi
  local users
  users=$(grep -E "$marker" "$config_file" 2>/dev/null | cut -d' ' -f2-3 | sort | uniq) || true
  if [[ -z "$users" ]]; then echo "Aucun utilisateur $typ."; return 0; fi
  echo "Utilisateurs:"
  nl -w2 -s') ' <<<"$users"
  read -rp "Numéro à supprimer: " idx
  if ! [[ "$idx" =~ ^[0-9]+$ ]]; then echo "Annulé"; return 1; fi
  sel=$(nl -w2 -s') ' <<<"$users" | sed -n "${idx}p" | sed 's/^[[:space:]]*[0-9][0-9]*)[[:space:]]*//')
  if [[ -z "$sel" ]]; then echo "Choix invalide"; return 1; fi
  name=$(awk '{print $1}' <<<"$sel")
  exp=$(awk '{print $2}' <<<"$sel")
  # remove from config: delete from marker line up to next "^},{"
  sed -i "/^#${marker//^/}${name} ${exp}/,/^},{/d" "$config_file" 2>/dev/null || true
  # also try removing alternate marker (like #vlsg, #vmsg, #trg)
  alt_marker=""
  case "$typ" in
    vless) alt_marker="#vlsg" ;;
    vmess) alt_marker="#vmsg" ;;
    trojan) alt_marker="#trg" ;;
  esac
  if [[ -n "$alt_marker" ]]; then
    sed -i "/^${alt_marker} ${name} ${exp}/,/^},{/d" "$config_file" 2>/dev/null || true
  fi
  validate_json || echo "Attention: JSON peut être invalide après suppression."
  systemctl restart xray || true
  echo "$typ user deleted: $name (exp: $exp)"
}

# Renew user (add days)
renew_user_type() {
  local typ="$1"
  local marker
  case "$typ" in
    vless) marker='^#vlsg ' ;;
    vmess) marker='^#vmsg ' ;;
    trojan) marker='^#trg ' ;;
    *) echo "Type invalide"; return 1 ;;
  esac
  if [[ ! -f "$config_file" ]]; then echo "Config absent"; return 1; fi
  local users
  users=$(grep -E "$marker" "$config_file" 2>/dev/null | cut -d' ' -f2-3 | sort | uniq) || true
  if [[ -z "$users" ]]; then echo "Aucun utilisateur $typ."; return 0; fi
  echo "Utilisateurs:"
  nl -w2 -s') ' <<<"$users"
  read -rp "Nom utilisateur à renouveler (ou vide pour annuler): " user
  if [[ -z "$user" ]]; then echo "Annulé"; return 1; fi
  read -rp "Ajouter combien de jours ? " days
  if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo "Invalid days"; return 1; fi
  exp=$(grep -wE "^${marker}" "$config_file" | grep -w "$user" | awk '{print $3}' | head -n1)
  if [[ -z "$exp" ]]; then echo "Utilisateur non trouvé"; return 1; fi
  now=$(date +%Y-%m-%d)
  d1=$(date -d "$exp" +%s)
  d2=$(date -d "$now" +%s)
  remaining_days=$(( (d1 - d2) / 86400 ))
  if (( remaining_days < 0 )); then remaining_days=0; fi
  new_total=$(( remaining_days + days ))
  new_exp=$(date -d "$new_total days" +%Y-%m-%d)
  # replace both marker forms if present
  case "$typ" in
    vless)
      sed -i "/#vlsg $user/c\#vlsg $user $new_exp" "$config_file" || true
      sed -i "/#vls $user/c\#vls $user $new_exp" "$config_file" || true
      ;;
    vmess)
      sed -i "/#vmsg $user/c\#vmsg $user $new_exp" "$config_file" || true
      sed -i "/#vms $user/c\#vms $user $new_exp" "$config_file" || true
      ;;
    trojan)
      sed -i "/#trg $user/c\#trg $user $new_exp" "$config_file" || true
      sed -i "/#tr $user/c\#tr $user $new_exp" "$config_file" || true
      ;;
  esac
  systemctl restart xray || true
  echo "$typ user $user renewed until $new_exp"
}

# Check current websocket users (combines both VLESS/VMESS/TROJAN markers)
check_ws_users() {
  echo -n > /tmp/other.txt
  # collect all marker names (vls, vms, tr)
  data=( $(grep -E "^#(vls|vms|tr) " /etc/xray/config.json 2>/dev/null | cut -d' ' -f2 | sort -u) )
  echo "-------------------------------"
  echo "-----=[ XRAY User Login ]=-----"
  echo "-------------------------------"
  for akun in "${data[@]}"; do
    [[ -z "$akun" ]] && akun="tidakada"
    echo -n > /tmp/ipxray.txt
    data2=( $(tail -n 500 /var/log/xray/access.log 2>/dev/null | awk '{print $3}' | sed 's/tcp://g' | cut -d: -f1 | sort -u) )
    for ip in "${data2[@]}"; do
      jum=$(grep -w "$akun" /var/log/xray/access.log 2>/dev/null | tail -n 500 | awk '{print $3}' | sed 's/tcp://g' | cut -d: -f1 | grep -w "$ip" | sort -u || true)
      if [[ "$jum" == "$ip" ]]; then
        echo "$jum" >> /tmp/ipxray.txt
      else
        echo "$ip" >> /tmp/other.txt
      fi
      jum2=$(cat /
