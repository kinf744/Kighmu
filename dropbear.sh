#!/bin/bash
set -euo pipefail

PORT=109
LOG_DIR="/var/log/dropbear"
LOG_FILE="$LOG_DIR/dropbear-109.log"
CONF_FILE="/etc/dropbear/dropbear_109.conf"
SERVICE_FILE="/etc/systemd/system/dropbear-109.service"

echo "[+] Installation de Dropbear"
apt update -y
apt install -y dropbear

echo "[+] Création du dossier de logs"
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
chmod 640 "$LOG_FILE"
chown root:adm "$LOG_FILE"

echo "[+] Configuration Dropbear (port $PORT)"
mkdir -p /etc/dropbear
cat > "$CONF_FILE" <<EOF
DROPBEAR_PORT=$PORT
DROPBEAR_EXTRA_ARGS="-w -g -E"
EOF

echo "[+] Création du service systemd dédié"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Dropbear SSH Server (VPN) - Port $PORT
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/dropbear -F -p $PORT -w -g -E
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

echo "[+] Désactivation du service dropbear par défaut (sécurité)"
systemctl stop dropbear 2>/dev/null || true
systemctl disable dropbear 2>/dev/null || true

echo "[+] Activation du service dropbear-109"
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable dropbear-109
systemctl restart dropbear-109

echo "[+] Vérification des ports"
ss -tlnp | grep ":$PORT" || {
  echo "[ERREUR] Dropbear n'écoute pas sur le port $PORT"
  exit 1
}

echo
echo "======================================"
echo " Dropbear VPN actif"
echo " Port           : $PORT"
echo " Bannière       : SSH-2.0-dropbear_XXXX.XX"
echo " Logs           : $LOG_FILE"
echo " Service        : dropbear-109.service"
echo "======================================"
