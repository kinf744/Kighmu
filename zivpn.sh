#!/bin/bash
# zivpn-panel-v2.sh - Panel UDP ZiVPN complet (quota + gestion users + fix)
set -euo pipefail

# ---------- VARIABLES ----------

ZIVPN_BIN="/usr/local/bin/zivpn"
ZIVPN_SERVICE="zivpn.service"
ZIVPN_CONFIG="/etc/zivpn/config.json"
ZIVPN_USER_FILE="/etc/zivpn/users.list"
ZIVPN_DOMAIN_FILE="/etc/zivpn/domain.txt"
ZIVPN_QUOTA_FILE="/etc/zivpn/quotas.list"  # PHONE|IP|QUOTA_BYTES

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

# ---------- FONCTIONS QUOTA / STATUT ----------

bytes_to_gb() {
  awk -v b="$1" 'BEGIN { printf "%.2f", b/1024/1024/1024 }'
}

get_ip_usage() {
  local IP="$1"
  iptables -L FORWARD -v -n | awk -v ip="$IP" '
    $8==ip && $1 ~ /^[0-9]+$/ { sum+=$2 }
    END { print sum+0 }
  '
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

block_expired_user() {
  local PHONE="$1"
  IP=$(awk -F'|' -v p="$PHONE" '$1==p {print $2}' "$ZIVPN_QUOTA_FILE")
  [[ -z "$IP" ]] && return
  iptables -D FORWARD -s "$IP" -j DROP 2>/dev/null || true
}

# ---------- 1) INSTALLATION ZIVPN ----------

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
  systemctl stop ufw  >/dev/null 2>&1 || true
  ufw disable         >/dev/null 2>&1 || true
  apt purge ufw -y    >/dev/null 2>&1 || true
  
  # RESET iptables propre
  iptables -F
  iptables -t nat -F
  iptables -t mangle -F 2>/dev/null || true

  # Paquets
  apt update -y && apt install -y wget curl jq openssl iptables-persistent netfilter-persistent

  # Binaire
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
RestartSec=5
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$ZIVPN_SERVICE"

  # Firewall / NAT
  iptables -A INPUT -p udp --dport 5667 -j ACCEPT   # ZIVPN interne
  iptables -A INPUT -p udp --dport 36712 -j ACCEPT  # UDP Custom
  iptables -A INPUT -p udp --dport 6000:19999 -j ACCEPT  # ZIVPN clients
  iptables -t nat -A PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667
  
  netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4

  # Optimisations réseau
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
    echo "🔍 Vérif ports: ss -ulnp | grep -E '(53|5667|36712)'"
  else
    echo "❌ ZIVPN ne démarre pas → journalctl -u zivpn.service"
  fi
  
  pause
}

# ---------- 2) CRÉATION UTILISATEUR ----------

create_zivpn_user() {
  print_title
  echo "[2] CRÉATION UTILISATEUR ZIVPN"

  if ! systemctl is-active --quiet "$ZIVPN_SERVICE"; then
    echo "❌ Service ZIVPN inactif ou non installé."
    echo "   Lance l'option 1 ou: systemctl start $ZIVPN_SERVICE"
    pause
    return
  fi

  echo "Format: téléphone | password | durée | quota"
  echo "Exemple: 2330 / MonPass123 / 30 jours / 50 Go"
  echo "NB: quota 0 = illimité (pas de blocage sur quota)"
  echo

  read -rp "Téléphone: " PHONE
  read -rp "Password ZIVPN: " PASS
  read -rp "Durée (jours): " DAYS
  read -rp "Quota (Go, 0 = illimité): " QUOTA_GB
  read -rp "IP client (laisser vide pour IP publique VPS): " USER_IP

  EXPIRE=$(date -d "+${DAYS} days" '+%Y-%m-%d')
  TODAY=$(date +%Y-%m-%d)
  QUOTA_BYTES=$(awk -v gb="${QUOTA_GB:-0}" 'BEGIN { print gb*1024*1024*1024 }')
  USER_IP=${USER_IP:-$(hostname -I | awk '{print $1}')}
  CONSO_USED=0

  # Sauvegarde users.list (téléphone|password|expiration)
  tmp=$(mktemp)
  grep -v "^$PHONE|" "$ZIVPN_USER_FILE" > "$tmp" 2>/dev/null || true
  echo "$PHONE|$PASS|$EXPIRE" >> "$tmp"
  mv "$tmp" "$ZIVPN_USER_FILE"

  # Sauvegarde quotas.list (téléphone|IP|quota_bytes|consommé)
  tmpq=$(mktemp)
  grep -v "^$PHONE|" "$ZIVPN_QUOTA_FILE" > "$tmpq" 2>/dev/null || true
  echo "$PHONE|$USER_IP|$QUOTA_BYTES|$CONSO_USED" >> "$tmpq"
  mv "$tmpq" "$ZIVPN_QUOTA_FILE"

  chmod 600 "$ZIVPN_USER_FILE" "$ZIVPN_QUOTA_FILE"

  # Extraction des passwords valides
  PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" | sort -u | paste -sd, -)
  if jq --arg passwords "$PASSWORDS" '.auth.config = ($passwords | split(","))' "$ZIVPN_CONFIG" > /tmp/config.json 2>/dev/null; then
    if jq empty /tmp/config.json >/dev/null 2>&1; then
      mv /tmp/config.json "$ZIVPN_CONFIG"
      systemctl restart "$ZIVPN_SERVICE"

      DOMAIN=$(cat "$ZIVPN_DOMAIN_FILE" 2>/dev/null || echo "$USER_IP")

      # 🔹 Déterminer statut
      if [[ "$EXPIRE" < "$TODAY" ]]; then
        STATUS="EXPIRÉ"
        COLOR="⚫"
      elif [[ "$QUOTA_BYTES" -ne 0 && "$CONSO_USED" -ge "$QUOTA_BYTES" ]]; then
        STATUS="ÉPUISÉ"
        COLOR="🔴"
      else
        STATUS="ACTIF"
        COLOR="🟢"
      fi

      # 🔹 Blocage automatique si expiré ou quota atteint
      if [[ "$STATUS" == "EXPIRÉ" ]] || [[ "$STATUS" == "ÉPUISÉ" ]]; then
        iptables -A INPUT -s "$USER_IP" -j DROP
      fi

      # 🔹 Affichage
      echo
      echo "✅ UTILISATEUR CRÉÉ"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "📱 Téléphone : $PHONE"
      echo "🌐 Domaine   : $DOMAIN"
      echo "🎭 Obfs      : zivpn"
      echo "🔐 Password  : $PASS"
      echo "📅 Expire    : $EXPIRE"
      echo "🔌 IP client : $USER_IP"
      echo "📦 Quota     : ${QUOTA_GB} Go (0 = illimité)"
      echo "📊 Consommé  : ${CONSO_USED} Bytes"
      echo "🟢 Statut    : $STATUS $COLOR"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    else
      echo "❌ JSON invalide → rollback"
      rm -f /tmp/config.json
    fi
  else
    echo "❌ Erreur jq → config inchangée"
  fi

  pause
}

# ---------- 3) SUPPRESSION UTILISATEUR ----------

delete_zivpn_user() {
  print_title
  echo "[3] SUPPRIMER UTILISATEUR (NUMÉRO)"

  if [[ ! -f "$ZIVPN_USER_FILE" || ! -s "$ZIVPN_USER_FILE" ]]; then
    echo "❌ Aucun utilisateur enregistré."
    pause
    return
  fi

  echo "Utilisateurs enregistrés (sélectionnez NUMÉRO):"
  echo "────────────────────────────────────"
  
  mapfile -t USERS < <(awk -F'|' '{
    printf "%s | %s | %s
", $1, $2, $3
  }' "$ZIVPN_USER_FILE" | sort -k3 | nl -w2 -s'. ')
  
  printf '%s
' "${USERS[@]}"
  echo "────────────────────────────────────"
  read -rp "🔢 Numéro à supprimer (1-$(echo "${#USERS[@]}")): " NUM

  if ! [[ "$NUM" =~ ^[0-9]+$ ]] || [ "$NUM" -lt 1 ] || [ "$NUM" -gt "${#USERS[@]}" ]; then
    echo "❌ Numéro invalide."
    pause
    return
  fi

  PHONE=$(awk -F'|' 'NR=='"$NUM"' {print $1}' "$ZIVPN_USER_FILE")
  
  if [[ -z "$PHONE" ]]; then
    echo "❌ Utilisateur introuvable."
    pause
    return
  fi

  echo "🗑️ Suppression de $PHONE..."

  tmp=$(mktemp)
  grep -v "^$PHONE|" "$ZIVPN_USER_FILE" > "$tmp"
  mv "$tmp" "$ZIVPN_USER_FILE"
  chmod 600 "$ZIVPN_USER_FILE"

  # Supprime aussi le quota associé
  if [[ -f "$ZIVPN_QUOTA_FILE" ]]; then
    tmpq=$(mktemp)
    grep -v "^$PHONE|" "$ZIVPN_QUOTA_FILE" > "$tmpq"
    mv "$tmpq" "$ZIVPN_QUOTA_FILE"
    chmod 600 "$ZIVPN_QUOTA_FILE"
  fi

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

# ---------- 4) FIX ZIVPN (COEXIST SlowDNS) ----------

fix_zivpn() {
  print_title
  echo "[4] FIX ZIVPN + SlowDNS (coexistence)"
  
  update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
  
  iptables -t nat -F PREROUTING
  iptables -A INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || true
  iptables -A INPUT -p udp --dport 36712 -j ACCEPT 2>/dev/null || true
  iptables -t nat -A PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667
  
  netfilter-persistent save
  systemctl restart zivpn.service
  
  echo "✅ ZIVPN fixé (6000-19999→5667)"
  echo "   SlowDNS préservé (53→5300)"
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
  rm -f "/etc/systemd/system/$ZIVPN_SERVICE"
  systemctl daemon-reload

  rm -f "$ZIVPN_BIN"
  rm -rf /etc/zivpn

  # Nettoyage firewall / NAT
  iptables -t nat -D PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || true
  iptables -t nat -F PREROUTING 2>/dev/null || true

  echo "✅ ZIVPN supprimé"
  pause
}

# ---------- 6) AFFICHAGE UTILISATEURS + CONSOMMATION ----------

show_users_usage() {
  print_title
  echo "[6] UTILISATEURS – CONSOMMATION & EXPIRATION"
  echo

  [[ -f "$ZIVPN_USER_FILE" ]]  || { echo "❌ Aucun utilisateur."; pause; return; }
  [[ -f "$ZIVPN_QUOTA_FILE" ]] || { echo "❌ Aucun quota."; pause; return; }

  # 🔹 Création d'un fichier temporaire pour mettre à jour les quotas
  tmpq=$(mktemp)
  TODAY=$(date +%Y-%m-%d)

  printf "%-15s %-15s %-15s %-15s %-10s\n" "PASSWORD" "CONSOMMATION" "QUOTA TOTAL" "EXPIRATION" "STATUT"
  echo "────────────────────────────────────────────────────────────"

  while IFS='|' read -r PHONE PASS EXPIRE; do
    QUOTA_LINE=$(grep "^$PHONE|" "$ZIVPN_QUOTA_FILE" 2>/dev/null || true)
    [[ -z "$QUOTA_LINE" ]] && continue

    IP=$(echo "$QUOTA_LINE" | cut -d'|' -f2)
    QUOTA_BYTES=$(echo "$QUOTA_LINE" | cut -d'|' -f3)
    CONSO_USED=$(echo "$QUOTA_LINE" | cut -d'|' -f4)

    # 🔹 Calcul consommation réelle
    USED_BYTES=$(iptables -L INPUT -v -n -x | awk -v ip="$IP" '$8==ip && $7=="udp" {sum+=$2*64} END{print sum+0}')

    # 🔹 Vérification blocage
    if [[ "$QUOTA_BYTES" -ne 0 && "$USED_BYTES" -ge "$QUOTA_BYTES" ]]; then
      iptables -D INPUT -s "$IP" -j DROP 2>/dev/null || true
      iptables -A INPUT -s "$IP" -j DROP
    else
      iptables -D INPUT -s "$IP" -j DROP 2>/dev/null || true
    fi

    # 🔹 Mise à jour temporaire du fichier quotas
    echo "$PHONE|$IP|$QUOTA_BYTES|$USED_BYTES" >> "$tmpq"

    # 🔹 Statut
    if [[ "$EXPIRE" < "$TODAY" ]]; then
      STATUS="EXPIRÉ"
      STATUS_COLOR="⚫"
    elif [[ "$QUOTA_BYTES" -ne 0 && "$USED_BYTES" -ge "$QUOTA_BYTES" ]]; then
      STATUS="ÉPUISÉ"
      STATUS_COLOR="🔴"
    else
      STATUS="ACTIF"
      STATUS_COLOR="🟢"
    fi

    USED_GB=$(bytes_to_gb "$USED_BYTES")
    QUOTA_GB=$(bytes_to_gb "$QUOTA_BYTES")

    printf "%-15s %-15s %-15s %-15s %-10s\n" \
      "$PASS" "${USED_GB} Go" "${QUOTA_GB} Go" "$EXPIRE" "$STATUS_COLOR $STATUS"

  done < "$ZIVPN_USER_FILE"

  # 🔹 Remplacement du fichier quotas par la version mise à jour
  mv "$tmpq" "$ZIVPN_QUOTA_FILE"
  chmod 600 "$ZIVPN_QUOTA_FILE"

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
  echo "6) Voir utilisateurs + consommation"
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
