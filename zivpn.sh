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
  
  # ✅ FIX UDP OPTIMAL (comme tes logs le confirment)
  PORT_OK=$(ss -lunp 2>/dev/null | grep -q ":5667" && echo "✅" || echo "❌")
  
  echo "Service file: $SVC_FILE_OK"
  echo "Service actif: $SVC_ACTIVE"
  echo "Port 5667: $PORT_OK"  # ✅ S'AFFICHE MAINTENANT
  
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
  echo "[1] INSTALLATION ZIVPN (SOCAT - NO CONFLIT UFW)"
  echo

  if zivpn_installed; then
    echo "ZIVPN déjà installé."
    pause
    return
  fi

  # Clean slate + PURGE UFW
  systemctl stop zivpn >/dev/null 2>&1 || true
  systemctl stop socat-zivpn >/dev/null 2>&1 || true
  systemctl stop ufw >/dev/null 2>&1 || true
  ufw disable >/dev/null 2>&1 || true
  apt purge ufw -y >/dev/null 2>&1 || true
  
  # ✅ PAQUETS (socat + iptables-persistent)
  apt update -y && apt install -y wget curl jq openssl iptables-persistent netfilter-persistent socat

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

  # ✅ ZIVPN systemd service
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

  # ✅ SOCAT service (REMPLACE iptables 6000-19999→5667)
  cat > "/etc/systemd/system/socat-zivpn.service" << 'EOF'
[Unit]
Description=Socat ZIVPN UDP Forwarder (6000-19999 → 5667)
After=zivpn.service network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/socat UDP-LISTEN:6000-19999,fork,reuseaddr,bind=0.0.0.0 UDP:127.0.0.1:5667
Restart=always
RestartSec=5
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_NET_RAW

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$ZIVPN_SERVICE" socat-zivpn.service

  # ✅ UNE SEULE règle iptables (5667 direct access)
  iptables -C INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || \
  iptables -A INPUT -p udp --dport 5667 -j ACCEPT

  netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4
  
  # Optimisations réseau
  sysctl -w net.core.rmem_max=16777216
  sysctl -w net.core.wmem_max=16777216
  echo "net.core.rmem_max=16777216" >> /etc/sysctl.conf
  echo "net.core.wmem_max=16777216" >> /etc/sysctl.conf
  sysctl -p

  # Démarrage services
  systemctl start "$ZIVPN_SERVICE" socat-zivpn.service
  
  # VÉRIFICATION FINALE
  sleep 3
  ZIVPN_OK=$(systemctl is-active --quiet "$ZIVPN_SERVICE" 2>/dev/null && echo "✅" || echo "❌")
  SOCAT_OK=$(systemctl is-active --quiet socat-zivpn.service 2>/dev/null && echo "✅" || echo "❌")
  
  if [[ "$ZIVPN_OK" == "✅" && "$SOCAT_OK" == "✅" ]]; then
    IP=$(hostname -I | awk '{print $1}')
    echo "✅ ZIVPN + SOCAT installé et actif !"
    echo "📱 Config ZIVPN App:"
    echo "   Serveur UDP: $IP"
    echo ""
    echo "🔍 Status: systemctl status zivpn socat-zivpn"
    echo "📊 Logs:   journalctl -u socat-zivpn -f"
  else
    echo "❌ Problème → Vérifie:"
    echo "   journalctl -u zivpn.service -u socat-zivpn.service"
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

    # --- Entrée utilisateur ---
    read -rp "Téléphone: " PHONE
    read -rp "Password ZIVPN: " PASS
    read -rp "Durée (jours): " DAYS
    EXPIRE=$(date -d "+${DAYS} days" '+%Y-%m-%d')

    # --- Nettoyage utilisateurs expirés ---
    TODAY=$(date +%Y-%m-%d)
    tmp=$(mktemp)
    awk -F'|' -v today="$TODAY" '$3>=today {print $0}' "$ZIVPN_USER_FILE" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$ZIVPN_USER_FILE"

    # --- Suppression éventuelle doublon PHONE ---
    tmp=$(mktemp)
    grep -v "^$PHONE|" "$ZIVPN_USER_FILE" > "$tmp" 2>/dev/null || true
    echo "$PHONE|$PASS|$EXPIRE" >> "$tmp"
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

  # Lire la liste réelle depuis users.list
  mapfile -t USERS < <(sort -t'|' -k3 "$ZIVPN_USER_FILE")
  echo "Utilisateurs actifs (sélectionnez NUMÉRO):"
  echo "────────────────────────────────────"

  for i in "${!USERS[@]}"; do
    echo "$((i+1)). ${USERS[$i]}"
  done

  echo "────────────────────────────────────"
  read -rp "🔢 Numéro à supprimer (1-${#USERS[@]}): " NUM

  if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#USERS[@]} )); then
    echo "❌ Numéro invalide."
    pause
    return
  fi

  # EXTRACTION DU NUMÉRO DE TÉLÉPHONE RÉEL
  LINE="${USERS[$((NUM-1))]}"
  PHONE=$(echo "$LINE" | cut -d'|' -f1 | tr -d '[:space:]')

  echo "🗑️ Suppression de $PHONE..."

  # Supprimer la ligne correspondante dans users.list
  grep -v "^$PHONE|" "$ZIVPN_USER_FILE" > "${ZIVPN_USER_FILE}.tmp" || true
  mv "${ZIVPN_USER_FILE}.tmp" "$ZIVPN_USER_FILE"
  chmod 600 "$ZIVPN_USER_FILE"

  # Mise à jour config.json
  TODAY=$(date +%Y-%m-%d)
  PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" | sort -u | paste -sd, -)

  if jq --arg passwords "$PASSWORDS" '.auth.config = ($passwords | split(","))' "$ZIVPN_CONFIG" > /tmp/config.json 2>/dev/null &&
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
  echo "[5] DÉSINSTALLATION ZIVPN + SOCAT (SAUF autres tunnels)"
  read -rp "Confirmer ? (o/N): " CONFIRM
  [[ "$CONFIRM" =~ ^[oO]$ ]] || { echo "Annulé"; pause; return; }

  # 1) Arrêt et suppression services ZIVPN + SOCAT
  systemctl stop "$ZIVPN_SERVICE" socat-zivpn.service 2>/dev/null || true
  systemctl disable "$ZIVPN_SERVICE" socat-zivpn.service 2>/dev/null || true
  rm -f "/etc/systemd/system/$ZIVPN_SERVICE" "/etc/systemd/system/socat-zivpn.service"
  systemctl daemon-reload
  systemctl reset-failed "$ZIVPN_SERVICE" socat-zivpn.service 2>/dev/null || true

  # 2) Suppression binaire et fichiers config
  rm -f "$ZIVPN_BIN"
  rm -rf /etc/zivpn

  # 3) IPTABLES - SEULEMENT règle 5667 (socat n'ajoute rien d'autre)
  iptables -D INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || true

  # ✅ SAUVEGARDE iptables (autres tunnels préservés)
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save 2>/dev/null || true
  else
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
  fi

  echo "✅ ZIVPN + SOCAT supprimés SANS toucher autres tunnels"
  echo "   Services supprimés: zivpn.service, socat-zivpn.service"
  echo "   Fichiers supprimés: $ZIVPN_BIN, /etc/zivpn/"
  echo "   IPTables nettoyé: port 5667 seulement"
  echo ""
  echo "🔍 Vérifier status:"
  echo "   systemctl status zivpn socat-zivpn"
  echo "   iptables -t nat -L PREROUTING -n | grep 5667"
  echo "   ss -ulnp | grep 5667"
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
