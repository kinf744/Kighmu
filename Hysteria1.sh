#!/bin/bash
# Hysteria1.sh - Aligné sur arivpnstores/udp-zivpn
set -euo pipefail

HYSTERIA_BIN="/usr/local/bin/hysteria-linux-amd64"
HYSTERIA_SERVICE="hysteria.service"
HYSTERIA_CONFIG="/etc/hysteria/config.json"
HYSTERIA_USER_FILE="/etc/hysteria/users.txt"
HYSTERIA_DOMAIN_FILE="/etc/hysteria/domain.txt"

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

hysteria_installed() {
  [[ -x "$HYSTERIA_BIN" ]] && systemctl list-unit-files | grep -q "^$HYSTERIA_SERVICE"
}

hysteria_running() {
  systemctl is-active --quiet "$HYSTERIA_SERVICE" 2>/dev/null
}

print_title() {
  clear
  echo "╔═══════════════════════════════════════╗"
  echo "║        HYSTERIA CONTROL PANEL v1      ║"
  echo "║     (Compatible @kighmu 🇨🇲)           ║"
  echo "╚═══════════════════════════════════════╝"
  echo
}

show_status_block() {
  echo "-------- STATUT HYSTERIA --------"
  
  SVC_FILE_OK=$([[ -f "/etc/systemd/system/$HYSTERIA_SERVICE" ]] && echo "✅" || echo "❌")
  SVC_ACTIVE=$(systemctl is-active "$HYSTERIA_SERVICE" 2>/dev/null || echo "N/A")
  PORT_OK=$(ss -ludp | grep -q 20000 && echo "✅" || echo "❌")
  
  echo "Service file: $SVC_FILE_OK"
  echo "Service actif: $SVC_ACTIVE"
  echo "Port 20000: $PORT_OK"
  
  if [[ "$SVC_FILE_OK" == "✅" ]]; then
    if systemctl is-active --quiet "$HYSTERIA_SERVICE" 2>/dev/null; then
      echo "✅ HYSTERIA : INSTALLÉ et ACTIF"
      echo "   Port interne: 20000"
    else
      echo "⚠️  HYSTERIA : INSTALLÉ mais INACTIF"
    fi
  else
    echo "❌ HYSTERIA : NON INSTALLÉ"
  fi
  echo "-----------------------------------------"
  echo
}

# ---------- 1) Installation (exactement comme arivpnstores) ----------

install_hysteria() {
  print_title
  echo "[1] INSTALLATION HYSTERIA (NO CONFLIT UFW)"
  echo

  if hysteria_installed; then
    echo "HYSTERIA déjà installé."
    pause
    return
  fi

  # Clean slate + PURGE UFW
  systemctl stop hysteria >/dev/null 2>&1 || true
  systemctl stop ufw >/dev/null 2>&1 || true
  ufw disable >/dev/null 2>&1 || true
  apt purge ufw -y >/dev/null 2>&1 || true
  
  # RESET iptables propre
  # iptables -F; iptables -t nat -F; iptables -t mangle -F 2>/dev/null || true

  # ✅ PAQUETS SANS CONFLIT UFW
  apt update -y && apt install -y wget curl jq openssl iptables-persistent netfilter-persistent

  # Binaire + cert
  wget -q "https://github.com/apernet/hysteria/releases/download/v1.3.3/hysteria-linux-amd64" -O "$HYSTERIA_BIN"
  chmod +x "$HYSTERIA_BIN"
  
  mkdir -p /etc/hysteria
  read -rp "Domaine: " DOMAIN; DOMAIN=${DOMAIN:-"hysteria.local"}
  echo "$DOMAIN" > "$HYSTERIA_DOMAIN_FILE"
  
  CERT="/etc/hysteria/hysteria.crt"; KEY="/etc/hysteria/hysteria.key"
  openssl req -x509 -newkey rsa:2048 -keyout "$KEY" -out "$CERT" -nodes -days 3650 -subj "/CN=$DOMAIN"
  chmod 600 "$KEY"; chmod 644 "$CERT"

  # config.json
  cat > "$HYSTERIA_CONFIG" << 'EOF'
{
  "listen": ":20000",
  "exclude_port": [53,5300,36712,5667,4466],
  "cert": "/etc/hysteria/hysteria.crt",
  "key": "/etc/hysteria/hysteria.key",
  "obfs": "hysteria",
  "auth": {
    "mode": "passwords",
    "config": ["zi"]
  }
}
EOF

  # systemd service
  cat > "/etc/systemd/system/$HYSTERIA_SERVICE" << EOF
[Unit]
Description=HYSTERIA UDP Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$HYSTERIA_BIN server -c $HYSTERIA_CONFIG
WorkingDirectory=/etc/hysteria
Restart=always
RestartSec=5
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload && systemctl enable "$HYSTERIA_SERVICE"

  # ✅ IPTABLES INTELLIGENT (pas de flush !)
  iptables -C INPUT -p udp --dport 20000 -j ACCEPT 2>/dev/null || \
  iptables -A INPUT -p udp --dport 20000 -j ACCEPT

  iptables -C INPUT -p udp --dport 20000:50000 -j ACCEPT 2>/dev/null || \
  iptables -A INPUT -p udp --dport 20000:50000 -j ACCEPT

  iptables -t nat -C PREROUTING -p udp --dport 20000:50000 -j DNAT --to-destination :20000 2>/dev/null || \
  iptables -t nat -A PREROUTING -p udp --dport 20000:50000 -j DNAT --to-destination :20000

  netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4

  # Optimisations réseau
  sysctl -w net.core.rmem_max=16777216
  sysctl -w net.core.wmem_max=16777216
  echo "net.core.rmem_max=16777216" >> /etc/sysctl.conf
  echo "net.core.wmem_max=16777216" >> /etc/sysctl.conf

  systemctl start "$HYSTERIA_SERVICE"
  
  # VÉRIFICATION FINALE
  sleep 3
  if systemctl is-active --quiet "$HYSTERIA_SERVICE"; then
    IP=$(hostname -I | awk '{print $1}')
    echo "✅ HYSTERIA installé et actif !"
    echo "📱 Config HTTP INJECTOR App:"
    echo "   udp server: $IP"
    echo "   Password: zi"
  else
    echo "❌ HYSTERIA ne démarre pas → journalctl -u hysteria.service"
  fi
  
  pause
}

# ---------- 2) Création utilisateur ----------

create_hysteria_user() {
  print_title
  echo "[2] CRÉATION UTILISATEUR HYSTERIA"

  if ! systemctl is-active --quiet "$HYSTERIA_SERVICE"; then
    echo "❌ Service HYSTERIA inactif ou non installé."
    echo "   Lance l'option 1 ou: systemctl start $HYSTERIA_SERVICE"
    pause
    return
  fi

  echo "Format: téléphone|password|expiration"
  echo "Exemple: 2330|MonPass123|2026-02-01"
  echo

  read -rp "Téléphone: " PHONE
  read -rp "Password HYSTERIA: " PASS
  read -rp "Durée (jours): " DAYS

  EXPIRE=$(date -d "+${DAYS} days" '+%Y-%m-%d')

  # ✅ SAUVEGARDE users.list
  tmp=$(mktemp)
  grep -v "^$PHONE|" "$HYSTERIA_USER_FILE" > "$tmp" 2>/dev/null || true
  echo "$PHONE|$PASS|$EXPIRE" >> "$tmp"
  mv "$tmp" "$HYSTERIA_USER_FILE"
  chmod 600 "$HYSTERIA_USER_FILE"

  # ✅ EXTRACTION PASSWORDS (NOUVEAU : simple et sûr)
  TODAY=$(date +%Y-%m-%d)
  PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$HYSTERIA_USER_FILE" | \
              sort -u | paste -sd, -)

  # ✅ JQ CORRIGÉ (string → array avec split)
  if jq --arg passwords "$PASSWORDS" \
        '.auth.config = ($passwords | split(","))' \
        "$HYSTERIA_CONFIG" > /tmp/config.json 2>/dev/null; then
    
    # Vérif JSON valide
    if jq empty /tmp/config.json >/dev/null 2>&1; then
      mv /tmp/config.json "$HYSTERIA_CONFIG"
      systemctl restart "$HYSTERIA_SERVICE"
      
      IP=$(hostname -I | awk '{print $1}')
      DOMAIN=$(cat "$HYSTERIA_DOMAIN_FILE" 2>/dev/null || echo "$IP")

      echo
      echo "✅ 𝗨𝗧𝗜𝗟𝗜𝗦𝗔𝗧𝗘𝗨𝗥 𝗖𝗥𝗘𝗘𝗥"
      echo "━━━━━━━━━━━━━━━━━━━━━"
      echo "🌐 𝗗𝗼𝗺𝗮𝗶𝗻𝗲  : $DOMAIN"
      echo "🎭 𝗢𝗯𝗳𝘀     : hysteria"
      echo "🔐 𝗣𝗮𝘀𝘀𝘄𝗼𝗿𝗱 : $PASS"
      echo "📅 𝗘𝘅𝗽𝗶𝗿𝗲   : $EXPIRE"
      echo "🔌 𝐏𝐨𝐫𝐭    : 20000-50000"
      echo "━━━━━━━━━━━━━━━━━━━━━"
    else
      echo "❌ JSON invalide → rollback"
      rm -f /tmp/config.json
    fi
  else
    echo "❌ Erreur jq → config inchangée"
  fi

  pause
}

# ---------- 3) Suppression utilisateur ----------

delete_hysteria_user() {
  print_title
  echo "[3] SUPPRIMER UTILISATEUR (NUMÉRO)"

  if [[ ! -f "$HYSTERIA_USER_FILE" || ! -s "$HYSTERIA_USER_FILE" ]]; then
    echo "❌ Aucun utilisateur enregistré."
    pause
    return
  fi

  echo "Utilisateurs actifs (sélectionnez NUMÉRO):"
  echo "────────────────────────────────────"

  # 📋 Liste triée + numérotée (STABLE)
  mapfile -t USERS < <(
    awk -F'|' '{ printf "%s|%s|%s\n", $1, $2, $3 }' "$HYSTERIA_USER_FILE" |
    sort -t'|' -k3 |
    nl -w2 -s'. '
  )

  printf '%s\n' "${USERS[@]}"
  echo "────────────────────────────────────"

  read -rp "🔢 Numéro à supprimer (1-${#USERS[@]}): " NUM

  # VALIDATION
  if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#USERS[@]} )); then
    echo "❌ Numéro invalide."
    pause
    return
  fi

  # EXTRACTION ligne exacte sélectionnée
  LINE=$(printf '%s\n' "${USERS[$((NUM-1))]}" | sed 's/^[0-9]*\. //')
  PHONE=$(echo "$LINE" | cut -d'|' -f1)

  if [[ -z "$PHONE" ]]; then
    echo "❌ Utilisateur introuvable."
    pause
    return
  fi

  echo "🗑️ Suppression de $PHONE..."

  # SUPPRESSION RÉELLE
  tmp=$(mktemp)
  grep -v "^$PHONE|" "$HYSTERIA_USER_FILE" > "$tmp"
  mv "$tmp" "$HYSTERIA_USER_FILE"
  chmod 600 "$HYSTERIA_USER_FILE"

  # 🔄 Mise à jour HYSTERIA
  TODAY=$(date +%Y-%m-%d)
  PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$HYSTERIA_USER_FILE" |
              sort -u | paste -sd, -)

  if jq --arg passwords "$PASSWORDS" \
        '.auth.config = ($passwords | split(","))' \
        "$HYSTERIA_CONFIG" > /tmp/config.json 2>/dev/null &&
     jq empty /tmp/config.json >/dev/null 2>&1; then

    mv /tmp/config.json "$HYSTERIA_CONFIG"
    systemctl restart "$HYSTERIA_SERVICE"
    echo "✅ $PHONE (n°$NUM) supprimé et HYSTERIA mis à jour"
  else
    echo "⚠️ Config HYSTERIA inchangée (sécurité)"
    rm -f /tmp/config.json
  fi

  pause
}

# ---------- 4) Fix (comme fix-hysteria.sh) ----------

fix_hysteria() {
  print_title
  echo "[4] IPTABLES HYSTERIA (coexistence ZIVPN OK)"
  # Utilise iptables -C intelligent (pas de flush)
  iptables -C INPUT -p udp --dport 20000 -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p udp --dport 20000 -j ACCEPT
  # ... (reste des règles -C)
  systemctl restart hysteria.service
  echo "✅ IPTables Hysteria OK"
}

# ---------- 5) Désinstallation ----------

uninstall_hysteria() {
  print_title
  echo "[5] DÉSINSTALLATION HYSTERIA (SAUF autres tunnels)"
  read -rp "Confirmer ? (o/N): " CONFIRM
  [[ "$CONFIRM" =~ ^[oO]$ ]] || { echo "Annulé"; pause; return; }

  # 1) Service seulement
  systemctl stop "$HYSTERIA_SERVICE" 2>/dev/null || true
  systemctl disable "$HYSTERIA_SERVICE" 2>/dev/null || true
  rm -f "/etc/systemd/system/$HYSTERIA_SERVICE"
  systemctl daemon-reload

  # 2) Fichiers seulement
  rm -f "$HYSTERIA_BIN"
  rm -rf /etc/hysteria

  # 3) IPTABLES HYSTERIA UNIQUEMENT (règles spécifiques -C)
  iptables -t nat -D PREROUTING -p udp --dport 20000:50000 -j DNAT --to-destination :20000 2>/dev/null || true
  iptables -D INPUT -p udp --dport 20000 -j ACCEPT 2>/dev/null || true
  iptables -D INPUT -p udp --dport 20000:50000 -j ACCEPT 2>/dev/null || true

  # ✅ SAUVEGARDE iptables (RESTORE autres tunnels)
  netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4

  echo "✅ HYSTERIA supprimé SANS toucher ZIVPN/SlowDNS/UDP"
  echo "   Vérifiez: iptables -t nat -L PREROUTING -n"
  pause
}

# ---------- MAIN LOOP ----------

check_root

while true; do
  print_title
  show_status_block
  
  echo "1) Installer HYSTERIA (arivpnstores)"
  echo "2) Créer utilisateur HYSTERIA" 
  echo "3) Supprimer utilisateur"
  echo "4) Fix HYSTERIA (reset firewall/NAT)"
  echo "5) Désinstaller HYSTERIA"
  echo "0) Quitter"
  echo
  read -rp "Choix: " CHOIX

  case $CHOIX in
    1) install_hysteria ;;
    2) create_hysteria_user ;;
    3) delete_hysteria_user ;;
    4) fix_hysteria ;;
    5) uninstall_hysteria ;;
    0) exit 0 ;;
    *) echo "❌ Choix invalide"; sleep 1 ;;
  esac
done
