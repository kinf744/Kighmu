#!/bin/bash

# Variables email et domaine
EMAIL="adrienkiaje@gmail.com"
read -rp "Entrez votre nom de domaine (ex: monsite.com) : " DOMAIN
if [ -z "$DOMAIN" ]; then
  echo "Erreur : nom de domaine non valide."
  exit 1
fi
echo "$DOMAIN" > /tmp/.xray_domain

# Installation dépendances et outils système complets
apt update && apt install -y curl unzip sudo socat snapd iptables iptables-persistent \
  xz-utils apt-transport-https gnupg gnupg2 gnupg1 dnsutils lsb-release cron bash-completion ntpdate chrony || { echo "Erreur installation dépendances"; exit 1; }

# Synchronisation temps et timezone
ntpdate pool.ntp.org
timedatectl set-ntp true
systemctl enable chronyd && systemctl restart chronyd
systemctl enable chrony && systemctl restart chrony
timedatectl set-timezone Asia/Kuala_Lumpur

# Téléchargement de la dernière version Xray Core depuis GitHub
latest_version="$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep tag_name | sed -E 's/.*"v(.*)".*/\1/' | head -n 1)"
xraycore_link="https://github.com/XTLS/Xray-core/releases/download/v${latest_version}/Xray-linux-64.zip"

# Arrêt services sur port 80
systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true
sudo lsof -t -i tcp:80 -s tcp:listen | sudo xargs kill 2>/dev/null || true

# Téléchargement et installation Xray
mkdir -p /usr/local/bin
cd $(mktemp -d)
curl -sL "$xraycore_link" -o xray.zip
unzip -q xray.zip && rm -f xray.zip
mv xray /usr/local/bin/xray
chmod +x /usr/local/bin/xray
sudo setcap 'cap_net_bind_service=+ep' /usr/local/bin/xray

# Préparation dossiers logs et config
mkdir -p /var/log/xray /usr/local/etc/xray
chown -R nobody:nogroup /var/log/xray

# Installation et configuration acme.sh pour certificat TLS
cd /root/
wget -q https://raw.githubusercontent.com/acmesh-official/acme.sh/master/acme.sh
bash acme.sh --install --quiet
export PATH="${HOME}/.acme.sh:$PATH"
bash $HOME/.acme.sh/acme.sh --register-account -m "$EMAIL" --quiet
bash $HOME/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN" --force --quiet
bash $HOME/.acme.sh/acme.sh --installcert -d "$DOMAIN" --fullchainpath /etc/xray/xray.crt --keypath /etc/xray/xray.key --quiet

CRT_PATH="/etc/xray/xray.crt"
KEY_PATH="/etc/xray/xray.key"
if [[ ! -f "$CRT_PATH" || ! -f "$KEY_PATH" ]]; then
  echo "Erreur : certificats TLS non trouvés après acme.sh"
  exit 1
fi

# Génération UUIDs multiples pour config
uuid1=$(cat /proc/sys/kernel/random/uuid)
uuid2=$(cat /proc/sys/kernel/random/uuid)
uuid3=$(cat /proc/sys/kernel/random/uuid)
uuid4=$(cat /proc/sys/kernel/random/uuid)
uuid5=$(cat /proc/sys/kernel/random/uuid)
TROJAN_PASS=$(openssl rand -base64 16)

# Création fichier configuration Xray complet avec options enrichies
cat > /usr/local/etc/xray/config.json << EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "info"
  },
  "inbounds": [
    {
      "port": 8443,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${uuid1}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "$CRT_PATH",
              "keyFile": "$KEY_PATH"
            }
          ]
        },
        "wsSettings": {
          "path": "/vmess",
          "headers": {
            "Host": "$DOMAIN"
          }
        }
      }
    },
    {
      "port": 80,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${uuid2}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vmess",
          "headers": {
            "Host": "$DOMAIN"
          }
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "port": 8443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid3}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "$CRT_PATH",
              "keyFile": "$KEY_PATH"
            }
          ]
        },
        "wsSettings": {
          "path": "/vless",
          "headers": {
            "Host": "$DOMAIN"
          }
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "port": 80,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid4}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vless",
          "headers": {
            "Host": "$DOMAIN"
          }
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "port": 2083,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "$TROJAN_PASS"
          }
        ],
        "fallbacks": [
          {
            "dest": 80
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "$CRT_PATH",
              "keyFile": "$KEY_PATH"
            }
          ],
          "alpn": ["http/1.1"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8",
          "10.0.0.0/8",
          "100.64.0.0/10",
          "169.254.0.0/16",
          "172.16.0.0/12",
          "192.0.0.0/24",
          "192.0.2.0/24",
          "192.168.0.0/16",
          "198.18.0.0/15",
          "198.51.100.0/24",
          "203.0.113.0/24",
          "::1/128",
          "fc00::/7",
          "fe80::/10"
        ],
        "outboundTag": "blocked"
      }
    ]
  },
  "policy": {
    "levels": {
      "0": {
        "statsUserDownlink": true,
        "statsUserUplink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true
    }
  },
  "stats": {},
  "api": {
    "services": ["StatsService"],
    "tag": "api"
  }
}
EOF

# Création et configuration du service systemd Xray avec options de sécurité
cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service Modifié
After=network.target nss-lookup.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF

# Ouverture des ports dans iptables avec persistance
for port in 80 443 8443 2083; do
  iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport $port -j ACCEPT
  iptables -I INPUT -m state --state NEW -m udp -p udp --dport $port -j ACCEPT
done
iptables-save > /etc/iptables.up.rules
iptables-restore -t < /etc/iptables.up.rules
netfilter-persistent save
netfilter-persistent reload

# Activation et démarrage du service Xray
systemctl daemon-reload
systemctl enable xray
systemctl restart xray
if systemctl is-active --quiet xray; then
  echo "Xray service démarré avec succès."
else
  echo "Erreur : le service Xray ne démarre pas."
  journalctl -u xray -n 20 --no-pager
  exit 1
fi

# Script renouvellement automatique Certificat + redémarrage Xray
cat > /usr/local/bin/renew-cert-xray.sh << 'EOS'
#!/bin/bash
~/.acme.sh/acme.sh --cron --home ~/.acme.sh
systemctl restart xray
EOS
chmod +x /usr/local/bin/renew-cert-xray.sh
(crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/renew-cert-xray.sh") | crontab -

# Résumé des infos importantes
echo "----- XRAY ${latest_version} installé avec certificat acme.sh -----"
echo "Domaine : $DOMAIN"
echo "UUID VMess TLS : $uuid1"
echo "UUID VMess Non-TLS : $uuid2"
echo "UUID VLESS TLS : $uuid3"
echo "UUID VLESS Non-TLS : $uuid4"
echo "Mot de passe Trojan (TLS 2083) : $TROJAN_PASS"
echo "Certificat : $CRT_PATH"
echo "Clé privée : $KEY_PATH"
echo "Ports ouverts : 80, 443, 8443, 2083"
echo ""
echo "Assure-toi d'ouvrir ces ports dans le firewall si nécessaire."

exit 0
