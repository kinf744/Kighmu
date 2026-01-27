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
  echo -e "${MAGENTA}╔═══════════════════════════════════════╗${RESET}"
  echo -e "${MAGENTA}║        ZIVPN CONTROL PANEL v2        ║${RESET}"
  echo -e "${MAGENTA}║     (Compatible @kighmu 🇨🇲)        ║${RESET}"
  echo -e "${MAGENTA}╚═══════════════════════════════════════╝${RESET}"
  echo
}

show_status_block() {
  # Titre du bloc
  echo -e "${MAGENTA}-------- STATUT ZIVPN --------${RESET}"

  # Vérification des statuts
  SVC_FILE_OK=$([[ -f "/etc/systemd/system/$ZIVPN_SERVICE" ]] && echo -e "${GREEN}✅ OK${RESET}" || echo -e "${RED}❌ MANQUANT${RESET}")
  SVC_ACTIVE=$(systemctl is-active "$ZIVPN_SERVICE" 2>/dev/null && echo -e "${GREEN}ACTIF${RESET}" || echo -e "${RED}INACTIF${RESET}")
  PORT_OK=$(ss -ludp | grep -q 5667 && echo -e "${GREEN}✅ OUVERT${RESET}" || echo -e "${RED}❌ FERMÉ${RESET}")

  # Affichage
  echo -e "${CYAN}Service file :${RESET} $SVC_FILE_OK"
  echo -e "${CYAN}Service actif :${RESET} $SVC_ACTIVE"
  echo -e "${CYAN}Port 5667 :${RESET} $PORT_OK"

  # Résumé général
  if [[ "$SVC_FILE_OK" == *"✅"* ]]; then
    if zivpn_running; then
      echo -e "${GREEN}[✔] ZIVPN : INSTALLÉ et ACTIF (Port interne: 5667)${RESET}"
    else
      echo -e "${YELLOW}[!] ZIVPN : INSTALLÉ mais INACTIF${RESET}"
    fi
  else
    echo -e "${RED}[✖] ZIVPN : NON INSTALLÉ${RESET}"
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
    
      echo
      echo "✅ 𝗨𝗧𝗜𝗟𝗜𝗦𝗔𝗧𝗘𝗨𝗥 𝗖𝗥𝗘𝗘𝗥"
      echo "━━━━━━━━━━━━━━━━━━━━━"
      echo "🌐 𝗗𝗼𝗺𝗮𝗶𝗻𝗲  : $DOMAIN"
      echo "🎭 𝗢𝗯𝗳𝘀     : zivpn"
      echo "🔐 𝗣𝗮𝘀𝘀𝘄𝗼𝗿𝗱 : $PASS"
      echo "📦 𝗤𝘂𝗼𝘁𝗮.   : $QUOTA_GB Go"
      echo "📅 𝗘𝘅𝗽𝗶𝗿𝗲   : $EXPIRE"
      echo "🔌 𝐏𝐨𝐫𝐭    : 5667"
      echo "━━━━━━━━━━━━━━━━━━━━━"
  else
    err "Erreur config → supprimé"
    rm -f "$ZIVPN_USER_FILE"
  fi

  pause
}

# ---------- 3) SUPPRESSION UTILISATEUR ----------
delete_zivpn_user() {
  print_title
  echo -e "${MAGENTA}[3] SUPPRIMER UTILISATEUR${RESET}"
  echo

  # Vérifie s'il y a des utilisateurs
  [[ ! -s "$ZIVPN_USER_FILE" ]] && { echo -e "${YELLOW}[!] Aucun utilisateur${RESET}"; pause; return; }

  # Affiche les utilisateurs
  echo -e "${MAGENTA}Utilisateurs actifs:${RESET}"
  nl -w2 -s'. ' "$ZIVPN_USER_FILE" | awk -F'|' '{printf "'"$CYAN"'%s | %s | %s'"$RESET"'\n", $1, $2, $3}'

  # Demande le numéro
  read -rp "$(echo -e ${BLUE}🔢 Numéro:${RESET} )" NUM
  PHONE=$(sed -n "${NUM}p" "$ZIVPN_USER_FILE" 2>/dev/null | cut -d'|' -f1)

  # Vérification du choix
  [[ -z "$PHONE" ]] && { echo -e "${YELLOW}[!] Numéro invalide${RESET}"; pause; return; }

  # Supprime l'utilisateur sélectionné
  awk -F'|' -v phone="$PHONE" '$1!=phone' "$ZIVPN_USER_FILE" > /tmp/users.tmp
  mv /tmp/users.tmp "$ZIVPN_USER_FILE"

  # Recharge la config ZIVPN
  TODAY=$(date +%Y-%m-%d)
  PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" | paste -sd,)

  jq --arg passwords "$PASSWORDS" \
     '.auth.config = ($passwords | split(","))' \
     "$ZIVPN_CONFIG" > /tmp/config.json && \
  jq empty /tmp/config.json >/dev/null 2>&1 && \
  mv /tmp/config.json "$ZIVPN_CONFIG" && systemctl restart "$ZIVPN_SERVICE"

  # Message de succès
  echo -e "${GREEN}[✔] $PHONE supprimé${RESET}"
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
  echo -e "${MAGENTA}[6] UTILISATEURS & CONSOMMATION TOTALE${RESET}"
  echo

  # Vérifie s'il y a des utilisateurs
  [[ ! -s "$ZIVPN_USER_FILE" ]] && { echo -e "${YELLOW}[!] Aucun utilisateur${RESET}"; pause; return; }

  # Récupération stats
  ZIVPN_PORTS=$(ss -ulnp | grep -E "(5667|6000|19999)" | wc -l)
  UDP_TOTAL=$(awk 'NR>1 {sum+=$2+$3} END{print sum}' /proc/net/udp 2>/dev/null || echo 0)
  TOTAL_GB=$(awk "BEGIN{printf \"%.2f\", $UDP_TOTAL/1024/1024/1024}")

  # Tableau utilisateurs
  echo -e "${CYAN}PHONE        PASS        EXPIRE      QUOTA${RESET}"
  echo -e "${MAGENTA}────────────────────────────────────────${RESET}"

  TODAY=$(date +%Y-%m-%d)
  awk -F'|' -v today="$TODAY" '{
    if($3>=today) 
      printf "'"$CYAN"'%-12s %-12s %-12s %-8s'"$RESET"'\n", substr($1,1,10), substr($2,1,10)"..", $3, ($4 ? $4"Go" : "∞")
  }' "$ZIVPN_USER_FILE"

  echo -e "${MAGENTA}────────────────────────────────────────${RESET}"

  # Stats UDP
  echo -e "${GREEN}📊 UDP TOTAL:${RESET} ${TOTAL_GB} Go (${ZIVPN_PORTS} connexions)"
  echo -e "${CYAN}🔄 Reset:${RESET} ss -z | grep 5667"
  echo -e "${CYAN}🔍 Live:${RESET} watch -n2 ss -ulnp"

  pause
}

# ---------- BOUCLE PRINCIPALE ----------
check_root

while true; do
  print_title
  show_status_block
  
  echo -e "${CYAN}1) Installer ZIVPN${RESET}"
echo -e "${CYAN}2) Créer utilisateur${RESET}" 
echo -e "${CYAN}3) Supprimer utilisateur${RESET}"
echo -e "${CYAN}4) Fix ZIVPN (SlowDNS OK)${RESET}"
echo -e "${CYAN}5) Désinstaller${RESET}"
echo -e "${CYAN}6) Utilisateurs + stats${RESET}"
echo -e "${CYAN}0) Quitter${RESET}"
echo
read -rp "$(echo -e ${BLUE}Choix:${RESET}) " CHOIX

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
