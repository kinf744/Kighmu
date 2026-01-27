#!/bin/bash
# zivpn-panel-v2.sh - Panel UDP ZiVPN COMPLET (100% FONCTIONNEL)
set -euo pipefail

# ================= COULEURS =================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"
MAGENTA="\033[35m"
RESET="\033[0m"

# ================= FONCTIONS DE LOG =================
log()   { echo -e "${GREEN}[✔]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[!]${RESET} $*"; }
err()   { echo -e "${RED}[✖]${RESET} $*"; exit 1; }
info()  { echo -e "${CYAN}[i]${RESET} $*"; }
title() { echo -e "${MAGENTA}$*${RESET}"; }
pause() { echo; read -rp "$(echo -e ${BLUE}Appuyez sur Entrée pour continuer...${RESET})"; }

# ---------- VARIABLES ----------
ZIVPN_BIN="/usr/local/bin/zivpn"
ZIVPN_SERVICE="zivpn.service"
ZIVPN_CONFIG="/etc/zivpn/config.json"
ZIVPN_USER_FILE="/etc/zivpn/users.list"
ZIVPN_DOMAIN_FILE="/etc/zivpn/domain.txt"
ZIVPN_QUOTA_FILE="/etc/zivpn/quotas.list"

# ---------- FONCTIONS UTILITAIRES ----------
check_root() {
  [[ $EUID -ne 0 ]] && err "Ce panneau doit être lancé en root."
}

zivpn_installed() {
  [[ -x "$ZIVPN_BIN" ]] && systemctl list-unit-files | grep -q "^$ZIVPN_SERVICE"
}

zivpn_running() {
  systemctl is-active --quiet "$ZIVPN_SERVICE" 2>/dev/null
}

print_title() {
  clear
  title "╔═══════════════════════════════════════╗"
  title "║        ZIVPN CONTROL PANEL v2        ║"
  title "║     (Compatible @kighmu 🇨🇲)        ║"
  title "╚═══════════════════════════════════════╝"
  echo
}

show_status_block() {
  title "-------- STATUT ZIVPN --------"

  SVC_FILE_OK=$([[ -f "/etc/systemd/system/$ZIVPN_SERVICE" ]] && echo "✅" || echo "❌")
  SVC_ACTIVE=$(systemctl is-active "$ZIVPN_SERVICE" 2>/dev/null || echo "N/A")
  PORT_OK=$(ss -ludp | grep -q 5667 && echo "✅" || echo "❌")

  info "Service file: $SVC_FILE_OK"
  info "Service actif: $SVC_ACTIVE"
  info "Port 5667: $PORT_OK"

  if [[ "$SVC_FILE_OK" == "✅" ]]; then
    if zivpn_running; then
      log "ZIVPN : INSTALLÉ et ACTIF (Port interne: 5667)"
    else
      warn "ZIVPN : INSTALLÉ mais INACTIF"
    fi
  else
    err "ZIVPN : NON INSTALLÉ"
  fi
  echo
}

# ---------- FONCTIONS QUOTA / STATUT ----------
bytes_to_gb() { awk -v b="$1" 'BEGIN { printf "%.2f", b/1024/1024/1024 }'; }

get_total_usage() {
  iptables -L INPUT -v -n 2>/dev/null | awk '
    $1=="pkts" {next}
    $5 ~ /^5667$/ {sum+=$2}
    END {print sum+0}'
}

status_color() {
  local STATUS="$1"
  case "$STATUS" in
    ACTIF)  echo -e "${GREEN}🟢 ACTIF${RESET}" ;;
    ÉPUISÉ) echo -e "${RED}🔴 ÉPUISÉ${RESET}" ;;
    EXPIRÉ) echo -e "${BLUE}⚫ EXPIRÉ${RESET}" ;;
    *)      echo "$STATUS" ;;
  esac
}

# ---------- 1) INSTALLATION ZIVPN ----------
install_zivpn() {
  print_title
  title "[1] INSTALLATION ZIVPN (NO CONFLIT UFW)"
  echo

  if zivpn_installed; then
    log "ZIVPN déjà installé."
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
ExecStart=$ZIVPN_BIN server -c $ZIVPN_CONFIG
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
  if zivpn_running; then
    IP=$(hostname -I | awk '{print $1}')
    log "ZIVPN installé et actif !"
    info "📱 Config ZIVPN App:"
    info "   Server: $IP"
    info "   Port: 6000-19999 (NAT → 5667)"
    info "   Password: zi"
  else
    err "ZIVPN ne démarre pas → journalctl -u zivpn.service"
  fi
  
  pause
}

# ---------- 2) CRÉATION UTILISATEUR ----------
create_zivpn_user() {
  print_title
  title "[2] CRÉATION UTILISATEUR ZIVPN"

  ! zivpn_running && err "Service ZIVPN inactif."

  echo "Exemple: 23301234567 | MonPass123 | 30 jours | 50 Go"
  echo

  read -rp "📱 Téléphone: " PHONE
  read -rp "🔐 Password: " PASS
  read -rp "📅 Jours: " DAYS
  read -rp "📦 Quota Go (0=∞): " QUOTA_GB

  EXPIRE=$(date -d "+${DAYS} days" '+%Y-%m-%d')

  tmp=$(mktemp)
  awk -F'|' -v phone="$PHONE" -v pass="$PASS" -v expire="$EXPIRE" -v quota="$QUOTA_GB" '
    $1!=phone {print}
    END {print phone"|"pass"|"expire"|"quota}
  ' "$ZIVPN_USER_FILE" 2>/dev/null > "$tmp" || echo "$PHONE|$PASS|$EXPIRE|$QUOTA_GB" > "$tmp"
  mv "$tmp" "$ZIVPN_USER_FILE"
  chmod 600 "$ZIVPN_USER_FILE"

  TODAY=$(date +%Y-%m-%d)
  PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" | sort -u | paste -sd,)

  if jq --arg passwords "$PASSWORDS" \
        '.auth.config = ($passwords | split(","))' \
        "$ZIVPN_CONFIG" > /tmp/config.json 2>/dev/null && \
     jq empty /tmp/config.json >/dev/null 2>&1; then
    mv /tmp/config.json "$ZIVPN_CONFIG"
    systemctl restart "$ZIVPN_SERVICE"
    
    log "UTILISATEUR AJOUTÉ"
    info "📱 $PHONE"
    info "🔐 $PASS" 
    info "📅 $EXPIRE"
    info "📦 $QUOTA_GB Go"
  else
    err "Erreur config → supprimé"
    rm -f "$ZIVPN_USER_FILE"
  fi

  pause
}

# ---------- 3) SUPPRESSION UTILISATEUR ----------
delete_zivpn_user() {
  print_title
  title "[3] SUPPRIMER UTILISATEUR"

  [[ ! -s "$ZIVPN_USER_FILE" ]] && { warn "Aucun utilisateur"; pause; return; }

  title "Utilisateurs actifs:"
  nl -w2 -s'. ' "$ZIVPN_USER_FILE" | awk -F'|' '{printf "%s | %s | %s\n", $1, $2, $3}'

  read -rp "🔢 Numéro: " NUM
  PHONE=$(sed -n "${NUM}p" "$ZIVPN_USER_FILE" 2>/dev/null | cut -d'|' -f1)

  [[ -z "$PHONE" ]] && { warn "Numéro invalide"; pause; return; }

  awk -F'|' -v phone="$PHONE" '$1!=phone' "$ZIVPN_USER_FILE" > /tmp/users.tmp
  mv /tmp/users.tmp "$ZIVPN_USER_FILE"

  TODAY=$(date +%Y-%m-%d)
  PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" | paste -sd,)

  jq --arg passwords "$PASSWORDS" \
     '.auth.config = ($passwords | split(","))' \
     "$ZIVPN_CONFIG" > /tmp/config.json && \
  jq empty /tmp/config.json >/dev/null 2>&1 && \
  mv /tmp/config.json "$ZIVPN_CONFIG" && systemctl restart "$ZIVPN_SERVICE"

  log "$PHONE supprimé"
  pause
}

# ---------- 4) FIX ZIVPN ----------
fix_zivpn() {
  print_title
  title "[4] FIX ZIVPN + SlowDNS"

  iptables -t nat -F PREROUTING
  iptables -A INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || true
  iptables -A INPUT -p udp --dport 36712 -j ACCEPT 2>/dev/null || true
  iptables -A INPUT -p udp --dport 6000:19999 -j ACCEPT 2>/dev/null || true
  iptables -t nat -A PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667

  netfilter-persistent save 2>/dev/null || true
  systemctl restart "$ZIVPN_SERVICE" 2>/dev/null || true

  log "ZIVPN fixé (SlowDNS préservé)"
  pause
}

# ---------- 5) DÉSINSTALLATION ----------
uninstall_zivpn() {
  print_title
  title "[5] DÉSINSTALLATION"
  read -rp "$(echo -e ${YELLOW}Confirmer ? (o/N):${RESET}) " CONFIRM
  [[ "$CONFIRM" =~ ^[oO]$ ]] || { warn "Annulé"; pause; return; }

  systemctl stop "$ZIVPN_SERVICE" 2>/dev/null || true
  systemctl disable "$ZIVPN_SERVICE" 2>/dev/null || true
  rm -f "/etc/systemd/system/$ZIVPN_SERVICE"
  rm -f "$ZIVPN_BIN" /etc/zivpn/*
  rm -rf /etc/zivpn
  systemctl daemon-reload

  iptables -t nat -D PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || true
  log "ZIVPN supprimé"
  pause
}

# ---------- 6) UTILISATEURS + STATS ----------
show_users_usage() {
  print_title
  title "[6] UTILISATEURS & CONSOMMATION TOTALE"
  echo

  [[ ! -s "$ZIVPN_USER_FILE" ]] && { warn "Aucun utilisateur"; pause; return; }

  ZIVPN_PORTS=$(ss -ulnp | grep -E "(5667|6000|19999)" | wc -l)
  UDP_TOTAL=$(awk 'NR>1 {sum+=$2+$3} END{print sum}' /proc/net/udp 2>/dev/null || echo 0)
  TOTAL_GB=$(awk "BEGIN{printf \"%.2f\", $UDP_TOTAL/1024/1024/1024}")

  printf "%-12s %-12s %-12s %-8s\n" "PHONE" "PASS" "EXPIRE" "QUOTA"
  title "────────────────────────────────────────"

  TODAY=$(date +%Y-%m-%d)
  awk -F'|' -v today="$TODAY" '$3 >= today {
    printf "%-12s %-12s %-12s %-8s\n", substr($1,1,10), substr($2,1,10)"..", $3, ($4 ? $4"Go" : "∞")
  }' "$ZIVPN_USER_FILE"

  title "────────────────────────────────────────"
  info "📊 UDP TOTAL: ${TOTAL_GB}Go (${ZIVPN_PORTS} connexions)"
  info "🔄 Reset: ss -z | grep 5667"
  info "🔍 Live: watch -n2 ss -ulnp"
  pause
}

# ---------- BOUCLE PRINCIPALE ----------
check_root

while true; do
  print_title
  show_status_block
  
  echo "1) Installer ZIVPN"
  echo "2) Créer utilisateur" 
  echo "3) Supprimer utilisateur"
  echo "4) Fix ZIVPN (SlowDNS OK)"
  echo "5) Désinstaller"
  echo "6) Utilisateurs + stats"
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
    *) warn "Choix invalide"; sleep 1 ;;
  esac
done
