#!/usr/bin/env bash
# ============================================================
# Script : ws_wssr_ws_only.sh
# Description : Gestion et supervision du tunnel WS SSH (WS only)
# Auteur : Kinf744 (adapté)
# Version : 2.4 - WS uniquement, prêt à l'emploi
# ============================================================

set -euo pipefail

SERVICE_NAME="ws_wss_server"
SCRIPT_PATH="/root/Kighmu/ws_wss_server_ws_only.py"
LOG_FILE="/var/log/ws_wss_server.log"
DOMAIN_FILE="$HOME/.kighmu_info"
VENV_DIR="$HOME/.ws_wss_venv"

# -------------------- Logging --------------------
log() {
  local lvl="$1"; shift
  local msg="$*"
  local ts
  ts=$(date "+%Y-%m-%d %H:%M:%S")
  printf "%s [%s] %s\n" "$ts" "$lvl" "$msg" | tee -a "$LOG_FILE"
}
log_debug() { log DEBUG "$@"; }
log_info()  { log INFO  "$@"; }
log_warn()  { log WARNING "$@"; }
log_error() { log ERROR "$@"; }

log_info "Démarrage du script ws_wssr_ws_only.sh"

# -------------------- Vérification domaine --------------------
if [[ ! -f "$DOMAIN_FILE" ]]; then
  log_error "Fichier ~/.kighmu_info introuvable !"
  exit 1
fi
DOMAIN=$(grep -m1 "DOMAIN=" "$DOMAIN_FILE" | cut -d'=' -f2)
if [[ -z "$DOMAIN" ]]; then
  log_error "Domaine introuvable dans ~/.kighmu_info"
  exit 1
fi
log_info "Domaine chargé: $DOMAIN"

# -------------------- Python & venv --------------------
log_info "Vérification/installation des dépendances système..."
apt-get update -y >/dev/null 2>&1
apt-get install -y --no-install-recommends python3 python3-venv python3-pip curl >/dev/null 2>&1 || true

if [[ ! -d "$VENV_DIR" ]]; then
  log_info "Création de l'environnement virtuel Python dans $VENV_DIR..."
  python3 -m venv "$VENV_DIR"
else
  log_info "Environnement virtuel Python déjà existant ($VENV_DIR)."
fi

log_info "Activation du venv et installation de websockets..."
source "$VENV_DIR/bin/activate"
pip install --upgrade pip setuptools
pip install websockets
deactivate
log_info "Dépendances Python installées dans le venv."

# -------------------- Création service systemd --------------------
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
log_info "Création du service systemd..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Kighmu WS Tunnel SSH (WS only)
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
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"
log_info "Service systemd ${SERVICE_NAME} démarré."

# -------------------- Watchdog persistant --------------------
log_info "Installation du watchdog persistant..."
cat > /usr/local/bin/ws_wss_watchdog.sh <<'EOF'
#!/usr/bin/env bash
SERVICE="ws_wss_server"
while true; do
  if ! systemctl is-active --quiet "$SERVICE"; then
    logger -t ws_wss_watchdog "Service $SERVICE indisponible, redémarrage..."
    systemctl restart "$SERVICE"
  fi
  sleep 30
done
EOF
chmod +x /usr/local/bin/ws_wss_watchdog.sh

cat > /etc/systemd/system/ws_wss_watchdog.service <<EOF
[Unit]
Description=Watchdog for WS service

[Service]
ExecStart=/usr/local/bin/ws_wss_watchdog.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ws_wss_watchdog
systemctl start ws_wss_watchdog
log_info "Watchdog installé et démarré."

# -------------------- UFW --------------------
if command -v ufw >/dev/null 2>&1; then
  log_info "UFW détecté. Autorisation du port 8880..."
  if ufw status | grep -qw "8880/tcp"; then
    log_info "Port 8880/tcp déjà autorisé."
  else
    ufw allow 8880/tcp
    log_info "Port 8880/tcp autorisé via UFW."
  fi
else
  log_warn "UFW non installé. Pas de configuration de pare-feu."
fi

# -------------------- Rapport final --------------------
log_info ""
log_info "=============================================================="
log_info " 🎉 Serveur WS opérationnel (WS uniquement)"
log_info "--------------------------------------------------------------"
log_info " Domaine utilisé   : ${DOMAIN}"
log_info " WS (non sécurisé) : ws://${DOMAIN}:8880"
log_info " Logs              : ${LOG_FILE}"
log_info " Service systemd   : ${SERVICE_NAME}"
log_info " Pour suivre les logs : journalctl -u ${SERVICE_NAME} -f"
log_info "=============================================================="
log_info ""

exit 0
