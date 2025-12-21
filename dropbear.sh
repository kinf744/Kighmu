#!/bin/bash
set -euo pipefail

# ==============================
# VARIABLES
# ==============================
DROPBEAR_BIN="/usr/bin/dropbear"
DROPBEAR_CONF="/etc/default/dropbear"
DROPBEAR_LOG="/var/log/dropbear_custom.log"
DROPBEAR_PORTS=(22 109)
SYSTEMD_SERVICE="/etc/systemd/system/dropbear-custom.service"

# ==============================
# DETECTION VERSION UBUNTU
# ==============================
UBUNTU_VERSION=$(lsb_release -rs)
case "$UBUNTU_VERSION" in
    "20.04") DROPBEAR_VER="2019.78" ;;
    "22.04") DROPBEAR_VER="2020.81" ;;
    "24.04") DROPBEAR_VER="2024.84" ;;
    *) DROPBEAR_VER="2024.84" ;;
esac
BANNER="SSH-2.0-dropbear_$DROPBEAR_VER"

# ==============================
# INSTALLATION DROPBEAR
# ==============================
if ! command -v dropbear >/dev/null 2>&1; then
    echo "[INFO] Installation de Dropbear..."
    apt-get update -q
    DEBIAN_FRONTEND=noninteractive apt-get install -y dropbear
fi

# ==============================
# DESACTIVER COMPLETEMENT OPENSSH
# ==============================
echo "[INFO] Arrêt et désactivation d'OpenSSH..."
systemctl stop ssh.service ssh.socket || true
systemctl disable ssh.service ssh.socket || true

# ==============================
# VERIFIER QUE LES PORTS SONT LIBRES
# ==============================
for port in "${DROPBEAR_PORTS[@]}"; do
    if ss -tulpn | grep -q ":$port "; then
        echo "[ERREUR] Le port $port est déjà utilisé. Libérez-le avant de continuer."
        exit 1
    fi
done

# ==============================
# CONFIGURATION DROPBEAR
# ==============================
mkdir -p /etc/dropbear
echo "DROPBEAR_PORT=${DROPBEAR_PORTS[0]}" > "$DROPBEAR_CONF"
echo "DROPBEAR_EXTRA_ARGS='$(printf " -p %s" "${DROPBEAR_PORTS[@]}") -F -E -m'" >> "$DROPBEAR_CONF"

# ==============================
# SERVICE SYSTEMD PERSONNALISE
# ==============================
cat <<EOF > "$SYSTEMD_SERVICE"
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

# ==============================
# LOG
# ==============================
touch "$DROPBEAR_LOG"
chmod 600 "$DROPBEAR_LOG"

# ==============================
# IPTABLES
# ==============================
for port in "${DROPBEAR_PORTS[@]}"; do
    if ! iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
        iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
    fi
done

# ==============================
# ACTIVER ET DEMARRER LE SERVICE
# ==============================
systemctl daemon-reload
systemctl enable dropbear-custom
systemctl restart dropbear-custom

# ==============================
# AFFICHAGE INFO
# ==============================
echo "[OK] Dropbear est actif sur les ports: ${DROPBEAR_PORTS[*]}"
echo "[OK] Bannière: $BANNER"
echo "[OK] Logs: $DROPBEAR_LOG"
echo "[INFO] Vérifiez la bannière: nc 127.0.0.1 ${DROPBEAR_PORTS[0]}"
