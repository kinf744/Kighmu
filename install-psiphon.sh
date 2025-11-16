#!/bin/bash

# Psiphon auto-installer pour Ubuntu 24.04+
# Installe psiphon-tunnel-core, la config, la commande globale "psiphon"
# et un service systemd qui tourne en arrière-plan.

set -e

# Couleurs simples
GREEN="e[32m"
RED="e[31m"
NC="e[0m"

echo -e "${GREEN}=== Psiphon VPS Installer (Ubuntu 24.04) ===${NC}"

# 1. Vérifications de base
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Erreur : exécute ce script en root (sudo -i ou sudo bash).${NC}"
  exit 1
fi

if ! command -v wget >/dev/null 2>&1; then
  echo -e "${GREEN}Installation de wget...${NC}"
  apt update -y
  apt install -y wget
fi

# 2. Création des dossiers
echo -e "${GREEN}Création du répertoire /etc/psiphon...${NC}"
mkdir -p /etc/psiphon

# 3. Téléchargement binaire + config
echo -e "${GREEN}Téléchargement du binaire Psiphon et de la config...${NC}"

# Binaire officiel Psiphon Tunnel Core (x86_64)
wget -q -O /etc/psiphon/psiphon-tunnel-core-x86_64 \
  https://raw.githubusercontent.com/Psiphon-Labs/psiphon-tunnel-core-binaries/master/linux/psiphon-tunnel-core-x86_64

# Fichier de config (ton JSON avec ports 8081/1081, région US, etc.)
cat >/etc/psiphon/psiphon.config << 'EOF'
{
  "LocalHttpProxyPort":8081,
  "LocalSocksProxyPort":1081,
  "EgressRegion":"US",
  "PropagationChannelId":"FFFFFFFFFFFFFFFF",
  "RemoteServerListDownloadFilename":"remote_server_list",
  "RemoteServerListSignaturePublicKey":"MIICIDANBgkqhkiG9w0BAQEFAAOCAg0AMIICCAKCAgEAt7Ls+/39r+T6zNW7GiVpJfzq/xvL9SBH5rIFnk0RXYEYavax3WS6HOD35eTAqn8AniOwiH+DOkvgSKF2caqk/y1dfq47Pdymtwzp9ikpB1C5OfAysXzBiwVJlCdajBKvBZDerV1cMvRzCKvKwRmvDmHgphQQ7WfXIGbRbmmk6opMBh3roE42KcotLFtqp0RRwLtcBRNtCdsrVsjiI1Lqz/lH+T61sGjSjQ3CHMuZYSQJZo/KrvzgQXpkaCTdbObxHqb6/+i1qaVOfEsvjoiyzTxJADvSytVtcTjijhPEV6XskJVHE1Zgl+7rATr/pDQkw6DPCNBS1+Y6fy7GstZALQXwEDN/qhQI9kWkHijT8ns+i1vGg00Mk/6J75arLhqcodWsdeG/M/moWgqQAnlZAGVtJI1OgeF5fsPpXu4kctOfuZlGjVZXQNW34aOzm8r8S0eVZitPlbhcPiR4gT/aSMz/wd8lZlzZYsje/Jr8u/YtlwjjreZrGRmG8KMOzukV3lLmMppXFMvl4bxv6YFEmIuTsOhbLTwFgh7KYNjodLj/LsqRVfwz31PgWQFTEPICV7GCvgVlPRxnofqKSjgTWI4mxDhBpVcATvaoBl1L/6WLbFvBsoAUBItWwctO2xalKxF5szhGm8lccoc5MZr8kfE0uxMgsxz4er68iCID+rsCAQM=",
  "RemoteServerListUrl":"https://s3.amazonaws.com//psiphon/web/mjr4-p23r-puwl/server_list_compressed",
  "SponsorId":"FFFFFFFFFFFFFFFF",
  "UseIndistinguishableTLS":true
}
EOF

# 4. Script de démarrage global /usr/bin/psiphon
echo -e "${GREEN}Création de la commande globale 'psiphon'...${NC}"

cat >/usr/bin/psiphon << 'EOF'
#!/bin/bash
# Wrapper simple pour lancer Psiphon tunnel core avec la config globale

CONFIG_FILE="/etc/psiphon/psiphon.config"
BIN="/etc/psiphon/psiphon-tunnel-core-x86_64"

if [ ! -f "$BIN" ]; then
  echo "Erreur : binaire Psiphon introuvable à $BIN"
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Erreur : fichier de configuration Psiphon introuvable à $CONFIG_FILE"
  exit 1
fi

echo "Démarrage de Psiphon..."
echo "HTTP/HTTPS proxy local : 127.0.0.1:8081"
echo "SOCKS5 proxy local     : 127.0.0.1:1081"
echo "Appuie sur CTRL+C pour arrêter."

exec "$BIN" -config "$CONFIG_FILE"
EOF

chmod +x /etc/psiphon/psiphon-tunnel-core-x86_64
chmod +x /usr/bin/psiphon

# 5. Service systemd (optionnel mais conseillé)
echo -e "${GREEN}Création du service systemd psiphon.service...${NC}"

cat >/etc/systemd/system/psiphon.service << 'EOF'
[Unit]
Description=Psiphon Tunnel Core Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/psiphon
ExecStart=/etc/psiphon/psiphon-tunnel-core-x86_64 -config /etc/psiphon/psiphon.config
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable psiphon.service

# 6. Vérifications rapides
echo -e "${GREEN}Vérifications des fichiers installés...${NC}"

if [ -f /etc/psiphon/psiphon-tunnel-core-x86_64 ]; then
  echo -e "${GREEN}OK${NC} - binaire Psiphon trouvé"
else
  echo -e "${RED}ERREUR${NC} - binaire Psiphon manquant"
fi

if [ -f /etc/psiphon/psiphon.config ]; then
  echo -e "${GREEN}OK${NC} - configuration Psiphon trouvée"
else
  echo -e "${RED}ERREUR${NC} - configuration Psiphon manquante"
fi

if [ -x /usr/bin/psiphon ]; then
  echo -e "${GREEN}OK${NC} - commande globale 'psiphon' prête"
else
  echo -e "${RED}ERREUR${NC} - /usr/bin/psiphon n'est pas exécutable"
fi

echo -e "${GREEN}Installation terminée.${NC}"
echo
echo "Commandes utiles :"
echo "  psiphon                # lance Psiphon au premier plan (CTRL+C pour arrêter)"
echo "  systemctl start psiphon.service   # démarre Psiphon en service"
echo "  systemctl stop psiphon.service    # arrête le service"
echo "  systemctl status psiphon.service  # état du service"
echo
echo "Psiphon écoute en local sur :"
echo "  HTTP/HTTPS : 127.0.0.1:8081"
echo "  SOCKS5     : 127.0.0.1:1081"
echo
echo -e "${GREEN}Tu peux maintenant chaîner ces proxys avec tes tunnels (HTTP Custom, SSH, Xray, etc.).${NC}"
