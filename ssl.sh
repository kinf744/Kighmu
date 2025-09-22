#!/bin/bash
# Installation & configuration complète de Stunnel avec service systemd et port SSL fixe 444

set -e

STUNNEL_CONF="/etc/stunnel/stunnel.conf"
STUNNEL_PEM="/etc/stunnel/stunnel.pem"
LISTEN_PORT=444    # Port fixe SSL Stunnel choisi
TARGET_PORT=22     # Port local à sécuriser (ex : SSH 22)

echo "Mise à jour système..."
apt-get update && apt-get upgrade -y

echo "Installation de Stunnel4..."
apt-get install -y stunnel4

echo "Activation de stunnel au démarrage..."
sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/stunnel4

echo "Génération du certificat auto-signé..."
openssl genrsa -out /etc/stunnel/stunnel.key 2048
openssl req -new -x509 -key /etc/stunnel/stunnel.key -days 1000 -out /etc/stunnel/stunnel.crt -subj "/CN=$(hostname)"
cat /etc/stunnel/stunnel.crt /etc/stunnel/stunnel.key > $STUNNEL_PEM
chmod 600 $STUNNEL_PEM

echo "Configuration de Stunnel..."
cat > $STUNNEL_CONF <<EOF
client = no

[ssh]
accept = $LISTEN_PORT
connect = 127.0.0.1:$TARGET_PORT

cert = $STUNNEL_PEM
EOF

echo "Création d'un override systemd pour stunnel avec redémarrage automatique..."
mkdir -p /etc/systemd/system/stunnel4.service.d
cat > /etc/systemd/system/stunnel4.service.d/override.conf <<EOF
[Service]
Restart=always
RestartSec=5s
EOF

echo "Rechargement de la configuration systemd..."
systemctl daemon-reload

echo "Activation et démarrage du service Stunnel..."
systemctl enable stunnel4
systemctl restart stunnel4

echo "Installation terminée. Stunnel écoute en SSL sur le port $LISTEN_PORT et protège le port $TARGET_PORT en local."
echo "Le service est configuré pour redémarrer automatiquement en cas de plantage ou au démarrage du VPS."
