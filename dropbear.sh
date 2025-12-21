#!/bin/bash
set -euo pipefail

# --- VARIABLES ---
DROPBEAR_BIN="/usr/sbin/dropbear"
DROPBEAR_CONF="/etc/default/dropbear"
DROPBEAR_LOG="/var/log/dropbear_custom.log"
DROPBEAR_PORTS=(22 109)
SYSTEMD_SERVICE="/etc/systemd/system/dropbear-custom.service"

# --- DETECTION VERSION UBUNTU ---
UBUNTU_VERSION=$(lsb_release -rs)
case "$UBUNTU_VERSION" in
  "20.04") DROPBEAR_VER="2019.78" ;;
  "22.04") DROPBEAR_VER="2020.81" ;;
  "24.04") DROPBEAR_VER="2024.84" ;;
  *) DROPBEAR_VER="2024.84" ;;
esac
BANNER="SSH-2.0-dropbear_$DROPBEAR_VER"

# --- INSTALLATION DROPBEAR ---
if ! command -v dropbear >/dev/null 2>&1; then
    echo "[INFO] Installation de Dropbear..."
    apt-get update -q
    DEBIAN_FRONTEND=noninteractive apt-get install -y dropbear
fi

# --- DESACTIVER OPENSSH ---
if systemctl is-active --quiet ssh; then
    echo "[INFO] Désactivation de OpenSSH..."
    systemctl stop ssh
    systemctl disable ssh
fi

# --- CONFIG DROPBEAR ---
mkdir -p /etc/dropbear
echo "DROPBEAR_PORT=${DROPBEAR_PORTS[0]}" > $DROPBEAR_CONF
echo "DROPBEAR_EXTRA_ARGS='$(printf " -p %s" "${DROPBEAR_PORTS[@]}") -F -E -m'" >> $DROPBEAR_CONF

# --- SYSTEMD SERVICE PERSONNALISE ---
cat <<EOF > $SYSTEMD_SERVICE
[Unit]
Description=Dropbear SSH Custom
After=network.target

[Service]
ExecStart=$DROPBEAR_BIN -F -E -m $(printf " -p %s" "${DROPBEAR_PORTS[@]}")
Restart=on-failure
StandardOutput=syslog
StandardError=syslog

[Install]
WantedBy=multi-user.target
EOF

# --- LOG FILE ---
touch $DROPBEAR_LOG
chmod 600 $DROPBEAR_LOG

# --- IPTABLES ---
# Autoriser uniquement les ports Dropbear et bloquer tout conflit potentiel
for port in "${DROPBEAR_PORTS[@]}"; do
    if ! iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
        iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
    fi
done

# --- ACTIVER SERVICE ---
systemctl daemon-reload
systemctl enable dropbear-custom
systemctl restart dropbear-custom || {
    echo "[ERREUR] Impossible de démarrer Dropbear. Vérifiez les logs:"
    echo "journalctl -xeu dropbear-custom.service"
    exit 1
}

# --- BANNIERE ---
echo "[INFO] Dropbear actif sur ports: ${DROPBEAR_PORTS[*]}"
echo "[INFO] BANNIERE: $BANNER"
echo "[INFO] Logs: $DROPBEAR_LOG"
