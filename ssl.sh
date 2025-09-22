#!/bin/bash
# Installation & configuration complète de Stunnel avec service systemd et port SSL fixe 444 optimisé

set -e

STUNNEL_CONF="/etc/stunnel/stunnel.conf"
STUNNEL_PEM="/etc/stunnel/stunnel.pem"
STUNNEL_KEY="/etc/stunnel/stunnel.key"
STUNNEL_CRT="/etc/stunnel/stunnel.crt"
LISTEN_PORT=444    # Port fixe SSL Stunnel choisi
TARGET_PORT=22     # Port local à sécuriser (ex : SSH 22)
LOG_FILE="/var/log/stunnel4/stunnel.log"

echo "Mise à jour système..."
apt-get update && apt-get upgrade -y

echo "Installation de Stunnel4..."
apt-get install -y stunnel4
apt-get install -y ufw

echo "Activation de stunnel au démarrage..."
sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/stunnel4

# Backup de la configuration existante
if [ -f "$STUNNEL_CONF" ]; then
    echo "Backup de la configuration existante de Stunnel..."
    mv "$STUNNEL_CONF" "$STUNNEL_CONF.bak.$(date +%F_%T)"
fi

echo "Génération du certificat auto-signé sécurisé..."
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$STUNNEL_KEY"
openssl req -new -x509 -key "$STUNNEL_KEY" -days 3650 -out "$STUNNEL_CRT" -subj "/CN=$(hostname)"

cat "$STUNNEL_CRT" "$STUNNEL_KEY" > "$STUNNEL_PEM"
chmod 600 "$STUNNEL_PEM"

echo "Création fichier log Stunnel..."
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

echo "Configuration de Stunnel..."
cat > "$STUNNEL_CONF" << EOF
setuid = stunnel4
setgid = stunnel4
pid = /var/run/stunnel4.pid
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
client = no
foreground = no
output = $LOG_FILE

[ssh]
accept = $LISTEN_PORT
connect = 127.0.0.1:$TARGET_PORT
cert = $STUNNEL_PEM
EOF

echo "Création d'un override systemd pour stunnel avec redémarrage automatique..."
mkdir -p /etc/systemd/system/stunnel4.service.d
cat > /etc/systemd/system/stunnel4.service.d/override.conf << EOF
[Service]
Restart=always
RestartSec=5s
EOF

echo "Rechargement de la configuration systemd..."
systemctl daemon-reload

echo "Activation et démarrage du service Stunnel..."
systemctl enable stunnel4
systemctl restart stunnel4

echo "Ouverture du port $LISTEN_PORT dans le firewall UFW (si utilisé)..."
if command -v ufw &> /dev/null; then
    ufw allow $LISTEN_PORT/tcp
    ufw reload
else
    echo "UFW non installé ou non présent, vérifier le firewall manuellement."
fi

echo "Installation terminée. Stunnel écoute en SSL sur le port $LISTEN_PORT et protège le port $TARGET_PORT en local."
echo "Le service est configuré pour redémarrer automatiquement en cas de plantage ou au démarrage du VPS."
echo "Les logs Stunnel sont disponibles dans : $LOG_FILE"
