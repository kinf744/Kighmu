#!/usr/bin/env bash
# ============================================================
# Script : ws_wssr.sh
# Description : Gestion et supervision du tunnel WS/WSS SSH
# Auteur : Kinf744
# Version : 2.0
# ============================================================

set -e

SERVICE_NAME="ws_wss_server"
SCRIPT_PATH="/usr/local/bin/ws_wss_server.py"
LOG_FILE="/var/log/ws_wss_server.log"
PYTHON_BIN=$(command -v python3 || command -v python)
DOMAIN_FILE="$HOME/.kighmu_info"

# ============================================================
# 🔧 Vérification du domaine configuré
# ============================================================
if [[ ! -f "$DOMAIN_FILE" ]]; then
  echo "❌ Fichier ~/.kighmu_info introuvable ! Exécute d'abord ton script d'installation Kighmu."
  exit 1
fi

DOMAIN=$(grep -m1 "DOMAIN=" "$DOMAIN_FILE" | cut -d'=' -f2)
if [[ -z "$DOMAIN" ]]; then
  echo "❌ Domaine introuvable dans ~/.kighmu_info"
  exit 1
fi

# ============================================================
# 🧩 Vérification de Python et dépendances
# ============================================================
echo "🔍 Vérification de l’environnement Python..."
apt-get update -y >/dev/null 2>&1
apt-get install -y python3 python3-pip certbot >/dev/null 2>&1

pip3 install websockets >/dev/null 2>&1

# ============================================================
# 📜 Création du service systemd
# ============================================================
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo "⚙️ Configuration du service systemd : ${SERVICE_FILE}"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Kighmu WS/WSS Tunnel SSH
After=network.target

[Service]
ExecStart=${PYTHON_BIN} ${SCRIPT_PATH}
Restart=always
RestartSec=5
User=root
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "$SERVICE_FILE"

# ============================================================
# 🔐 Gestion des certificats Let's Encrypt
# ============================================================
CERT_PATH="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

if [[ ! -f "$CERT_PATH" || ! -f "$KEY_PATH" ]]; then
  echo "📜 Génération automatique du certificat Let's Encrypt pour ${DOMAIN}..."
  systemctl stop nginx 2>/dev/null || true
  certbot certonly --standalone -d "$DOMAIN" --agree-tos -m "admin@${DOMAIN}" --non-interactive || {
    echo "⚠️ Échec de Let's Encrypt — création d’un certificat auto-signé..."
    mkdir -p /etc/ssl/kighmu
    openssl req -x509 -newkey rsa:2048 -nodes \
      -keyout /etc/ssl/kighmu/key.pem \
      -out /etc/ssl/kighmu/cert.pem \
      -days 365 \
      -subj "/CN=${DOMAIN}"
  }
fi

# ============================================================
# 🚀 Lancement et activation du service
# ============================================================
echo "🚀 Activation et démarrage du service WS/WSS..."

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl restart "${SERVICE_NAME}"

sleep 2

if systemctl is-active --quiet "${SERVICE_NAME}"; then
  echo "✅ Service ${SERVICE_NAME} démarré avec succès."
else
  echo "❌ Échec du démarrage du service. Consulte les logs avec :"
  echo "   journalctl -u ${SERVICE_NAME} -f"
  exit 1
fi

# ============================================================
# 📋 Informations finales
# ============================================================
echo
echo "=============================================================="
echo " 🎉 Serveur WS/WSS opérationnel"
echo "--------------------------------------------------------------"
echo " Domaine utilisé   : ${DOMAIN}"
echo " WS (non sécurisé) : ws://${DOMAIN}:8880"
echo " WSS (sécurisé)    : wss://${DOMAIN}:443"
echo " Logs              : ${LOG_FILE}"
echo " Service systemd   : ${SERVICE_NAME}"
echo " Pour voir les logs : journalctl -u ${SERVICE_NAME} -f"
echo "=============================================================="
echo
