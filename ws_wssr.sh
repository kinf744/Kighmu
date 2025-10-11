#!/usr/bin/env bash
# ============================================================
# Script : ws_wssr.sh
# Description : Gestion et supervision du tunnel WS/WSS SSH
# Auteur : Kinf744
# Version : 2.1 + persistance + firewall + venv Python
# ============================================================

set -euo pipefail

SERVICE_NAME="ws_wss_server"
SCRIPT_PATH="/root/Kighmu/ws_wss_server.py"
LOG_FILE="/var/log/ws_wss_server.log"
LOG_FILE_WD="/var/log/ws_wss_watchdog.log"
LOG_FILE_BAK="/var/log/ws_wss_server.bak.log"
DOMAIN_FILE="$HOME/.kighmu_info"
VENV_DIR="$HOME/.ws_wss_venv"

# Log helpers
LOG_DIR=$(dirname "$LOG_FILE")
mkdir -p "$LOG_DIR"

log() {
  local lvl="$1"; shift
  local msg="$*"
  local ts
  ts=$(date "+%Y-%m-%d %H:%M:%S")
  printf "%s [%s] %s
" "$ts" "$lvl" "$msg" | tee -a "$LOG_FILE"
}

log INFO "Démarrage du script ws_wssr.sh"
log INFO "Chemin script: $0"

# Vérification domaine
verify_and_load_domain() {
  if [[ ! -f "$DOMAIN_FILE" ]]; then
    log ERROR "Fichier ~/.kighmu_info introuvable ! Exécute d'abord ton script d'installation Kighmu."
    exit 1
  fi

  DOMAIN=$(grep -m1 "DOMAIN=" "$DOMAIN_FILE" | cut -d'=' -f2)
  if [[ -z "$DOMAIN" ]]; then
    log ERROR "Domaine introuvable dans ~/.kighmu_info"
    exit 1
  fi
  log INFO "Domaine chargé: $DOMAIN"
}
verify_and_load_domain

# 🧩 Vérification de Python et dépendances avec venv
install_dependencies() {
  log INFO "Vérification/installation des dépendances système..."
  apt-get update -y >/dev/null 2>&1
  apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip certbot ufw curl wget jq ca-certificates nginx >/dev/null 2>&1 || true

  if [[ ! -d "$VENV_DIR" ]]; then
    log INFO "Création d’un environnement virtuel Python dans $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
  else
    log INFO "Environnement virtuel Python déjà existant ($VENV_DIR)."
  fi

  log INFO "Activation du venv et installation de websockets..."
  source "$VENV_DIR/bin/activate"
  pip install --upgrade pip setuptools
  pip install websockets
  deactivate
  log INFO "Dépendances Python installées dans le venv."
}
install_dependencies

# 📜 Création du service systemd avec python du venv
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

create_systemd_service() {
  log INFO "Création du service systemd pour ws_wss_server..."
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Kighmu WS/WSS Tunnel SSH
After=network.target

[Service]
ExecStart=${VENV_DIR}/bin/python ${SCRIPT_PATH}
Restart=always
RestartSec=5
User=root
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}

[Install]
WantedBy=multi-user.target
EOF

  chmod 644 "$SERVICE_FILE"
  log INFO "Service systemd créé: $SERVICE_FILE"
}
create_systemd_service

# 🔐 Gestion des certificats Let's Encrypt (inchangé)
setup_certificates() {
  CERT_PATH="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
  KEY_PATH="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

  if [[ ! -f "$CERT_PATH" || ! -f "$KEY_PATH" ]]; then
    log INFO "Génération/obtention des certificats Let's Encrypt pour ${DOMAIN}..."
    systemctl stop nginx 2>/dev/null || true
    certbot certonly --standalone -d "$DOMAIN" --agree-tos -m "admin@${DOMAIN}" --non-interactive || {
      log WARNING "Échec de Let's Encrypt — tentative d'un certificat auto-signé..."
      mkdir -p /etc/ssl/kighmu
      openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout /etc/ssl/kighmu/key.pem \
        -out /etc/ssl/kighmu/cert.pem \
        -days 365 \
        -subj "/CN=${DOMAIN}"
      CERT_PATH="/etc/ssl/kighmu/cert.pem"
      KEY_PATH="/etc/ssl/kighmu/key.pem"
    }
  fi
  log INFO "Certificat prêt (paths: $CERT_PATH, $KEY_PATH)."
}
setup_certificates

# 🚀 Lancement et activation du service
enable_and_start_service() {
  log INFO "Activation et démarrage du service WS/WSS..."
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}"
  systemctl restart "${SERVICE_NAME}"

  sleep 2
  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    log INFO "Service ${SERVICE_NAME} démarré avec succès."
  else
    log ERROR "Échec du démarrage du service. Voir journal."
    journalctl -u "${SERVICE_NAME}" -n 50 --no-pager
    exit 1
  fi
}
enable_and_start_service

# 🔄 Persistance avancée (watchdog)
install_persistent_watchdog() {
  log INFO "Installation du watchdog persistant..."
  local WATCHDOG="/usr/local/bin/ws_wss_watchdog.sh"
  cat > "$WATCHDOG" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SERVICE="ws_wss_server"
LOG="/var/log/ws_wss_watchdog.log"

while true; do
  if ! systemctl is-active --quiet "$SERVICE"; then
    logger -t ws_wss_watchdog "Service $SERVICE indisponible, redémarrage..."
    systemctl restart "$SERVICE" || logger -t ws_wss_watchdog "Échec du redémarrage du service $SERVICE"
  fi
  sleep 30
done
EOF
  chmod +x "$WATCHDOG"

  local WD_SERVICE="/etc/systemd/system/ws_wss_watchdog.service"
  cat > "$WD_SERVICE" <<EOF
[Unit]
Description=Watchdog for WS/WSS service

[Service]
ExecStart=/usr/local/bin/ws_wss_watchdog.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "$WD_SERVICE"
  systemctl daemon-reload
  systemctl enable ws_wss_watchdog
  systemctl start ws_wss_watchdog
  log INFO "Watchdog persistant installé et démarré."
}
install_persistent_watchdog

configure_ufw() {
  if command -v ufw >/dev/null 2>&1; then
    log INFO "UFW détecté. Mise en place des règles pour WS/WSS."
    if ufw status 2>&1 | grep -qi "inactive"; then
      log INFO "Activation de UFW (si non actif)."
      ufw --force enable
    fi
    open_port() {
      local port="$1"
      if ufw status | grep -qw "$port/tcp"; then
        log INFO "Port $port/tcp déjà autorisé par UFW."
      else
        ufw allow "$port/tcp"
        log INFO "Autorisation du port $port/tcp via UFW."
      fi
    }
    open_port 8880
    open_port 443
  else
    log WARNING "UFW n’est pas installé. Pas de configuration de pare-feu."
  fi
}
configure_ufw

gg_final_report() {
  log INFO ""
  log INFO "=============================================================="
  log INFO " 🎉 Serveur WS/WSS opérationnel"
  log INFO "--------------------------------------------------------------"
  log INFO " Domaine utilisé   : ${DOMAIN}"
  log INFO " WS (non sécurisé) : ws://${DOMAIN}:8880"
  log INFO " WSS (sécurisé)    : wss://${DOMAIN}:443"
  log INFO " Logs              : ${LOG_FILE}"
  log INFO " Service systemd   : ${SERVICE_NAME}"
  log INFO " Pour voir les logs : journalctl -u ${SERVICE_NAME} -f"
  log INFO "=============================================================="
  log INFO ""
}
gg_final_report

exit 0
