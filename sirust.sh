#!/bin/bash
# sirust.sh - ZIVPN Control Panel
# Corrigé: up/down_mbps réalistes, recv_window réduit, CPUScheduling safe,
#           udp_mem adapté RAM, MTU discovery désactivé, watchdog cron

ZIVPN_BIN="/usr/local/bin/zivpn"
ZIVPN_SERVICE="zivpn.service"
ZIVPN_CONFIG="/etc/zivpn/config.json"
ZIVPN_USER_FILE="/etc/zivpn/users.list"
ZIVPN_DOMAIN_FILE="/etc/zivpn/domain.txt"

# ========================
setup_colors() {
    RED=""; GREEN=""; YELLOW=""; CYAN=""; WHITE=""
    MAGENTA=""; MAGENTA_VIF=""; BOLD=""; RESET=""
    if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
        RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"
        MAGENTA="$(tput setaf 5)"; MAGENTA_VIF="$(tput setaf 5; tput bold)"
        CYAN="$(tput setaf 6)"; WHITE="$(tput setaf 7)"
        BOLD="$(tput bold)"; RESET="$(tput sgr0)"
    fi
}

setup_colors

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

# =========
# Calcul dynamique de udp_mem selon la RAM disponible
# =========
get_udp_mem_values() {
    local TOTAL_RAM_KB
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local TOTAL_RAM_MB=$(( TOTAL_RAM_KB / 1024 ))

    # Allouer ~12% de la RAM pour UDP, en pages de 4Ko
    local PAGE_SIZE=4  # Ko par page
    local ALLOC_KB=$(( TOTAL_RAM_KB * 12 / 100 ))
    local MAX_PAGES=$(( ALLOC_KB / PAGE_SIZE ))
    local PRESSURE_PAGES=$(( MAX_PAGES * 3 / 4 ))
    local MIN_PAGES=$(( MAX_PAGES / 4 ))

    # Plancher minimum raisonnable
    [[ $MIN_PAGES -lt 65536 ]] && MIN_PAGES=65536
    [[ $PRESSURE_PAGES -lt 131072 ]] && PRESSURE_PAGES=131072
    [[ $MAX_PAGES -lt 262144 ]] && MAX_PAGES=262144

    echo "${MIN_PAGES} ${PRESSURE_PAGES} ${MAX_PAGES}"
}

# ==========
# Optimisations kernel/réseau adaptées aux réseaux instables
# ==========
apply_network_optimizations() {
    echo "${CYAN}⚙️  Application des optimisations réseau...${RESET}"

    # Charger les modules BBR et FQ
    modprobe tcp_bbr 2>/dev/null || true
    modprobe sch_fq 2>/dev/null || true

    # Calculer udp_mem adapté à la RAM réelle
    read -r UDP_MIN UDP_PRESSURE UDP_MAX <<< "$(get_udp_mem_values)"

    # Supprimer les anciennes entrées pour éviter les doublons
    local KEYS=(
        "net.core.rmem_default" "net.core.wmem_default"
        "net.core.rmem_max" "net.core.wmem_max"
        "net.core.netdev_max_backlog" "net.core.optmem_max"
        "net.core.default_qdisc" "net.ipv4.tcp_congestion_control"
        "net.ipv4.ip_forward" "net.ipv4.udp_mem"
        "fs.file-max" "net.ipv4.tcp_fastopen"
        "net.ipv4.tcp_mtu_probing"
        "net.core.somaxconn" "net.ipv4.tcp_max_syn_backlog"
    )
    for KEY in "${KEYS[@]}"; do
        sed -i "/^${KEY}=/d" /etc/sysctl.conf 2>/dev/null || true
    done

    # Écrire toutes les optimisations
    cat >> /etc/sysctl.conf << SYSEOF

# === ZIVPN High-Speed Optimizations (réseaux instables) ===
# Buffers UDP 64 Mo (adapté réseau mobile instable)
net.core.rmem_default=16777216
net.core.wmem_default=16777216
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.core.optmem_max=16777216
# File descriptor limits
fs.file-max=1000000
# Queue réseau
net.core.netdev_max_backlog=250000
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
# BBR congestion control
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
# IP forwarding
net.ipv4.ip_forward=1
# UDP memory adapté à la RAM réelle (pages 4Ko)
net.ipv4.udp_mem=${UDP_MIN} ${UDP_PRESSURE} ${UDP_MAX}
# TCP Fast Open (client + serveur)
net.ipv4.tcp_fastopen=3
# MTU probing désactivé (évite black hole sur réseaux mobiles qui bloquent ICMP)
net.ipv4.tcp_mtu_probing=0
# === FIN ZIVPN ===
SYSEOF

    # Appliquer immédiatement
    sysctl -p >/dev/null 2>&1 || true

    # QoS: FQ qdisc sur l'interface principale
    local IFACE
    IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -1)
    if [[ -n "$IFACE" ]]; then
        tc qdisc del dev "$IFACE" root 2>/dev/null || true
        tc qdisc add dev "$IFACE" root fq 2>/dev/null || true
        echo "${GREEN}✅ FQ qdisc appliqué sur $IFACE${RESET}"
    fi

    # DSCP Expedited Forwarding (EF/46) sur la plage client 6000:19999
    iptables -t mangle -D OUTPUT     -p udp --sport 6000:19999 -j DSCP --set-dscp-class EF 2>/dev/null || true
    iptables -t mangle -D OUTPUT     -p udp --dport 6000:19999 -j DSCP --set-dscp-class EF 2>/dev/null || true
    iptables -t mangle -D PREROUTING -p udp --dport 6000:19999 -j DSCP --set-dscp-class EF 2>/dev/null || true
    # Nettoyer aussi les anciennes règles sur 5667
    iptables -t mangle -D OUTPUT     -p udp --sport 5667 -j DSCP --set-dscp-class EF 2>/dev/null || true
    iptables -t mangle -D OUTPUT     -p udp --dport 5667 -j DSCP --set-dscp-class EF 2>/dev/null || true
    iptables -t mangle -D PREROUTING -p udp --dport 5667 -j DSCP --set-dscp-class EF 2>/dev/null || true
    # Appliquer
    iptables -t mangle -A OUTPUT     -p udp --sport 6000:19999 -j DSCP --set-dscp-class EF 2>/dev/null || true
    iptables -t mangle -A OUTPUT     -p udp --dport 6000:19999 -j DSCP --set-dscp-class EF 2>/dev/null || true
    iptables -t mangle -A PREROUTING -p udp --dport 6000:19999 -j DSCP --set-dscp-class EF 2>/dev/null || true

    echo "${GREEN}✅ DSCP EF appliqué sur plage 6000:19999${RESET}"
    echo "${GREEN}✅ udp_mem adapté RAM: min=${UDP_MIN} pressure=${UDP_PRESSURE} max=${UDP_MAX} pages${RESET}"
    echo "${GREEN}✅ Optimisations réseau appliquées (BBR + FQ + DSCP + buffers adaptés)${RESET}"
}

# ============
# Installer le watchdog cron (vérifie et redémarre si mort)
# ============
install_watchdog() {
    local WATCHDOG_SCRIPT="/usr/local/bin/zivpn_watchdog.sh"
    cat > "$WATCHDOG_SCRIPT" << 'WEOF'
#!/bin/bash
SERVICE="zivpn.service"
LOG="/var/log/zivpn_watchdog.log"
if ! systemctl is-active --quiet "$SERVICE"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  ZIVPN inactif → redémarrage..." >> "$LOG"
    systemctl restart "$SERVICE"
    sleep 3
    if systemctl is-active --quiet "$SERVICE"; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ ZIVPN redémarré avec succès" >> "$LOG"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Échec redémarrage ZIVPN" >> "$LOG"
    fi
fi
WEOF
    chmod +x "$WATCHDOG_SCRIPT"

    # Ajouter au cron toutes les 3 minutes si pas déjà présent
    if ! crontab -l 2>/dev/null | grep -q "zivpn_watchdog"; then
        (crontab -l 2>/dev/null; echo "*/3 * * * * $WATCHDOG_SCRIPT") | crontab -
        echo "${GREEN}✅ Watchdog cron installé (vérification toutes les 3 min)${RESET}"
    else
        echo "${GREEN}✅ Watchdog cron déjà présent${RESET}"
    fi
}

# ==================
# Config optimisée 
# ==================
write_optimized_config() {
    cat > "$ZIVPN_CONFIG" << 'EOF'
{
  "listen": ":5667",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "zivpn",
  "up_mbps": 100,
  "down_mbps": 100,
  "recv_window_conn": 8388608,
  "recv_window_client": 16777216,
  "disable_mtu_discovery": true,
  "max_conn_client": 4096,
  "exclude_port": [53,5300,4466,36712,20000],
  "auth": {
    "mode": "passwords",
    "config": ["zi"]
  }
}
EOF
}

# ==============
# Service systemd corrigé
# ==============
write_optimized_service() {
    cat > "/etc/systemd/system/$ZIVPN_SERVICE" << EOF
[Unit]
Description=ZIVPN UDP Server (Optimisé réseaux instables)
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=$ZIVPN_BIN server -c $ZIVPN_CONFIG
ExecStartPost=/bin/bash -c "iptables -t nat -C PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || iptables -t nat -A PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667"
ExecStartPost=/bin/bash -c "iptables -C INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || iptables -A INPUT -p udp --dport 5667 -j ACCEPT"
WorkingDirectory=/etc/zivpn
Restart=always
RestartSec=5
StartLimitBurst=0
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
LimitNOFILE=1048576
LimitNPROC=infinity
LimitMEMLOCK=infinity
# Nice=-10 au lieu de CPUSchedulingPolicy=rr (évite le gel système)
Nice=-10
StandardOutput=append:/var/log/zivpn.log
StandardError=append:/var/log/zivpn.log

[Install]
WantedBy=multi-user.target
EOF
}

# ======================
cleanup_expired_users() {
    [[ ! -f "$ZIVPN_USER_FILE" ]] && return 0
    local TODAY
    TODAY=$(date +%Y-%m-%d)
    local TMP
    TMP=$(mktemp)
    awk -F'|' -v today="$TODAY" '$3>=today {print $0}' "$ZIVPN_USER_FILE" > "$TMP" 2>/dev/null || true
    mv "$TMP" "$ZIVPN_USER_FILE"
    chmod 600 "$ZIVPN_USER_FILE"
    update_zivpn_config_passwords
}

update_zivpn_config_passwords() {
    local TODAY
    TODAY=$(date +%Y-%m-%d)
    local PASSWORDS
    PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" 2>/dev/null | sort -u | paste -sd, -)

    if [[ -z "$PASSWORDS" ]]; then
        echo "⚠️  Aucun utilisateur actif - config inchangée"
        return 0
    fi

    local TMP
    TMP=$(mktemp)
    if jq --arg passwords "$PASSWORDS" \
          '.auth.config = ($passwords | split(","))' \
          "$ZIVPN_CONFIG" > "$TMP" 2>/dev/null && \
       jq empty "$TMP" >/dev/null 2>&1; then
        mv "$TMP" "$ZIVPN_CONFIG"
        systemctl restart "$ZIVPN_SERVICE" || true
        return 0
    else
        echo "${RED}❌ JSON invalide → config inchangée${RESET}"
        rm -f "$TMP"
        return 1
    fi
}

print_title() {
  clear
  echo "${CYAN}${BOLD}╔═══════════════════════════════════════╗${RESET}"
  echo "${CYAN}║        ZIVPN CONTROL PANEL v3.1       ║${RESET}"
  echo "${CYAN}║   Optimisé réseaux instables @kighmu  ║${RESET}"
  echo "${CYAN}${BOLD}╚═══════════════════════════════════════╝${RESET}"
  echo
}

show_status_block() {
  echo "${CYAN}-------------- STATUT ZIVPN --------------${RESET}"
  local SVC_FILE_OK SVC_ACTIVE PORT_OK ACTIVE_USERS TODAY BBR_STATUS UPMBPS WATCHDOG_OK
  SVC_FILE_OK=$([[ -f "/etc/systemd/system/$ZIVPN_SERVICE" ]] && echo "✅" || echo "❌")
  SVC_ACTIVE=$(systemctl is-active "$ZIVPN_SERVICE" 2>/dev/null || echo "inactif")
  PORT_OK=$(ss -lunp 2>/dev/null | grep -q ":5667" && echo "✅" || echo "❌")
  BBR_STATUS=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr" && echo "✅ BBR" || echo "⚠️  non-BBR")
  UPMBPS=$(jq -r '.up_mbps // "non défini"' "$ZIVPN_CONFIG" 2>/dev/null || echo "N/A")
  WATCHDOG_OK=$(crontab -l 2>/dev/null | grep -q "zivpn_watchdog" && echo "✅ actif" || echo "❌ absent")
  echo "${WHITE}Service file:${RESET}       $SVC_FILE_OK"
  echo "${WHITE}Service actif:${RESET}      $SVC_ACTIVE"
  echo "${WHITE}Port 5667:${RESET}          $PORT_OK"
  echo "${WHITE}Congestion ctrl:${RESET}    $BBR_STATUS"
  echo "${WHITE}Bande passante:${RESET}     ↑↓ ${UPMBPS} Mbps"
  echo "${WHITE}Watchdog cron:${RESET}      $WATCHDOG_OK"
  if [[ -f "$ZIVPN_USER_FILE" ]]; then
    TODAY=$(date +%Y-%m-%d)
    ACTIVE_USERS=$(awk -F'|' -v today="$TODAY" '$3>=today {count++} END{print count+0}' "$ZIVPN_USER_FILE")
  else
    ACTIVE_USERS=0
  fi
  echo "${CYAN}Utilisateurs actifs:${RESET} $ACTIVE_USERS"
  if [[ "$SVC_FILE_OK" == "✅" ]]; then
    if systemctl is-active --quiet "$ZIVPN_SERVICE" 2>/dev/null; then
      echo "${GREEN}✅ ZIVPN : INSTALLÉ et ACTIF${RESET}"
    else
      echo "⚠️  ZIVPN : INSTALLÉ mais INACTIF"
    fi
  else
    echo "${RED}❌ ZIVPN : NON INSTALLÉ${RESET}"
  fi
  echo "${CYAN}------------------------------------------${RESET}"
  echo
}

# ---------- 1) Installation ----------
install_zivpn() {
  print_title
  echo "[1] INSTALLATION ZIVPN"
  echo

  if zivpn_installed; then
    echo "ZIVPN déjà installé."
    pause; return
  fi

  systemctl stop zivpn 2>/dev/null || true
  systemctl stop ufw 2>/dev/null || true
  ufw disable 2>/dev/null || true
  apt purge ufw -y 2>/dev/null || true
  apt update -y && apt install -y wget curl jq openssl iptables-persistent netfilter-persistent iproute2

  wget -q "https://github.com/kinf744/Kighmu/releases/download/v1.0.0/udp-zivpn-linux-amd64" -O "$ZIVPN_BIN"
  chmod +x "$ZIVPN_BIN"

  mkdir -p /etc/zivpn
  read -rp "Domaine: " DOMAIN; DOMAIN=${DOMAIN:-"zivpn.local"}
  echo "$DOMAIN" > "$ZIVPN_DOMAIN_FILE"

  local CERT="/etc/zivpn/zivpn.crt" KEY="/etc/zivpn/zivpn.key"
  openssl req -x509 -newkey rsa:2048 -keyout "$KEY" -out "$CERT" -nodes -days 3650 -subj "/CN=$DOMAIN"
  chmod 600 "$KEY"; chmod 644 "$CERT"

  # Config optimisée réseaux instables
  write_optimized_config

  # Service systemd corrigé (Nice=-10, ExecStartPost NAT)
  write_optimized_service

  systemctl daemon-reload && systemctl enable "$ZIVPN_SERVICE"

  # Firewall / NAT
  iptables -C INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p udp --dport 5667 -j ACCEPT
  iptables -C INPUT -p udp --dport 6000:19999 -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p udp --dport 6000:19999 -j ACCEPT
  iptables -t nat -C PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || \
    iptables -t nat -A PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667

  netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4

  # Optimisations réseau adaptées
  apply_network_optimizations

  # Watchdog cron
  install_watchdog

  systemctl start "$ZIVPN_SERVICE" || true
  sleep 3

  if systemctl is-active --quiet "$ZIVPN_SERVICE"; then
    local IP
    IP=$(hostname -I | awk '{print $1}')
    echo
    echo "${GREEN}✅ ZIVPN installé et actif !${RESET}"
    echo "📱 Config client:"
    echo "   Serveur         : $IP"
    echo "   Port            : 6000-19999"
    echo "   Password        : zi"
    echo "   Obfs            : zivpn"
    echo "   up/down_mbps    : 100 (adapté réseaux instables)"
    echo "   recv_window_conn: 8388608  (8 Mo)"
    echo "   recv_window_cli : 16777216 (16 Mo)"
    echo "   MTU discovery   : désactivé (stable sur mobile)"
    echo "   Watchdog        : actif (cron toutes les 3 min)"
  else
    echo "❌ ZIVPN ne démarre pas"
    journalctl -u zivpn.service -n 20 --no-pager
  fi
  pause
}

# ---------- 2) Création utilisateur ----------
create_zivpn_user() {
  print_title
  echo "[2] CRÉATION UTILISATEUR ZIVPN"

  if ! systemctl is-active --quiet "$ZIVPN_SERVICE" 2>/dev/null; then
    echo "❌ Service ZIVPN inactif. Lance l'option 1."
    pause; return
  fi

  read -rp "Identifiant (téléphone ou username): " USER_ID
  [[ -z "$USER_ID" ]] && { echo "❌ Identifiant vide"; pause; return; }
  read -rp "Password ZIVPN: " PASS
  [[ -z "$PASS" ]] && { echo "❌ Password vide"; pause; return; }
  read -rp "Durée (jours): " DAYS
  [[ ! "$DAYS" =~ ^[0-9]+$ ]] && { echo "❌ Durée invalide"; pause; return; }

  local EXPIRE TODAY
  EXPIRE=$(date -d "+${DAYS} days" '+%Y-%m-%d')
  TODAY=$(date +%Y-%m-%d)

  local TMP
  TMP=$(mktemp)
  awk -F'|' -v today="$TODAY" '$3>=today {print $0}' "$ZIVPN_USER_FILE" > "$TMP" 2>/dev/null || true
  grep -v "^$USER_ID|" "$TMP" > "${TMP}.2" 2>/dev/null || true
  echo "$USER_ID|$PASS|$EXPIRE" >> "${TMP}.2"
  mv "${TMP}.2" "$ZIVPN_USER_FILE"
  rm -f "$TMP"
  chmod 600 "$ZIVPN_USER_FILE"

  if update_zivpn_config_passwords; then
    local DOMAIN
    DOMAIN=$(cat "$ZIVPN_DOMAIN_FILE" 2>/dev/null || hostname -I | awk '{print $1}')
    echo
    echo "✅ UTILISATEUR CRÉÉ"
    echo "━━━━━━━━━━━━━━━━━━━━━"
    echo "🌐 Domaine  : $DOMAIN"
    echo "🎭 Obfs     : zivpn"
    echo "🔐 Password : $PASS"
    echo "📅 Expire   : $EXPIRE"
    echo "🔌 Port     : 6000-19999"
    echo "━━━━━━━━━━━━━━━━━━━━━"
  fi
  pause
}

# ---------- 3) Suppression utilisateur ----------
delete_zivpn_user() {
  print_title
  echo "[3] SUPPRIMER UTILISATEUR ZIVPN"

  if [[ ! -f "$ZIVPN_USER_FILE" || ! -s "$ZIVPN_USER_FILE" ]]; then
    echo "❌ Aucun utilisateur enregistré."
    pause; return
  fi

  local TODAY
  TODAY=$(date +%Y-%m-%d)
  local TMP
  TMP=$(mktemp)
  awk -F'|' -v today="$TODAY" '$3>=today {print $0}' "$ZIVPN_USER_FILE" > "$TMP" 2>/dev/null || true
  mv "$TMP" "$ZIVPN_USER_FILE"
  chmod 600 "$ZIVPN_USER_FILE"

  mapfile -t USERS < <(sort -t'|' -k3 "$ZIVPN_USER_FILE")
  if [[ ${#USERS[@]} -eq 0 ]]; then
    echo "❌ Aucun utilisateur actif."
    pause; return
  fi

  echo "Utilisateurs actifs:"
  echo "────────────────────────────────────"
  for i in "${!USERS[@]}"; do
    local UNAME EXP
    UNAME=$(echo "${USERS[$i]}" | cut -d'|' -f1)
    EXP=$(echo "${USERS[$i]}" | cut -d'|' -f3)
    echo "$((i+1)). $UNAME | Expire: $EXP"
  done
  echo "────────────────────────────────────"

  read -rp "🔢 Numéro à supprimer (1-${#USERS[@]}): " NUM
  if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#USERS[@]} )); then
    echo "❌ Numéro invalide."
    pause; return
  fi

  local LINE USER_ID
  LINE="${USERS[$((NUM-1))]}"
  USER_ID=$(echo "$LINE" | cut -d'|' -f1 | tr -d '[:space:]')

  grep -v "^$USER_ID|" "$ZIVPN_USER_FILE" > "${ZIVPN_USER_FILE}.tmp" 2>/dev/null || true
  mv "${ZIVPN_USER_FILE}.tmp" "$ZIVPN_USER_FILE"
  chmod 600 "$ZIVPN_USER_FILE"

  update_zivpn_config_passwords
  echo "✅ $USER_ID supprimé"
  pause
}

# ---------- 4) Fix ----------
fix_zivpn() {
  print_title
  echo "[4] FIX ZIVPN (iptables + service + optimisations)"

  systemctl reset-failed zivpn.service 2>/dev/null || true
  update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true

  iptables -C INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p udp --dport 5667 -j ACCEPT
  iptables -C INPUT -p udp --dport 6000:19999 -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p udp --dport 6000:19999 -j ACCEPT
  iptables -t nat -C PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || \
    iptables -t nat -A PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667

  netfilter-persistent save 2>/dev/null || true

  # Réappliquer toutes les optimisations réseau
  apply_network_optimizations

  # Réécrire le service corrigé
  write_optimized_service
  systemctl daemon-reload

  # Mettre à jour config.json si les champs sont obsolètes
  if [[ -f "$ZIVPN_CONFIG" ]]; then
    local NEEDS_UPDATE=0
    # Vérifier si up_mbps est toujours à 1000 (valeur dangereuse)
    local CURRENT_UP
    CURRENT_UP=$(jq -r '.up_mbps // 0' "$ZIVPN_CONFIG" 2>/dev/null)
    [[ "$CURRENT_UP" -gt 100 ]] && NEEDS_UPDATE=1
    jq -e '.recv_window_conn' "$ZIVPN_CONFIG" >/dev/null 2>&1 || NEEDS_UPDATE=1

    if [[ "$NEEDS_UPDATE" -eq 1 ]]; then
      echo "${CYAN}⚙️  Mise à jour config.json (paramètres réseaux instables)...${RESET}"
      local TMP
      TMP=$(mktemp)
      if jq '. + {
        "up_mbps": 100,
        "down_mbps": 100,
        "recv_window_conn": 8388608,
        "recv_window_client": 16777216,
        "disable_mtu_discovery": true,
        "max_conn_client": 4096
      }' "$ZIVPN_CONFIG" > "$TMP" 2>/dev/null && jq empty "$TMP" >/dev/null 2>&1; then
        mv "$TMP" "$ZIVPN_CONFIG"
        echo "${GREEN}✅ config.json mis à jour (100 Mbps + fenêtres 16Mo)${RESET}"
      else
        echo "${RED}❌ Erreur mise à jour config.json${RESET}"
        rm -f "$TMP"
      fi
    fi
  fi

  # Watchdog cron
  install_watchdog

  systemctl restart zivpn.service || true
  sleep 2

  if systemctl is-active --quiet zivpn.service; then
    echo "✅ ZIVPN actif (6000-19999→5667)"
    echo "✅ BBR + buffers adaptés + FQ + DSCP EF réappliqués"
    echo "✅ up/down_mbps: 100 | recv_window: 8Mo/16Mo"
    echo "✅ Nice=-10 (scheduling sûr)"
    echo "✅ Watchdog cron actif"
  else
    echo "❌ ZIVPN toujours inactif - voir: journalctl -u zivpn.service -n 30"
  fi
  pause
}

# ---------- 5) Appliquer optimisations seules ----------
optimize_only() {
  print_title
  echo "[5] APPLIQUER OPTIMISATIONS VITESSE"
  echo
  echo "Cette option applique uniquement les optimisations réseau"
  echo "sans réinstaller ZIVPN (utile si déjà installé)."
  echo

  apply_network_optimizations

  # Mettre à jour la config JSON
  if [[ -f "$ZIVPN_CONFIG" ]]; then
    local NEEDS_UPDATE=0
    local CURRENT_UP
    CURRENT_UP=$(jq -r '.up_mbps // 0' "$ZIVPN_CONFIG" 2>/dev/null)
    [[ "$CURRENT_UP" -gt 100 ]] && NEEDS_UPDATE=1
    jq -e '.recv_window_conn' "$ZIVPN_CONFIG" >/dev/null 2>&1 || NEEDS_UPDATE=1
    local MTU_DISC
    MTU_DISC=$(jq -r '.disable_mtu_discovery // false' "$ZIVPN_CONFIG" 2>/dev/null)
    [[ "$MTU_DISC" == "false" ]] && NEEDS_UPDATE=1

    if [[ "$NEEDS_UPDATE" -eq 1 ]]; then
      echo "${CYAN}⚙️  Mise à jour config.json (paramètres réseaux instables)...${RESET}"
      local TMP
      TMP=$(mktemp)
      if jq '. + {
        "up_mbps": 100,
        "down_mbps": 100,
        "recv_window_conn": 8388608,
        "recv_window_client": 16777216,
        "disable_mtu_discovery": true,
        "max_conn_client": 4096
      }' "$ZIVPN_CONFIG" > "$TMP" 2>/dev/null && jq empty "$TMP" >/dev/null 2>&1; then
        mv "$TMP" "$ZIVPN_CONFIG"
        echo "${GREEN}✅ config.json mis à jour (100 Mbps + 16Mo fenêtres + MTU fixe)${RESET}"
        systemctl restart "$ZIVPN_SERVICE" || true
      else
        echo "${RED}❌ Erreur mise à jour config.json${RESET}"
        rm -f "$TMP"
      fi
    else
      echo "${GREEN}✅ config.json déjà optimisé${RESET}"
    fi
  fi

  # Mettre à jour le service si nécessaire
  if [[ -f "/etc/systemd/system/$ZIVPN_SERVICE" ]]; then
    if ! grep -q "Nice=" "/etc/systemd/system/$ZIVPN_SERVICE" || \
       grep -q "CPUSchedulingPolicy=rr" "/etc/systemd/system/$ZIVPN_SERVICE"; then
      echo "${CYAN}⚙️  Mise à jour service systemd (Nice=-10 / suppression rr)...${RESET}"
      write_optimized_service
      systemctl daemon-reload
      systemctl restart "$ZIVPN_SERVICE" || true
      echo "${GREEN}✅ Service systemd mis à jour${RESET}"
    fi
  fi

  # Watchdog cron
  install_watchdog

  echo
  echo "${GREEN}${BOLD}✅ Toutes les optimisations appliquées (réseaux instables) !${RESET}"
  echo "  • BBR congestion control"
  echo "  • Buffers UDP adaptés à la RAM réelle"
  echo "  • FQ qdisc (priorité paquets)"
  echo "  • DSCP EF sur port 6000-19999"
  echo "  • up_mbps / down_mbps : 100 (réaliste réseau mobile)"
  echo "  • recv_window_conn    : 8 Mo"
  echo "  • recv_window_client  : 16 Mo"
  echo "  • disable_mtu_discovery: true (évite black hole mobile)"
  echo "  • somaxconn / tcp_max_syn_backlog: 65535"
  echo "  • Nice=-10 (priorité haute sans risque de gel)"
  echo "  • ExecStartPost: persistance NAT au reboot"
  echo "  • Watchdog cron: redémarrage auto toutes les 3 min"
  pause
}

# ---------- 6) Désinstallation ----------
uninstall_zivpn() {
  print_title
  echo "[6] DÉSINSTALLATION ZIVPN"
  read -rp "Confirmer ? (o/N): " CONFIRM
  [[ "$CONFIRM" =~ ^[oO]$ ]] || { echo "Annulé"; pause; return; }

  systemctl stop "$ZIVPN_SERVICE" 2>/dev/null || true
  systemctl disable "$ZIVPN_SERVICE" 2>/dev/null || true
  rm -f "/etc/systemd/system/$ZIVPN_SERVICE"
  systemctl daemon-reload

  rm -f "$ZIVPN_BIN"
  rm -f "/usr/local/bin/zivpn_watchdog.sh"
  rm -rf /etc/zivpn

  # Supprimer le watchdog du cron
  crontab -l 2>/dev/null | grep -v "zivpn_watchdog" | crontab - 2>/dev/null || true

  iptables -t nat -D PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || true
  iptables -D INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || true
  iptables -D INPUT -p udp --dport 6000:19999 -j ACCEPT 2>/dev/null || true
  iptables -t mangle -D OUTPUT     -p udp --sport 6000:19999 -j DSCP --set-dscp-class EF 2>/dev/null || true
  iptables -t mangle -D OUTPUT     -p udp --dport 6000:19999 -j DSCP --set-dscp-class EF 2>/dev/null || true
  iptables -t mangle -D PREROUTING -p udp --dport 6000:19999 -j DSCP --set-dscp-class EF 2>/dev/null || true

  netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4

  echo "✅ ZIVPN supprimé (service + binaire + config + watchdog)"
  pause
}

# ---------- MAIN LOOP ----------
check_root

while true; do
  print_title
  show_status_block
  echo "${GREEN}${BOLD}[01]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Installation de ZIVPN${RESET}"
  echo "${GREEN}${BOLD}[02]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Créer un utilisateur UDP-ZIVPN${RESET}"
  echo "${GREEN}${BOLD}[03]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Supprimer utilisateur${RESET}"
  echo "${GREEN}${BOLD}[04]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Fix ZIVPN (reset firewall/NAT + optimisations)${RESET}"
  echo "${GREEN}${BOLD}[05]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Appliquer optimisations vitesse (BBR/buffers/QUIC/DSCP)${RESET}"
  echo "${GREEN}${BOLD}[06]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Désinstaller ZIVPN${RESET}"
  echo "${RED}[00] ➜ Quitter${RESET}"
  echo
  echo -n "${BOLD}${YELLOW} Entrez votre choix [0-6]: ${RESET}"
  read -r CHOIX

  case $CHOIX in
    1) install_zivpn ;;
    2) create_zivpn_user ;;
    3) delete_zivpn_user ;;
    4) fix_zivpn ;;
    5) optimize_only ;;
    6) uninstall_zivpn ;;
    0) exit 0 ;;
    *) echo "${RED}❌ Choix invalide${RESET}"; sleep 1 ;;
  esac
done
