#!/usr/bin/env bash
# ============================================================
# Script : ws_wssr.sh
# Description : Installation et supervision du tunnel WS SSH
# Auteur : Kinf744 (adapté)
# Version : 3.1 - WS uniquement, style SlowDNS
# ============================================================

set -euo pipefail

SERVICE_NAME="ws_wss_server"
SCRIPT_PATH="/root/Kighmu/ws_wss_server.py"
LOG_FILE="/var/log/ws_wss_server.log"
WATCHDOG_LOG="/var/log/ws_wss_watchdog.log"
DOMAIN_FILE="$HOME/.kighmu_info"
VENV_DIR="$HOME/.ws_wss_venv"
WS_PORT=8880

# -------------------- Logging --------------------
log() { local lvl="$1"; shift; printf "%s [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$lvl" "$*" | tee -a "$LOG_FILE"; }
log_info() { log INFO "$@"; }
log_warn() { log WARNING "$@"; }
log_error() { log ERROR "$@"; }

log_info "🚀 Démarrage du script d'installation WS-only"

# -------------------- Domaine --------------------
if [[ ! -f "$DOMAIN_FILE" ]]; then
    log_error "Fichier ~/.kighmu_info introuvable !"
    exit 1
fi
DOMAIN=$(grep -m1 "DOMAIN=" "$DOMAIN_FILE" | cut -d'=' -f2)
log_info "Domaine chargé : $DOMAIN"

# -------------------- Arrêt des anciennes instances --------------------
OLD_PIDS=$(pgrep -f "$SCRIPT_PATH" || true)
if [[ -n "$OLD_PIDS" ]]; then
    log_info "Arrêt des anciennes instances WS (PID: $OLD_PIDS)..."
    kill -9 $OLD_PIDS || true
    sleep 2
fi

if systemctl list-units --full -all | grep -Fq "$SERVICE_NAME"; then
    log_info "Arrêt et suppression du service systemd existant..."
    systemctl stop "$SERVICE_NAME" || true
    systemctl disable "$SERVICE_NAME" || true
    rm -f /etc/systemd/system/"$SERVICE_NAME".service
    systemctl daemon-reload
fi

# -------------------- Python & venv --------------------
log_info "Vérification/installation des dépendances Python..."
apt-get update -y >/dev/null 2>&1
apt-get install -y --no-install-recommends python3 python3-venv python3-pip curl >/dev/null 2>&1 || true

if [[ ! -d "$VENV_DIR" ]]; then
    log_info "Création de l'environnement virtuel Python..."
    python3 -m venv "$VENV_DIR"
fi

log_info "Activation du venv et installation de websockets..."
source "$VENV_DIR/bin/activate"
pip install --upgrade pip setuptools
pip install websockets
deactivate

# -------------------- Service systemd --------------------
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
log_info "Création du service systemd..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=WS-only Tunnel SSH
After=network.target

[Service]
ExecStart=${VENV_DIR}/bin/python ${SCRIPT_PATH} --port ${WS_PORT}
Restart=always
RestartSec=5
User=root
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"
log_info "Service $SERVICE_NAME démarré"

# -------------------- Watchdog --------------------
WATCHDOG_SCRIPT="/usr/local/bin/ws_wss_watchdog.sh"
cat > "$WATCHDOG_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SERVICE="ws_wss_server"
while true; do
  if ! systemctl is-active --quiet "$SERVICE"; then
    logger -t ws_wss_watchdog "Service $SERVICE indisponible, redémarrage..."
    systemctl restart "$SERVICE" || logger -t ws_wss_watchdog "Échec du redémarrage du service $SERVICE"
  fi
  sleep 30
done
EOF
chmod +x "$WATCHDOG_SCRIPT"

WD_SERVICE="/etc/systemd/system/ws_wss_watchdog.service"
cat > "$WD_SERVICE" <<EOF
[Unit]
Description=Watchdog for WS-only service

[Service]
ExecStart=$WATCHDOG_SCRIPT
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ws_wss_watchdog
systemctl start ws_wss_watchdog
log_info "Watchdog installé et démarré"

# -------------------- Ouverture port TCP via iptables --------------------
if ! iptables -C INPUT -p tcp --dport $WS_PORT -j ACCEPT 2>/dev/null; then
    iptables -I INPUT -p tcp --dport $WS_PORT -j ACCEPT
fi
if ! iptables -C OUTPUT -p tcp --sport $WS_PORT -j ACCEPT 2>/dev/null; then
    iptables -I OUTPUT -p tcp --sport $WS_PORT -j ACCEPT
fi
log_info "Port TCP $WS_PORT ouvert via iptables"

# -------------------- Final --------------------
log_info "=============================================================="
log_info " 🎉 Serveur WS-only opérationnel"
log_info " WS : ws://${DOMAIN}:$WS_PORT"
log_info " Logs : ${LOG_FILE}"
log_info " Service systemd : ${SERVICE_NAME}"
log_info " Pour suivre les logs : journalctl -u ${SERVICE_NAME} -f"
log_info "=============================================================="
