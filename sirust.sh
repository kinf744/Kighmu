#!/bin/bash
# sirust.sh - Aligné sur arivpnstores/udp-zivpn
set -euo pipefail

ZIVPN_BIN="/usr/local/bin/zivpn"
ZIVPN_SERVICE="zivpn.service"
ZIVPN_CONFIG="/etc/zivpn/config.json"
ZIVPN_USER_FILE="/etc/zivpn/users.list"
ZIVPN_DOMAIN_FILE="/etc/zivpn/domain.txt"

# ==========================================================
# 🎨 COULEURS PRO STYLE KIGHMU (PORTABLE)
# ==========================================================
setup_colors() {
    RED=""
    GREEN=""
    YELLOW=""
    CYAN=""
    WHITE=""
    MAGENTA=""
    MAGENTA_VIF=""
    BOLD=""
    RESET=""

    if [ -t 1 ]; then
        if [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
            RED="$(tput setaf 1)"
            GREEN="$(tput setaf 2)"
            YELLOW="$(tput setaf 3)"
            MAGENTA="$(tput setaf 5)"
            CYAN="$(tput setaf 6)"
            WHITE="$(tput setaf 7)"
            MAGENTA_VIF="$(tput setaf 5; tput bold)"
            BOLD="$(tput bold)"
            RESET="$(tput sgr0)"
        fi
    fi
}

setup_colors

# ---------- Fonctions utilitaires ----------

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

cleanup_expired_users() {
    TODAY=$(date +%Y-%m-%d)
    tmp=$(mktemp)
    awk -F'|' -v today="$TODAY" '$3>=today {print $0}' "$ZIVPN_USER_FILE" > "$tmp" || true
    mv "$tmp" "$ZIVPN_USER_FILE"
    chmod 600 "$ZIVPN_USER_FILE"

    PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" | sort -u | paste -sd, -)
    jq --arg passwords "$PASSWORDS" '.auth.config = ($passwords | split(","))' "$ZIVPN_CONFIG" > /tmp/config.json
    mv /tmp/config.json "$ZIVPN_CONFIG"
    systemctl restart "$ZIVPN_SERVICE"
}

print_title() {
  clear
  echo "${CYAN}${BOLD}╔═══════════════════════════════════════╗${RESET}"
  echo "${CYAN}║        ZIVPN CONTROL PANEL v2         ║${RESET}"
  echo "${CYAN}║     (Compatible @kighmu 🇨🇲)           ║${RESET}"
  echo "${CYAN}${BOLD}╚═══════════════════════════════════════╝${RESET}"
  echo
}

show_status_block() {
  echo "${CYAN}-------------- STATUT ZIVPN --------------${RESET}"
  
  SVC_FILE_OK=$([[ -f "/etc/systemd/system/$ZIVPN_SERVICE" ]] && echo "✅" || echo "❌")
  SVC_ACTIVE=$(systemctl is-active "$ZIVPN_SERVICE" 2>/dev/null || echo "N/A")
  
  # ✅ FIX UDP OPTIMAL (comme tes logs le confirment)
  PORT_OK=$(ss -lunp 2>/dev/null | grep -q ":5667" && echo "✅" || echo "❌")
  
  echo "${WHITE}Service file:${RESET} $SVC_FILE_OK"
  echo "${WHITE}Service actif:${RESET} $SVC_ACTIVE"
  echo "${WHITE}Port 5667:${RESET} $PORT_OK"

  # ----- NOUVEAU : nombre d'utilisateurs actifs -----
  if [[ -f "$ZIVPN_USER_FILE" ]]; then
    TODAY=$(date +%Y-%m-%d)
    ACTIVE_USERS=$(awk -F'|' -v today="$TODAY" '$3>=today {count++} END{print count+0}' "$ZIVPN_USER_FILE")
  else
    ACTIVE_USERS=0
  fi
  echo "${CYAN}Utilisateurs Créé:${RESET} $ACTIVE_USERS"

  # ----- Affichage général -----
  if [[ "$SVC_FILE_OK" == "✅" ]]; then
    if systemctl is-active --quiet "$ZIVPN_SERVICE" 2>/dev/null; then
      echo "${GREEN}✅ ZIVPN : INSTALLÉ et ACTIF${RESET}"
      echo "   Port interne: 5667"
    else
      echo "⚠️  ZIVPN : INSTALLÉ mais INACTIF"
    fi
  else
    echo "${RED}❌ ZIVPN : NON INSTALLÉ${RESET}"
  fi
  echo "${CYAN}------------------------------------------${RESET}"
  echo
}

# ---------- 1) Installation (exactement comme arivpnstores) ----------

install_zivpn() {
  print_title
  echo "[1] INSTALLATION ZIVPN (NO CONFLIT UFW)"
  echo

  if zivpn_installed; then
    echo "ZIVPN déjà installé."
    pause
    return
  fi

  # Clean slate + PURGE UFW
  systemctl stop zivpn >/dev/null 2>&1 || true
  systemctl stop ufw >/dev/null 2>&1 || true
  ufw disable >/dev/null 2>&1 || true
  apt purge ufw -y >/dev/null 2>&1 || true
  
  # RESET iptables propre
  # iptables -F; iptables -t nat -F; iptables -t mangle -F 2>/dev/null || true

  # ✅ PAQUETS SANS CONFLIT UFW
  apt update -y && apt install -y wget curl jq openssl iptables-persistent netfilter-persistent

  # Binaire + cert
  wget -q "https://github.com/kinf744/Kighmu/releases/download/v1.0.0/udp-zivpn-linux-amd64" -O "$ZIVPN_BIN"
  chmod +x "$ZIVPN_BIN"
  
  mkdir -p /etc/zivpn
  read -rp "Domaine: " DOMAIN; DOMAIN=${DOMAIN:-"zivpn.local"}
  echo "$DOMAIN" > "$ZIVPN_DOMAIN_FILE"
  
  CERT="/etc/zivpn/zivpn.crt"; KEY="/etc/zivpn/zivpn.key"
  openssl req -x509 -newkey rsa:2048 -keyout "$KEY" -out "$CERT" -nodes -days 3650 -subj "/CN=$DOMAIN"
  chmod 600 "$KEY"; chmod 644 "$CERT"

  # config.json
  cat > "$ZIVPN_CONFIG" << 'EOF'
{
  "listen": ":5667",
  "exclude_port": [53,5300,4466,36712,20000],
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": ["zi"]
  }
}
EOF

  # systemd service
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
StandardOutput=append:/var/log/zivpn.log
StandardError=append:/var/log/zivpn.log

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload && systemctl enable "$ZIVPN_SERVICE"

  # ✅ IPTABLES INTELLIGENT (pas de flush !)
  iptables -C INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || \
  iptables -A INPUT -p udp --dport 5667 -j ACCEPT

  iptables -C INPUT -p udp --dport 6000:19999 -j ACCEPT 2>/dev/null || \
  iptables -A INPUT -p udp --dport 6000:19999 -j ACCEPT

  iptables -t nat -C PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || \
  iptables -t nat -A PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667

  netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4
  
  # Optimisations réseau
  sysctl -w net.core.rmem_max=16777216
  sysctl -w net.core.wmem_max=16777216
  echo "net.core.rmem_max=16777216" >> /etc/sysctl.conf
  echo "net.core.wmem_max=16777216" >> /etc/sysctl.conf

  systemctl start "$ZIVPN_SERVICE"
  
  # VÉRIFICATION FINALE
  sleep 3
  if systemctl is-active --quiet "$ZIVPN_SERVICE"; then
    IP=$(hostname -I | awk '{print $1}')
    echo "✅ ZIVPN installé et actif !"
    echo "📱 Config ZIVPN App:"
    echo "   udp server: $IP"
    echo "   Password: zi"
  else
    echo "❌ ZIVPN ne démarre pas → journalctl -u zivpn.service"
  fi
  
  pause
}

# ---------- 2) Création utilisateur ----------

create_zivpn_user() {
    print_title
    echo "[2] CRÉATION UTILISATEUR ZIVPN"

    if ! systemctl is-active --quiet "$ZIVPN_SERVICE"; then
        echo "❌ Service ZIVPN inactif ou non installé."
        pause
        return
    fi

    # --- Entrée utilisateur ---
    read -rp "Identifiant (téléphone ou username): " USER_ID
    read -rp "Password ZIVPN: " PASS
    read -rp "Durée (jours): " DAYS
    EXPIRE=$(date -d "+${DAYS} days" '+%Y-%m-%d')

    # --- Nettoyage utilisateurs expirés ---
    TODAY=$(date +%Y-%m-%d)
    tmp=$(mktemp)
    awk -F'|' -v today="$TODAY" '$3>=today {print $0}' "$ZIVPN_USER_FILE" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$ZIVPN_USER_FILE"

    # --- Suppression éventuelle doublon USER_ID ---
    tmp=$(mktemp)
    grep -v "^$USER_ID|" "$ZIVPN_USER_FILE" > "$tmp" 2>/dev/null || true
    echo "$USER_ID|$PASS|$EXPIRE" >> "$tmp"
    mv "$tmp" "$ZIVPN_USER_FILE"
    chmod 600 "$ZIVPN_USER_FILE"

    # --- Mise à jour auth.config dans config.json ---
    PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" | sort -u | paste -sd, -)
    
    if jq --arg passwords "$PASSWORDS" '.auth.config = ($passwords | split(","))' "$ZIVPN_CONFIG" > /tmp/config.json 2>/dev/null &&
       jq empty /tmp/config.json >/dev/null 2>&1; then
        mv /tmp/config.json "$ZIVPN_CONFIG"
        systemctl restart "$ZIVPN_SERVICE"

        DOMAIN=$(cat "$ZIVPN_DOMAIN_FILE" 2>/dev/null || hostname -I | awk '{print $1}')

        echo
        echo "✅ UTILISATEUR CRÉÉ"
        echo "━━━━━━━━━━━━━━━━━━━━━"
        echo "🌐 Domaine  : $DOMAIN"
        echo "🎭 Obfs    : zivpn"
        echo "🔐 Password: $PASS"
        echo "📅 Expire  : $EXPIRE"
        echo "🔌 Port    : 5667"
        echo "━━━━━━━━━━━━━━━━━━━━━"
    else
        echo "❌ JSON invalide → rollback"
        rm -f /tmp/config.json
    fi

    pause
}

# ---------- 3) Suppression utilisateur ----------

delete_zivpn_user() {
  print_title
  echo "[3] SUPPRIMER UTILISATEUR ZIVPN"

  if [[ ! -f "$ZIVPN_USER_FILE" || ! -s "$ZIVPN_USER_FILE" ]]; then
    echo "❌ Aucun utilisateur enregistré."
    pause
    return
  fi

  # --- Nettoyage comptes expirés avant affichage ---
  TODAY=$(date +%Y-%m-%d)
  TMP_FILE=$(mktemp)
  awk -F'|' -v today="$TODAY" '$3>=today {print $0}' "$ZIVPN_USER_FILE" > "$TMP_FILE" || true
  mv "$TMP_FILE" "$ZIVPN_USER_FILE"
  chmod 600 "$ZIVPN_USER_FILE"

  # --- Lire la liste réelle des utilisateurs actifs ---
  mapfile -t USERS < <(sort -t'|' -k3 "$ZIVPN_USER_FILE")
  if [[ ${#USERS[@]} -eq 0 ]]; then
    echo "❌ Aucun utilisateur actif trouvé."
    pause
    return
  fi

  echo "Utilisateurs actifs (sélectionnez NUMÉRO):"
  echo "────────────────────────────────────"
  for i in "${!USERS[@]}"; do
    USER_ID=$(echo "${USERS[$i]}" | cut -d'|' -f1)
    EXP=$(echo "${USERS[$i]}" | cut -d'|' -f3)
    echo "$((i+1)). $USER_ID | Expire: $EXP"
  done
  echo "────────────────────────────────────"

  read -rp "🔢 Numéro à supprimer (1-${#USERS[@]}): " NUM
  if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#USERS[@]} )); then
    echo "❌ Numéro invalide."
    pause
    return
  fi

  # --- Extraction de l'identifiant réel ---
  LINE="${USERS[$((NUM-1))]}"
  USER_ID=$(echo "$LINE" | cut -d'|' -f1 | tr -d '[:space:]')
  echo "🗑️ Suppression de $USER_ID..."

  # --- Supprimer la ligne correspondante dans users.list ---
  grep -v "^$USER_ID|" "$ZIVPN_USER_FILE" > "${ZIVPN_USER_FILE}.tmp" || true
  mv "${ZIVPN_USER_FILE}.tmp" "$ZIVPN_USER_FILE"
  chmod 600 "$ZIVPN_USER_FILE"

  # --- Mise à jour config.json avec mots de passe encore valides ---
  PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" | sort -u | paste -sd, -)
  if jq --arg passwords "$PASSWORDS" '.auth.config = ($passwords | split(","))' "$ZIVPN_CONFIG" > /tmp/config.json 2>/dev/null &&
     jq empty /tmp/config.json >/dev/null 2>&1; then
    mv /tmp/config.json "$ZIVPN_CONFIG"
    systemctl restart "$ZIVPN_SERVICE"
    echo "✅ $USER_ID (n°$NUM) supprimé et ZIVPN mis à jour"
  else
    echo "⚠️ Config ZIVPN inchangée (sécurité)"
    rm -f /tmp/config.json
  fi

  pause
}

# ---------- 4) Fix (comme fix-zivpn.sh) ----------

fix_zivpn() {
  print_title
  echo "[4] IPTABLES ZIVPN (Hysteria préservé)"
  
  # Force iptables legacy
  update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
  
  # ✅ IPTABLES INTELLIGENT (comme install)
  iptables -C INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p udp --dport 5667 -j ACCEPT
  
  iptables -C INPUT -p udp --dport 36712 -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p udp --dport 36712 -j ACCEPT
  
  iptables -C INPUT -p udp --dport 6000:19999 -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p udp --dport 6000:19999 -j ACCEPT
  
  iptables -t nat -C PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || \
    iptables -t nat -A PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667
  
  netfilter-persistent save 2>/dev/null || true
  systemctl restart zivpn.service
  
  echo "✅ ZIVPN fixé (6000-19999→5667)"
  echo "   ✅ Hysteria PRÉSERVÉ !"
}

# ---------- 5) Désinstallation ----------

uninstall_zivpn() {
  print_title
  echo "[5] DÉSINSTALLATION ZIVPN (SAUF autres tunnels)"
  read -rp "Confirmer ? (o/N): " CONFIRM
  [[ "$CONFIRM" =~ ^[oO]$ ]] || { echo "Annulé"; pause; return; }

  # 1) Service seulement
  systemctl stop "$ZIVPN_SERVICE" 2>/dev/null || true
  systemctl disable "$ZIVPN_SERVICE" 2>/dev/null || true
  rm -f "/etc/systemd/system/$ZIVPN_SERVICE"
  systemctl daemon-reload

  # 2) Fichiers seulement
  rm -f "$ZIVPN_BIN"
  rm -rf /etc/zivpn

  # 3) IPTABLES ZIVPN UNIQUEMENT (règles spécifiques -C)
  iptables -t nat -D PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || true
  iptables -D INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || true
  iptables -D INPUT -p udp --dport 6000:19999 -j ACCEPT 2>/dev/null || true

  # ✅ SAUVEGARDE iptables (RESTORE autres tunnels)
  netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4

  echo "✅ ZIVPN supprimé SANS toucher Hysteria/SlowDNS"
  echo "   Vérifiez: iptables -t nat -L PREROUTING -n"
  pause
}

# ---------- MAIN LOOP ----------

check_root

while true; do
  print_title
  show_status_block
  
  echo "${GREEN}${BOLD}[01]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Installation de ZIVPN${RESET}"
  echo "${GREEN}${BOLD}[02]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Créer un utilisateur ZIVPN${RESET}" 
  echo "${GREEN}${BOLD}[03]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Supprimer utilisateur${RESET}"
  echo "${GREEN}${BOLD}[04]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Fix ZIVPN (reset firewall/NAT)${RESET}"
  echo "${GREEN}${BOLD}[05]${RESET} ${BOLD}${MAGENTA}➜${RESET} ${YELLOW}Désinstaller ZIVPN${RESET}"
  echo "${RED}[00] ➜ Quitter${RESET}"
  echo
  echo -n "${BOLD}${YELLOW} Entrez votre choix [1-5]: ${RESET}"
  read -r CHOIX

  case $CHOIX in
    1) install_zivpn ;;
    2) create_zivpn_user ;;
    3) delete_zivpn_user ;;
    4) fix_zivpn ;;
    5) uninstall_zivpn ;;
    0) exit 0 ;;
    *) echo "${RED}❌ Choix invalide${RESET}"; sleep 1 ;;
  esac
done
