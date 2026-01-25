#!/bin/bash
# zivpn-panel-v2.sh - Aligné sur arivpnstores/udp-zivpn
set -euo pipefail

ZIVPN_BIN="/usr/local/bin/zivpn"
ZIVPN_SERVICE="zivpn.service"
ZIVPN_CONFIG="/etc/zivpn/config.json"
ZIVPN_USER_FILE="/etc/zivpn/users.list"
ZIVPN_DOMAIN_FILE="/etc/zivpn/domain.txt"

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

print_title() {
  clear
  echo "╔═══════════════════════════════════════╗"
  echo "║        ZIVPN CONTROL PANEL v2        ║"
  echo "║     (Compatible arivpnstores)        ║"
  echo "╚═══════════════════════════════════════╝"
  echo
}

show_status_block() {
  echo "------ STATUT ZIVPN (arivpnstores) ------"
  if zivpn_installed; then
    if zivpn_running; then
      echo "✅ ZIVPN : INSTALLÉ et ACTIF"
      echo "   Service: $(systemctl is-active "$ZIVPN_SERVICE")"
      echo "   Port interne: 5667 (DNAT 6000-19999)"
    else
      echo "⚠️  ZIVPN : INSTALLÉ mais INACTIF"
      echo "   $(systemctl is-active "$ZIVPN_SERVICE")"
    fi
  else
    echo "❌ ZIVPN : NON INSTALLÉ"
  fi
  echo "-----------------------------------------"
  echo
}

# ---------- 1) Installation (exactement comme arivpnstores) ----------

install_zivpn() {
  print_title
  echo "[1] INSTALLATION ZIVPN (arivpnstores style)"
  echo

  if zivpn_installed; then
    echo "ZIVPN déjà installé. Utilisez 'Fix ZIVPN' si besoin."
    pause
    return
  fi

  # Reset firewall comme arivpnstores
  systemctl stop "$ZIVPN_SERVICE" >/dev/null 2>&1 || true
  ufw disable >/dev/null 2>&1 || true
  iptables -F; iptables -t nat -F; iptables -t mangle -F

  apt update -y
  apt install -y wget curl jq openssl ufw nftables

  echo "[+] Téléchargement binaire ZIVPN (1.4.9)"
  wget -q "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64" \
    -O "$ZIVPN_BIN"
  chmod +x "$ZIVPN_BIN"

  mkdir -p /etc/zivpn
  touch "$ZIVPN_USER_FILE" "$ZIVPN_DOMAIN_FILE"
  chmod 600 "$ZIVPN_USER_FILE"

  # Domaine pour certificat
  if [[ ! -s "$ZIVPN_DOMAIN_FILE" ]]; then
    read -rp "Domaine (pour cert, ex: zivpn.votredomaine.com) [zivpn.local]: " DOMAIN
    DOMAIN=${DOMAIN:-"zivpn.local"}
    echo "$DOMAIN" > "$ZIVPN_DOMAIN_FILE"
  fi
  DOMAIN=$(cat "$ZIVPN_DOMAIN_FILE")

  # Certificat comme arivpnstores
  CERT="/etc/zivpn/zivpn.crt"
  KEY="/etc/zivpn/zivpn.key"
  openssl req -x509 -newkey rsa:2048 \
    -keyout "$KEY" -out "$CERT" \
    -nodes -days 3650 -subj "/CN=$DOMAIN"

  chmod 600 "$KEY"
  chmod 644 "$CERT"

  # config.json EXACTEMENT comme arivpnstores
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

  # systemd service IDENTIQUE à arivpnstores
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
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$ZIVPN_SERVICE"

  # Firewall/NAT EXACT comme arivpnstores (UFW + iptables)
  cat > /etc/ufw/before.rules << 'EOF'
# ZIVPN UDP NAT (6000-19999 -> 5667)
*nat
:PREROUTING ACCEPT [0:0]
-A PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667
COMMIT

# ZIVPN UDP INPUT
*filter
:ufw-before-input - [0:0]
-A ufw-before-input -p udp --dport 5667 -j ACCEPT
-A ufw-before-input -p udp --dport 6000:19999 -j ACCEPT
COMMIT
EOF

  ufw --force enable
  ufw allow 22,80,443,53

  # sysctl pour UDP buffers
  echo 'net.core.rmem_max=16777216' > /etc/sysctl.d/99-zivpn.conf
  echo 'net.core.wmem_max=16777216' >> /etc/sysctl.d/99-zivpn.conf
  sysctl --system

  systemctl start "$ZIVPN_SERVICE"
  sleep 3

  if zivpn_running; then
    echo "✅ ZIVPN installé (arivpnstores compatible) !"
    echo "   Password par défaut: zi"
    echo "   Ports: 6000-19999 (redirigés vers 5667)"
    echo "   Config client ZIVPN:"
    echo "   Host: $(hostname -I | awk '{print $1}')"
    echo "   Password: zi"
  else
    echo "❌ Service ne démarre pas. Logs: journalctl -u $ZIVPN_SERVICE"
  fi
  pause
}

# ---------- 2) Création utilisateur ----------

create_zivpn_user() {
  print_title
  echo "[2] CRÉATION UTILISATEUR ZIVPN"
  
  if ! zivpn_installed; then
    echo "❌ Installez ZIVPN d'abord (option 1)"
    pause; return
  fi

  echo "Format: téléphone|password|expiration"
  echo "Exemple: 22997000000|MonPass123|2026-02-01"
  echo

  read -rp "Téléphone: " PHONE
  read -rp "Password ZIVPN: " PASS
  read -rp "Durée (jours): " DAYS

  EXPIRE=$(date -d "+${DAYS} days" '+%Y-%m-%d')
  
  # Ajout/remplacement
  tmp=$(mktemp)
  grep -v "^$PHONE|" "$ZIVPN_USER_FILE" > "$tmp" 2>/dev/null || true
  echo "$PHONE|$PASS|$EXPIRE" >> "$tmp"
  mv "$tmp" "$ZIVPN_USER_FILE"
  chmod 600 "$ZIVPN_USER_FILE"

  # Update config.json avec TOUS les passwords valides
  TODAY=$(date +%Y-%m-%d)
  PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" | \
              sort -u | jq -R . | jq -s .)

  jq --argjson arr "$PASSWORDS" '.auth.config = $arr' "$ZIVPN_CONFIG" > /tmp/config.json
  mv /tmp/config.json "$ZIVPN_CONFIG"

  systemctl restart "$ZIVPN_SERVICE"

  IP=$(hostname -I | awk '{print $1}')
  DOMAIN=$(cat "$ZIVPN_DOMAIN_FILE" 2>/dev/null || echo "$IP")

  echo
  echo "✅ UTILISATEUR AJOUTÉ"
  echo "━━━━━━━━━━━━━━━━━━━━━"
  echo "📱 Téléphone : $PHONE"
  echo "🔑 Password  : $PASS"
  echo "📅 Expire    : $EXPIRE"
  echo
  echo "📲 CONFIG ZIVPN CLIENT:"
  echo "   Host/IP: $IP"
  echo "   Password: $PASS"
  echo "   Port: 6000-19999 (auto)"
  echo "   Domaine: $DOMAIN"
  echo
  echo "💡 Dans ZIVPN → UDP Tunnel → udp server: $IP, password: $PASS"
  pause
}

# ---------- 3) Suppression utilisateur ----------

delete_zivpn_user() {
  print_title
  echo "[3] SUPPRIMER UTILISATEUR"
  
  if ! zivpn_installed || [[ ! -s "$ZIVPN_USER_FILE" ]]; then
    echo "❌ Aucun utilisateur ou ZIVPN non installé"
    pause; return
  fi

  echo "Utilisateurs actifs:"
  echo "────────────────────"
  nl -w2 -s'. ' <(awk -F'|' '{print $1" | "$2" | "$3}' "$ZIVPN_USER_FILE" | sort -k3)
  echo
  read -rp "Téléphone à supprimer: " PHONE

  tmp=$(mktemp)
  grep -v "^$PHONE|" "$ZIVPN_USER_FILE" > "$tmp"
  mv "$tmp" "$ZIVPN_USER_FILE"

  # Refresh config
  TODAY=$(date +%Y-%m-%d)
  PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" | \
              sort -u | jq -R . | jq -s .)

  jq --argjson arr "$PASSWORDS" '.auth.config = $arr' "$ZIVPN_CONFIG" > /tmp/config.json
  mv /tmp/config.json "$ZIVPN_CONFIG"

  systemctl restart "$ZIVPN_SERVICE"
  echo "✅ $PHONE supprimé et config mise à jour"
  pause
}

# ---------- 4) Fix (comme fix-zivpn.sh d'arivpnstores) ----------

fix_zivpn() {
  print_title
  echo "[4] FIX ZIVPN (arivpnstores style)"
  
  if ! zivpn_installed; then
    echo "❌ ZIVPN non installé. Option 1 d'abord."
    pause; return
  fi

  echo "[+] Reset firewall + NAT (UFW/iptables)"
  ufw disable >/dev/null 2>&1 || true
  iptables -F; iptables -t nat -F; iptables -t mangle -F

  systemctl restart "$ZIVPN_SERVICE"
  ufw --force enable >/dev/null 2>&1
  sysctl --system >/dev/null 2>&1

  if zivpn_running; then
    echo "✅ ZIVPN fixé et actif !"
    echo "   Passwords: $(jq -r '.auth.config[]' "$ZIVPN_CONFIG" | tr '
' ' ')"
  else
    echo "❌ Toujours HS. Logs: journalctl -u $ZIVPN_SERVICE -n 20"
  fi
  pause
}

# ---------- 5) Désinstallation ----------

uninstall_zivpn() {
  print_title
  echo "[5] DÉSINSTALLATION"
  read -rp "Confirmer ? (o/N): " CONFIRM
  [[ "$CONFIRM" =~ ^[oO]$ ]] || { echo "Annulé"; pause; return; }

  systemctl stop "$ZIVPN_SERVICE" || true
  systemctl disable "$ZIVPN_SERVICE" || true
  rm -f "/etc/systemd/system/$ZIVPN_SERVICE"
  systemctl daemon-reload

  rm -f "$ZIVPN_BIN" /etc/zivpn/*
  ufw delete 6000:19999/udp >/dev/null 2>&1 || true
  iptables -t nat -F PREROUTING >/dev/null 2>&1 || true

  echo "✅ ZIVPN supprimé"
  pause
}

# ---------- MAIN LOOP ----------

check_root

while true; do
  print_title
  show_status_block
  
  echo "1) Installer ZIVPN (arivpnstores)"
  echo "2) Créer utilisateur ZIVPN" 
  echo "3) Supprimer utilisateur"
  echo "4) Fix ZIVPN (reset firewall/NAT)"
  echo "5) Désinstaller ZIVPN"
  echo "0) Quitter"
  echo
  read -rp "Choix: " CHOIX

  case $CHOIX in
    1) install_zivpn ;;
    2) create_zivpn_user ;;
    3) delete_zivpn_user ;;
    4) fix_zivpn ;;
    5) uninstall_zivpn ;;
    0) exit 0 ;;
    *) echo "❌ Choix invalide"; sleep 1 ;;
  esac
done
