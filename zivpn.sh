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
  echo "║     (Compatible @kighmu 🇨🇲)        ║"
  echo "╚═══════════════════════════════════════╝"
  echo
}

show_status_block() {
  echo "------ STATUT ZIVPN ------"
  
  # Debug détaillé pour identifier le problème
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

# ---------- 1) Installation (exactement comme arivpnstores) ----------

install_zivpn() {
  print_title
  echo "[1] INSTALLATION ZIVPN"
  echo

  if zivpn_installed; then
    echo "ZIVPN déjà installé."
    pause
    return
  fi

  # Clean slate
  systemctl stop zivpn >/dev/null 2>&1 || true
  ufw disable >/dev/null 2>&1 || true
  iptables -F; iptables -t nat -F

  apt update -y && apt install -y wget curl jq openssl ufw iptables-persistent

  # Binaire + cert (code précédent OK)
  wget -q "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64" -O "$ZIVPN_BIN"
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
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload && systemctl enable "$ZIVPN_SERVICE"

  # FIREWALL CORRIGÉ
  iptables -t nat -A PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667
  iptables -A INPUT -p udp --dport 5667 -j ACCEPT
  iptables -A INPUT -p udp --dport 6000:19999 -j ACCEPT
  iptables -A INPUT -p udp --dport 36712 -j ACCEPT 2>/dev/null || true
  netfilter-persistent save

  sysctl -w net.core.rmem_max=16777216
  sysctl -w net.core.wmem_max=16777216

  systemctl start "$ZIVPN_SERVICE"
  
  echo "✅ ZIVPN installé ! Teste avec password 'zi'"
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
      echo
      echo"━━━━━━━━━━━━━━━━━━━━━"
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
  echo "[3] SUPPRIMER UTILISATEUR"

  # On ne bloque plus sur zivpn_installed, seulement sur le fichier users
  if [[ ! -f "$ZIVPN_USER_FILE" || ! -s "$ZIVPN_USER_FILE" ]]; then
    echo "❌ Aucun utilisateur enregistré pour l’instant."
    pause
    return
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
