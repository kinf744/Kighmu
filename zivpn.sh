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
  echo "║        ZIVPN CONTROL PANEL v2         ║"
  echo "║     (Compatible @kighmu 🇨🇲)           ║"
  echo "╚═══════════════════════════════════════╝"
  echo
}

show_status_block() {
  echo "-------- STATUT ZIVPN --------"
  
  SVC_FILE_OK=$([[ -f "/etc/systemd/system/$ZIVPN_SERVICE" ]] && echo "✅" || echo "❌")
  SVC_ACTIVE=$(systemctl is-active "$ZIVPN_SERVICE" 2>/dev/null || echo "N/A")
  PORT_OK=$(ss -ludp | grep -q 5667 && echo "✅" || echo "❌")
  
  echo "Service file: $SVC_FILE_OK"
  echo "Service actif: $SVC_ACTIVE"
  echo "Port 5667: $PORT_OK"
  
  if [[ "$SVC_FILE_OK" == "✅" ]]; then
    if systemctl is-active --quiet "$ZIVPN_SERVICE" 2>/dev/null; then
      echo "✅ ZIVPN : INSTALLÉ et ACTIF"
      echo "   Port interne: 5667"
    else
      echo "⚠️  ZIVPN : INSTALLÉ mais INACTIF"
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

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload && systemctl enable "$ZIVPN_SERVICE"

  # ✅ IPTABLES INTELLIGENT (pas de flush !)
  iptables -C INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || \
  iptables -A INPUT -p udp --dport 5667 -j ACCEPT

  iptables -C INPUT -p udp --dport 36712 -j ACCEPT 2>/dev/null || \
  iptables -A INPUT -p udp --dport 36712 -j ACCEPT

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
    echo "   Lance l'option 1 ou: systemctl start $ZIVPN_SERVICE"
    pause
    return
  fi

  echo "Format: téléphone|password|expiration"
  echo "Exemple: 2330|MonPass123|2026-02-01"
  echo

  read -rp "Téléphone: " PHONE
  read -rp "Password ZIVPN: " PASS
  read -rp "Durée (jours): " DAYS

  EXPIRE=$(date -d "+${DAYS} days" '+%Y-%m-%d')

  # ✅ SAUVEGARDE users.list
  tmp=$(mktemp)
  grep -v "^$PHONE|" "$ZIVPN_USER_FILE" > "$tmp" 2>/dev/null || true
  echo "$PHONE|$PASS|$EXPIRE" >> "$tmp"
  mv "$tmp" "$ZIVPN_USER_FILE"
  chmod 600 "$ZIVPN_USER_FILE"

  # ✅ EXTRACTION PASSWORDS (NOUVEAU : simple et sûr)
  TODAY=$(date +%Y-%m-%d)
  PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" | \
              sort -u | paste -sd, -)

  # ✅ JQ CORRIGÉ (string → array avec split)
  if jq --arg passwords "$PASSWORDS" \
        '.auth.config = ($passwords | split(","))' \
        "$ZIVPN_CONFIG" > /tmp/config.json 2>/dev/null; then
    
    # Vérif JSON valide
    if jq empty /tmp/config.json >/dev/null 2>&1; then
      mv /tmp/config.json "$ZIVPN_CONFIG"
      systemctl restart "$ZIVPN_SERVICE"
      
      IP=$(hostname -I | awk '{print $1}')
      DOMAIN=$(cat "$ZIVPN_DOMAIN_FILE" 2>/dev/null || echo "$IP")

      echo
      echo "✅ 𝗨𝗧𝗜𝗟𝗜𝗦𝗔𝗧𝗘𝗨𝗥 𝗖𝗥𝗘𝗘𝗥"
      echo "━━━━━━━━━━━━━━━━━━━━━"
      echo "🌐 𝗗𝗼𝗺𝗮𝗶𝗻𝗲  : $DOMAIN"
      echo "🎭 𝗢𝗯𝗳𝘀     : zivpn"
      echo "🔐 𝗣𝗮𝘀𝘀𝘄𝗼𝗿𝗱 : $PASS"
      echo "📅 𝗘𝘅𝗽𝗶𝗿𝗲   : $EXPIRE"
      echo "🔌 𝐏𝐨𝐫𝐭    : 5667"
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

delete_zivpn_user() {
  print_title
  echo "[3] SUPPRIMER UTILISATEUR (NUMÉRO)"

  if [[ ! -f "$ZIVPN_USER_FILE" || ! -s "$ZIVPN_USER_FILE" ]]; then
    echo "❌ Aucun utilisateur enregistré."
    pause
    return
  fi

  echo "Utilisateurs actifs (sélectionnez NUMÉRO):"
  echo "────────────────────────────────────"
  
  # 📋 LISTE NUMÉROTÉE avec awk
  mapfile -t USERS < <(awk -F'|' '{
    printf "%s | %s | %s
", $1, $2, $3
  }' "$ZIVPN_USER_FILE" | sort -k3 | nl -w2 -s'. ')
  
  printf '%s
' "${USERS[@]}"
  echo "────────────────────────────────────"
  read -rp "🔢 Numéro à supprimer (1-$(echo "${#USERS[@]}")): " NUM

  # VALIDATION numéro
  if ! [[ "$NUM" =~ ^[0-9]+$ ]] || [ "$NUM" -lt 1 ] || [ "$NUM" -gt "${#USERS[@]}" ]; then
    echo "❌ Numéro invalide."
    pause
    return
  fi

  # EXTRACTION téléphone du numéro choisi
  PHONE=$(awk -F'|' 'NR=='$NUM' {print $1}' "$ZIVPN_USER_FILE")
  
  if [[ -z "$PHONE" ]]; then
    echo "❌ Utilisateur introuvable."
    pause
    return
  fi

  echo "🗑️ Supprimant $PHONE..."

  # SUPPRESSION
  tmp=$(mktemp)
  grep -v "^$PHONE|" "$ZIVPN_USER_FILE" > "$tmp"
  mv "$tmp" "$ZIVPN_USER_FILE"
  chmod 600 "$ZIVPN_USER_FILE"

  # ✅ JQ STABLE (comme avant)
  TODAY=$(date +%Y-%m-%d)
  PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" | \
              sort -u | paste -sd, -)

  if jq --arg passwords "$PASSWORDS" \
        '.auth.config = ($passwords | split(","))' \
        "$ZIVPN_CONFIG" > /tmp/config.json 2>/dev/null && \
     jq empty /tmp/config.json >/dev/null 2>&1; then
    
    mv /tmp/config.json "$ZIVPN_CONFIG"
    systemctl restart "$ZIVPN_SERVICE"
    echo "✅ $PHONE (n°$NUM) supprimé et ZIVPN mis à jour"
  else
    echo "⚠️ Config ZIVPN inchangée (sécurité)"
    rm -f /tmp/config.json
  fi

  pause
}

# ---------- 4) Fix (comme fix-zivpn.sh) ----------

fix_zivpn() {
  print_title
  echo "[4] FIX ZIVPN + SlowDNS (coexistence)"
  
  # Force iptables legacy (pas de conflit nftables)
  update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
  
  # Reset + recréation ZIVPN (préserve SlowDNS port 53)
  iptables -t nat -F PREROUTING
  iptables -A INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || true
  iptables -A INPUT -p udp --dport 36712 -j ACCEPT 2>/dev/null || true
  iptables -t nat -A PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667
  
  netfilter-persistent save
  systemctl restart zivpn.service
  
  echo "✅ ZIVPN fixé (6000-19999→5667)"
  echo "   SlowDNS préservé (53→5300)"
}

# ---------- 5) Désinstallation ----------

uninstall_zivpn() {
  print_title
  echo "[5] DÉSINSTALLATION"
  read -rp "Confirmer ? (o/N): " CONFIRM
  [[ "$CONFIRM" =~ ^[oO]$ ]] || { echo "Annulé"; pause; return; }

  # Arrêt et désactivation du service
  systemctl stop "$ZIVPN_SERVICE" 2>/dev/null || true
  systemctl disable "$ZIVPN_SERVICE" 2>/dev/null || true
  rm -f "/etc/systemd/system/$ZIVPN_SERVICE"
  systemctl daemon-reload

  # Suppression binaire + dossiers
  rm -f "$ZIVPN_BIN"
  rm -rf /etc/zivpn

  # Nettoyage firewall / NAT
  # 1) Supprimer la règle DNAT spécifique si tu veux être précis :
  iptables -t nat -D PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || true
  # 2) Et à défaut, tu peux garder un flush global si tu préfères :
  iptables -t nat -F PREROUTING 2>/dev/null || true

  # UFW : ta ligne actuelle ne sert à rien car tu n'as pas créé de règle 6000:19999/udp via ufw
  # soit tu vires complètement la ligne ufw, soit tu mets un reset général si tu veux :
  # ufw --force reset >/dev/null 2>&1 || true

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
