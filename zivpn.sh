#!/bin/bash
# zivpn-panel.sh
set -euo pipefail

ZIVPN_BIN="/usr/local/bin/zivpn"
ZIVPN_SERVICE="zivpn"
ZIVPN_CONFIG="/etc/zivpn/config.json"
ZIVPN_USER_FILE="/etc/zivpn/users.list"   # mapping téléphone|password|expiry

mkdir -p /etc/zivpn
touch "$ZIVPN_USER_FILE"

# ---------- Fonctions utilitaires ----------

pause() {
  echo
  read -rp "Appuyez sur Entrée pour continuer..."
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Ce panneau doit être lancé en root."
    exit 1
  fi
}

zivpn_installed() {
  [[ -x "$ZIVPN_BIN" ]] && systemctl list-unit-files | grep -q "^${ZIVPN_SERVICE}.service"
}

zivpn_running() {
  systemctl is-active --quiet "$ZIVPN_SERVICE"
}

print_title() {
  clear
  echo "╔═══════════════════════════════════════╗"
  echo "║        ZIVPN CONTROL PANEL           ║"
  echo "╚═══════════════════════════════════════╝"
  echo
}

show_status_block() {
  echo "------ STATUT ZIVPN ------"
  if zivpn_installed; then
    if zivpn_running; then
      echo "ZIVPN : INSTALLÉ et ACTIF (service en cours d'exécution)"
    else
      echo "ZIVPN : INSTALLÉ mais INACTIF (service arrêté)"
    fi
  else
    echo "ZIVPN : NON INSTALLÉ"
  fi
  echo "--------------------------"
  echo
}

# ---------- 1) Installation de ZIVPN ----------

install_zivpn() {
  print_title
  echo "[1] INSTALLATION DE ZIVPN"
  echo

  if zivpn_installed; then
    echo "ZIVPN semble déjà installé."
    pause
    return
  fi

  apt update -y
  apt install -y wget curl jq nftables openssl

  systemctl stop "$ZIVPN_SERVICE" >/dev/null 2>&1 || true

  echo "[+] Téléchargement du binaire ZIVPN (amd64 1.4.9)"
  wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 \
    -O "$ZIVPN_BIN"
  chmod +x "$ZIVPN_BIN"

  mkdir -p /etc/zivpn
  CERT="/etc/zivpn/zivpn.crt"
  KEY="/etc/zivpn/zivpn.key"

  read -rp "Nom de domaine (CN du certificat, ex: zivpn.example.com) : " DOMAIN
  [[ -z "$DOMAIN" ]] && DOMAIN="zivpn.local"

  echo "[+] Génération certificat auto-signé pour $DOMAIN"
  openssl req -x509 -newkey rsa:2048 \
    -keyout "$KEY" \
    -out "$CERT" \
    -nodes -days 3650 \
    -subj "/CN=$DOMAIN"

  chmod 600 "$KEY"
  chmod 644 "$CERT"

  cat > "$ZIVPN_CONFIG" <<EOF
{
  "listen": ":5667",
  "cert": "$CERT",
  "key": "$KEY",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": []
  }
}
EOF

  # service systemd
  cat > /etc/systemd/system/${ZIVPN_SERVICE}.service <<EOF
[Unit]
Description=ZIVPN UDP Server
After=network.target

[Service]
Type=simple
ExecStart=$ZIVPN_BIN server -c $ZIVPN_CONFIG
WorkingDirectory=/etc/zivpn
Restart=always
RestartSec=3
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$ZIVPN_SERVICE"

  # nftables minimal (plage 6000-19999 -> 5667)
  mkdir -p /etc/nftables.d
  cat > /etc/nftables.d/zivpn.nft <<'EOF'
table ip zivpn {
  chain prerouting {
    type nat hook prerouting priority -100;
    udp dport 6000-19999 dnat to 0.0.0.0:5667
  }

  chain input {
    type filter hook input priority 0;
    udp dport 5667 accept
    udp dport 6000-19999 accept
    ct state established,related accept
  }

  chain forward {
    type filter hook forward priority 0;
    accept
  }

  chain postrouting {
    type nat hook postrouting priority 100;
    oifname != "tun0" masquerade
  }
}
EOF

  if ! grep -q "nftables.d" /etc/nftables.conf 2>/dev/null; then
    echo 'include "/etc/nftables.d/*.nft"' >> /etc/nftables.conf
  fi

  systemctl enable nftables
  systemctl restart nftables

  systemctl restart "$ZIVPN_SERVICE"

  echo
  if zivpn_running; then
    echo "✅ Installation ZIVPN terminée."
  else
    echo "❌ Le service ZIVPN ne démarre pas, vérifiez 'journalctl -u $ZIVPN_SERVICE'."
  fi
  pause
}

# ---------- 2) Création d’utilisateur ZIVPN ----------

create_zivpn_user() {
  print_title
  echo "[2] CRÉATION D'UTILISATEUR ZIVPN"
  echo

  if ! zivpn_installed; then
    echo "ZIVPN n'est pas installé. Installe-le d'abord."
    pause
    return
  fi

  read -rp "Numéro de téléphone (identifiant user, ex: 22997000000) : " PHONE
  read -rp "Mot de passe ZIVPN (ex: Rerechan02) : " PASS
  read -rp "Durée (en jours) : " DAYS

  if [[ -z "$PHONE" || -z "$PASS" || -z "$DAYS" ]]; then
    echo "Champs invalides."
    pause
    return
  fi

  if ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
    echo "Durée invalide."
    pause
    return
  fi

  EXPIRE_DATE=$(date -d "+${DAYS} days" '+%Y-%m-%d')

  # Sauvegarde dans users.list : phone|pass|expire
  # si le phone existe déjà, on le remplace
  tmpfile=$(mktemp)
  grep -v "^${PHONE}|" "$ZIVPN_USER_FILE" > "$tmpfile" || true
  echo "${PHONE}|${PASS}|${EXPIRE_DATE}" >> "$tmpfile"
  mv "$tmpfile" "$ZIVPN_USER_FILE"

  # Regénérer auth.config avec tous les users non expirés
  TODAY=$(date +%Y-%m-%d)
  PASS_ARRAY=$(awk -F'|' -v today="$TODAY" '
    $3 >= today { print $2 }
  ' "$ZIVPN_USER_FILE" | sort -u | jq -R . | jq -s .)

  jq --argjson arr "$PASS_ARRAY" '.auth.config = $arr' "$ZIVPN_CONFIG" > /tmp/zivpn.json
  mv /tmp/zivpn.json "$ZIVPN_CONFIG"

  systemctl restart "$ZIVPN_SERVICE"

  HOST_IP=$(hostname -I | awk '{print $1}')
  echo
  echo "✅ UTILISATEUR ZIVPN CRÉÉ"
  echo "-------------------------"
  echo "Téléphone : $PHONE"
  echo "Password  : $PASS"
  echo "Expire    : $EXPIRE_DATE"
  echo
  echo "Config à donner au client ZIVPN :"
  echo "  Host/IP     : $HOST_IP"
  echo "  UDP password: $PASS"
  echo "  Port UDP    : un port entre 6000 et 19999 (redirigé vers 5667)"
  echo

  pause
}

# ---------- 3) Suppression d’utilisateur ZIVPN ----------

delete_zivpn_user() {
  print_title
  echo "[3] SUPPRESSION D'UTILISATEUR ZIVPN"
  echo

  if ! zivpn_installed; then
    echo "ZIVPN n'est pas installé."
    pause
    return
  fi

  if ! [[ -s "$ZIVPN_USER_FILE" ]]; then
    echo "Aucun utilisateur ZIVPN enregistré."
    pause
    return
  fi

  echo "Liste des utilisateurs (classés par téléphone) :"
  echo "----------------------------------------------"
  sort -t'|' -k1,1 "$ZIVPN_USER_FILE" | nl -w2 -s'. '
  echo "----------------------------------------------"
  echo
  read -rp "Saisis le numéro de téléphone à supprimer : " PHONE

  tmpfile=$(mktemp)
  grep -v "^${PHONE}|" "$ZIVPN_USER_FILE" > "$tmpfile" || true
  mv "$tmpfile" "$ZIVPN_USER_FILE"

  # Regénérer auth.config
  TODAY=$(date +%Y-%m-%d)
  PASS_ARRAY=$(awk -F'|' -v today="$TODAY" '
    $3 >= today { print $2 }
  ' "$ZIVPN_USER_FILE" | sort -u | jq -R . | jq -s .)

  jq --argjson arr "$PASS_ARRAY" '.auth.config = $arr' "$ZIVPN_CONFIG" > /tmp/zivpn.json
  mv /tmp/zivpn.json "$ZIVPN_CONFIG"

  systemctl restart "$ZIVPN_SERVICE"

  echo
  echo "✅ Utilisateur $PHONE supprimé (si existant) et config ZIVPN mise à jour."
  pause
}

# ---------- 4) Désinstallation de ZIVPN ----------

uninstall_zivpn() {
  print_title
  echo "[4] DÉSINSTALLATION DE ZIVPN"
  echo

  if ! zivpn_installed; then
    echo "ZIVPN n'est pas installé."
    pause
    return
  fi

  read -rp "Confirmer la désinstallation complète de ZIVPN ? (o/N) : " ans
  ans=${ans:-n}
  if [[ "$ans" != "o" && "$ans" != "O" ]]; then
    echo "Annulé."
    pause
    return
  fi

  systemctl stop "$ZIVPN_SERVICE" || true
  systemctl disable "$ZIVPN_SERVICE" || true
  rm -f /etc/systemd/system/${ZIVPN_SERVICE}.service
  systemctl daemon-reload

  rm -f "$ZIVPN_BIN"
  rm -rf /etc/zivpn

  # Optionnel : retirer la règle nft
  rm -f /etc/nftables.d/zivpn.nft
  systemctl restart nftables || true

  echo "✅ ZIVPN désinstallé."
  pause
}

# ---------- Boucle principale ----------

check_root

while true; do
  print_title
  show_status_block
  echo "1) Installer ZIVPN"
  echo "2) Créer un utilisateur ZIVPN"
  echo "3) Supprimer un utilisateur ZIVPN (par numéro de téléphone)"
  echo "4) Désinstaller ZIVPN"
  echo "0) Quitter"
  echo
  read -rp "Choix : " choice

  case "$choice" in
    1) install_zivpn ;;
    2) create_zivpn_user ;;
    3) delete_zivpn_user ;;
    4) uninstall_zivpn ;;
    0) exit 0 ;;
    *) echo "Choix invalide"; sleep 1 ;;
  esac
done
