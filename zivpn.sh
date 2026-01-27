#!/bin/bash
# zivpn-panel-v2.sh - Panel UDP ZiVPN COMPLET (quota + tracking + couleurs FIX)
set -euo pipefail

# ---------- VARIABLES ----------

ZIVPN_BIN="/usr/local/bin/zivpn"
ZIVPN_SERVICE="zivpn.service"
ZIVPN_CONFIG="/etc/zivpn/config.json"
ZIVPN_USER_FILE="/etc/zivpn/users.list"
ZIVPN_DOMAIN_FILE="/etc/zivpn/domain.txt"
ZIVPN_QUOTA_FILE="/etc/zivpn/quotas.list"  # PHONE|IP|QUOTA_BYTES|USED_BYTES

# ---------- FONCTIONS UTILITAIRES ----------

pause() {
  echo
  read -rp "Appuyez sur Entrée pour continuer..."
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "❌ Ce panneau doit être lancé en root."
    exit 1
  fi
}

zivpn_installed() {
  [[ -x "$ZIVPN_BIN" ]] && systemctl list-unit-files | grep -q "^$ZIVPN_SERVICE"
}

zivpn_running() {
  systemctl is-active --quiet "$ZIVPN_SERVICE" 2>/dev/null
}

print_title() {
  clear
  echo "╔═══════════════════════════════════════╗"
  echo "║        ZIVPN CONTROL PANEL v2        ║"
  echo "║     (Compatible @kighmu 🇨🇲)        ║"
  echo "╚═══════════════════════════════════════╝"
  echo
}

show_status_block() {
  echo "------ STATUT ZIVPN ------"
  
  BIN_OK=$([[ -x "$ZIVPN_BIN" ]] && echo "✅" || echo "❌")
  SVC_FILE_OK=$([[ -f "/etc/systemd/system/$ZIVPN_SERVICE" ]] && echo "✅" || echo "❌")
  SVC_ACTIVE=$(systemctl is-active "$ZIVPN_SERVICE" 2>/dev/null || echo "N/A")
  PORT_OK=$(ss -ludp | grep -q 5667 && echo "✅" || echo "❌")
  
  echo "Binaire $ZIVPN_BIN: $BIN_OK"
  echo "Service file: $SVC_FILE_OK"
  echo "Service actif: $SVC_ACTIVE"
  echo "Port 5667: $PORT_OK"
  
  if [[ "$BIN_OK" == "✅" && "$SVC_FILE_OK" == "✅" ]]; then
    if systemctl is-active --quiet "$ZIVPN_SERVICE" 2>/dev/null; then
      echo "✅ ZIVPN : INSTALLÉ et ACTIF"
      echo "   Port interne: 5667 (DNAT 6000-19999)"
    else
      echo "⚠️  ZIVPN : INSTALLÉ mais INACTIF"
    fi
  else
    echo "❌ ZIVPN : NON INSTALLÉ"
  fi
  echo "-----------------------------------------"
  echo
}

# ---------- FONCTIONS QUOTA / STATUT ✅ FIXÉ ----------

bytes_to_gb() {
  awk -v b="$1" 'BEGIN { printf "%.2f", b/1024/1024/1024 }'
}

get_ip_usage() {
  local IP="$1"
  iptables -L FORWARD -v -n 2>/dev/null | awk -v ip="$IP" '
    $1=="pkts" {next}
    $8==ip && $1 ~ /^[0-9]+$/ { sum+=$2 }
    END { print sum+0 }
  ' || echo "0"
}

get_user_status() {
  local USED="$1"
  local QUOTA="$2"
  local EXPIRE="$3"

  TODAY=$(date +%Y-%m-%d)

  if [[ "$TODAY" > "$EXPIRE" ]]; then
    echo "EXPIRÉ"
  elif (( QUOTA > 0 && USED >= QUOTA )); then
    echo "ÉPUISÉ"
  else
    echo "ACTIF"
  fi
}

status_color() {
  local STATUS="$1"
  case "$STATUS" in
    ACTIF)   echo -e "e[32m🟢 ACTIFe[0m" ;;
    ÉPUISÉ)  echo -e "e[31m🔴 ÉPUISÉe[0m" ;;
    EXPIRÉ)  echo -e "e[90m⚫ EXPIRÉe[0m" ;;
    *)       echo "$STATUS" ;;
  esac
}

block_user() {
  local PHONE="$1"
  IP=$(awk -F'|' -v p="$PHONE" '$1==p {print $2}' "$ZIVPN_QUOTA_FILE" 2>/dev/null)
  [[ -z "$IP" ]] && return
  iptables -D FORWARD -s "$IP" -j DROP 2>/dev/null || true
  iptables -A FORWARD -s "$IP" -j DROP
}

# ---------- 1) INSTALLATION ZIVPN (AVEC LOGS VERBOSE) ----------

install_zivpn() {
  print_title
  echo "[1] INSTALLATION ZIVPN (NO CONFLIT UFW)"
  echo

  if zivpn_installed; then
    echo "ZIVPN déjà installé."
    pause
    return
  fi

  systemctl stop zivpn >/dev/null 2>&1 || true
  systemctl stop ufw  >/dev/null 2>&1 || true
  ufw disable         >/dev/null 2>&1 || true
  apt purge ufw -y    >/dev/null 2>&1 || true
  
  iptables -F
  iptables -t nat -F
  iptables -t mangle -F 2>/dev/null || true

  apt update -y && apt install -y wget curl jq openssl iptables-persistent netfilter-persistent

  wget -q "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64" -O "$ZIVPN_BIN"
  chmod +x "$ZIVPN_BIN"
  
  mkdir -p /etc/zivpn
  read -rp "Domaine: " DOMAIN; DOMAIN=${DOMAIN:-"zivpn.local"}
  echo "$DOMAIN" > "$ZIVPN_DOMAIN_FILE"
  
  CERT="/etc/zivpn/zivpn.crt"
  KEY="/etc/zivpn/zivpn.key"
  openssl req -x509 -newkey rsa:2048 -keyout "$KEY" -out "$CERT" -nodes -days 3650 -subj "/CN=$DOMAIN"
  chmod 600 "$KEY"
  chmod 644 "$CERT"

  cat > "$ZIVPN_CONFIG" << 'EOF'
{
  "listen": ":5667",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": ["zi"]
  }
}
EOF

  cat > "/etc/systemd/system/$ZIVPN_SERVICE" << EOF
[Unit]
Description=ZIVPN UDP Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$ZIVPN_BIN server -c $ZIVPN_CONFIG -v
WorkingDirectory=/etc/zivpn
Restart=always
RestartSec=5
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$ZIVPN_SERVICE"

  iptables -A INPUT -p udp --dport 5667 -j ACCEPT
  iptables -A INPUT -p udp --dport 36712 -j ACCEPT
  iptables -A INPUT -p udp --dport 6000:19999 -j ACCEPT
  iptables -t nat -A PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667
  
  netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4

  sysctl -w net.core.rmem_max=16777216
  sysctl -w net.core.wmem_max=16777216
  echo "net.core.rmem_max=16777216" >> /etc/sysctl.conf
  echo "net.core.wmem_max=16777216" >> /etc/sysctl.conf

  systemctl start "$ZIVPN_SERVICE"
  
  sleep 3
  if systemctl is-active --quiet "$ZIVPN_SERVICE"; then
    IP=$(hostname -I | awk '{print $1}')
    echo "✅ ZIVPN installé et actif !"
    echo "📱 Config ZIVPN App:"
    echo "   udp server: $IP"
    echo "   Port: 6000-19999 (auto NAT → 5667)"
    echo "   Password: zi"
    echo "🔍 Logs temps réel: journalctl -u zivpn.service -f"
  else
    echo "❌ ZIVPN ne démarre pas → journalctl -u zivpn.service"
  fi
  
  pause
}

# ---------- 2) CRÉATION UTILISATEUR (IP OPTIONNELLE) ----------

create_zivpn_user() {
  print_title
  echo "[2] CRÉATION UTILISATEUR ZIVPN"

  if ! systemctl is-active --quiet "$ZIVPN_SERVICE"; then
    echo "❌ Service ZIVPN inactif ou non installé."
    pause
    return
  fi

  echo "Format: téléphone|password|quota|durée"
  echo "Ex: 2330 / MonPass123 / 50 / 30 (quota=0=illimité)"
  echo

  read -rp "Téléphone: " PHONE
  read -rp "Password ZIVPN: " PASS
  read -rp "Quota (Go, 0=illimité): " QUOTA_GB
  read -rp "Durée (jours): " DAYS
  read -rp "IP client (optionnel): " USER_IP

  EXPIRE=$(date -d "+${DAYS} days" '+%Y-%m-%d')
  QUOTA_BYTES=$(awk -v gb="${QUOTA_GB:-0}" 'BEGIN { print int(gb*1024*1024*1024) }')
  USER_IP=${USER_IP:-$(hostname -I | awk '{print $1}')}
  USED_BYTES=0

  # users.list (remplace si existant)
  tmp=$(mktemp)
  grep -v "^$PHONE|" "$ZIVPN_USER_FILE" > "$tmp" 2>/dev/null || true
  echo "$PHONE|$PASS|$EXPIRE" >> "$tmp"
  mv "$tmp" "$ZIVPN_USER_FILE"

  # quotas.list (remplace si existant)
  tmpq=$(mktemp)
  grep -v "^$PHONE|" "$ZIVPN_QUOTA_FILE" > "$tmpq" 2>/dev/null || true
  echo "$PHONE|$USER_IP|$QUOTA_BYTES|$USED_BYTES" >> "$tmpq"
  mv "$tmpq" "$ZIVPN_QUOTA_FILE"

  chmod 600 "$ZIVPN_USER_FILE" "$ZIVPN_QUOTA_FILE"

  # Update config.json
  TODAY=$(date +%Y-%m-%d)
  PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" | \
              sort -u | paste -sd, -)

  if jq --arg passwords "$PASSWORDS" \
        '.auth.config = ($passwords | split(","))' \
        "$ZIVPN_CONFIG" > /tmp/config.json 2>/dev/null; then
    
    if jq empty /tmp/config.json >/dev/null 2>&1; then
      mv /tmp/config.json "$ZIVPN_CONFIG"
      systemctl restart "$ZIVPN_SERVICE"
      
      DOMAIN=$(cat "$ZIVPN_DOMAIN_FILE" 2>/dev/null || echo "$USER_IP")
      echo "✅ UTILISATEUR CRÉÉ"
      echo "━━━━━━━━━━━━━━━━━━━━━"
      echo "📱 $PHONE"
      echo "🔐 $PASS"
      echo "📅 $EXPIRE"
      echo "📦 ${QUOTA_GB:-0} Go"
      echo "🌐 $DOMAIN:6000-19999"
      echo "━━━━━━━━━━━━━━━━━━━━━"
    else
      echo "❌ JSON invalide"
      rm -f /tmp/config.json
    fi
  fi

  pause
}

# ---------- 3) SUPPRESSION UTILISATEUR ----------

delete_zivpn_user() {
  print_title
  echo "[3] SUPPRIMER UTILISATEUR"

  [[ ! -f "$ZIVPN_USER_FILE" || ! -s "$ZIVPN_USER_FILE" ]] && { 
    echo "❌ Aucun utilisateur."; pause; return 
  }

  echo "Utilisateurs:"
  echo "────────────"
  mapfile -t USERS < <(awk -F'|' '{printf "%2d. %s | %s | %s
", NR, $1,$2,$3}' "$ZIVPN_USER_FILE")
  printf '%s
' "${USERS[@]}"
  
  read -rp "Numéro: " NUM
  PHONE=$(awk -F'|' -v n="$NUM" 'NR==n {print $1}' "$ZIVPN_USER_FILE")
  
  [[ -z "$PHONE" ]] && { echo "❌ Invalide"; pause; return; }

  echo "🗑️ Supprimant $PHONE..."
  
  tmp=$(mktemp); grep -v "^$PHONE|" "$ZIVPN_USER_FILE" > "$tmp"; mv "$tmp" "$ZIVPN_USER_FILE"
  tmp=$(mktemp); grep -v "^$PHONE|" "$ZIVPN_QUOTA_FILE" > "$tmp" 2>/dev/null || true; mv "$tmp" "$ZIVPN_QUOTA_FILE"
  chmod 600 "$ZIVPN_USER_FILE" "$ZIVPN_QUOTA_FILE"

  TODAY=$(date +%Y-%m-%d)
  PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" | sort -u | paste -sd, -)
  
  jq --arg passwords "$PASSWORDS" '.auth.config = ($passwords | split(","))' "$ZIVPN_CONFIG" > /tmp/config.json && \
  jq empty /tmp/config.json >/dev/null 2>&1 && mv /tmp/config.json "$ZIVPN_CONFIG" && systemctl restart "$ZIVPN_SERVICE"
  
  echo "✅ $PHONE supprimé"
  pause
}

# ---------- 4) FIX ZIVPN ----------

fix_zivpn() {
  print_title
  echo "[4] FIX ZIVPN + SlowDNS"
  
  update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
  iptables -t nat -F PREROUTING
  iptables -A INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || true
  iptables -A INPUT -p udp --dport 36712 -j ACCEPT 2>/dev/null || true
  iptables -t nat -A PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667
  
  netfilter-persistent save 2>/dev/null || true
  systemctl restart "$ZIVPN_SERVICE"
  
  echo "✅ ZIVPN fixé"
  pause
}

# ---------- 5) DÉSINSTALLATION ----------

uninstall_zivpn() {
  print_title
  echo "[5] DÉSINSTALLATION"
  read -rp "Confirmer ? (o/N): " CONFIRM
  [[ "$CONFIRM" =~ ^[oO]$ ]] || { echo "Annulé"; pause; return; }

  systemctl stop "$ZIVPN_SERVICE" 2>/dev/null || true
  systemctl disable "$ZIVPN_SERVICE" 2>/dev/null || true
  rm -f "/etc/systemd/system/$ZIVPN_SERVICE" "$ZIVPN_BIN"
  rm -rf /etc/zivpn
  systemctl daemon-reload

  iptables -t nat -D PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || true
  iptables -t nat -F PREROUTING 2>/dev/null || true

  echo "✅ ZIVPN supprimé"
  pause
}

# ---------- 6) UTILISATEURS + CONSOMMATION (FIXÉ) ----------

show_users_usage() {
  print_title
  echo "[6] UTILISATEURS – STATUT & CONSOMMATION"
  echo

  [[ ! -f "$ZIVPN_USER_FILE" ]] && { echo "❌ Aucun utilisateur."; pause; return; }

  printf "%-12s %-15s %-10s %-12s %-8s
" "PHONE" "PASSWORD" "QUOTA" "EXPIRATION" "STATUT"
  echo "────────────────────────────────────────────────────────────"

  TODAY=$(date +%Y-%m-%d)
  while IFS='|' read -r PHONE PASS EXPIRE; do
    QUOTA_LINE=$(grep "^$PHONE|" "$ZIVPN_QUOTA_FILE" 2>/dev/null)
    [[ -z "$QUOTA_LINE" ]] && continue

    IP=$(echo "$QUOTA_LINE" | cut -d'|' -f2)
    QUOTA_BYTES=$(echo "$QUOTA_LINE" | cut -d'|' -f3)
    USED_BYTES=$(get_ip_usage "$IP")
    STATUS=$(get_user_status "$USED_BYTES" "$QUOTA_BYTES" "$EXPIRE")

    [[ "$STATUS" != "ACTIF" ]] && block_user "$PHONE"

    USED_GB=$(bytes_to_gb "$USED_BYTES")
    QUOTA_GB=$(bytes_to_gb "$QUOTA_BYTES")
    STATUS_DISPLAY=$(status_color "$STATUS")

    printf "%-12s %-15s %-10s %-12s %s
" \
      "$PHONE" "$PASS" "${QUOTA_GB}Go" "$EXPIRE" "$STATUS_DISPLAY"
  done < <(awk -F'|' -v today="$TODAY" '$3>=today' "$ZIVPN_USER_FILE")

  echo
  echo "💡 Logs temps réel: journalctl -u zivpn.service -f"
  echo "💡 Reset compteurs: iptables -Z"
  pause
}

# ---------- MAIN LOOP ----------

check_root

while true; do
  print_title
  show_status_block
  
  echo "1) Installer ZIVPN"
  echo "2) Créer utilisateur"
  echo "3) Supprimer utilisateur"
  echo "4) Fix ZIVPN (SlowDNS OK)"
  echo "5) Désinstaller"
  echo "6) Utilisateurs + consommation"
  echo "0) Quitter"
  echo
  read -rp "Choix: " CHOIX

  case $CHOIX in
    1) install_zivpn ;;
    2) create_zivpn_user ;;
    3) delete_zivpn_user ;;
    4) fix_zivpn ;;
    5) uninstall_zivpn ;;
    6) show_users_usage ;;
    0) exit 0 ;;
    *) echo "❌ Choix invalide"; sleep 1 ;;
  esac
done
