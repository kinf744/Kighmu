#!/bin/bash
set -euo pipefail

# Couleurs
CYAN="\u001B[1;36m"
GREEN="\u001B[1;32m"
YELLOW="\u001B[1;33m"
RED="\u001B[1;31m"
RESET="\u001B[0m"

echo -e "${CYAN}=== Installation V2Ray WS (Port 5401) ===${RESET}"
    echo -n "Domaine/IP VPS : "; read domaine

    LOGFILE="/var/log/v2ray_install.log"
    sudo touch "$LOGFILE" && sudo chmod 640 "$LOGFILE"
    
    echo "📥 Téléchargement V2Ray... (logs: $LOGFILE)"

    # Dépendances + binaire (code robuste)
    sudo apt update && sudo apt install -y jq unzip netfilter-persistent 2>/dev/null || true
    set +e
    wget -q "https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip" -O /tmp/v2ray.zip 2>>"$LOGFILE"
    [[ $? -ne 0 ]] && { echo -e "${RED}❌ Échec téléchargement${RESET}"; return 1; }
    set -e
    unzip -o /tmp/v2ray.zip -d /tmp/v2ray >>"$LOGFILE" 2>&1 || { echo -e "${RED}❌ Échec décompression${RESET}"; return 1; }
    sudo mv /tmp/v2ray/v2ray /usr/local/bin/ && sudo chmod +x /usr/local/bin/v2ray || { echo -e "${RED}❌ Binaire manquant${RESET}"; return 1; }

    sudo mkdir -p /etc/v2ray
    echo "$domaine" | sudo tee /.v2ray_domain > /dev/null

        # ✅ CONFIG V2RAY ONLY (SANS SSH)
    cat <<EOF | sudo tee /etc/v2ray/config-v2only.json > /dev/null
{
  "log": {
    "loglevel": "info"
  },
  "inbounds": [
    {
      "port": 5401,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "00000000-0000-0000-0000-000000000001",
            "email": "default@admin"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vless-ws"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "vless"
    },
    {
      "port": 5401,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "00000000-0000-0000-0000-000000000001",
            "alterId": 0,
            "email": "default@admin"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess-ws"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "vmess"
    },
    {
      "port": 5401,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "00000000-0000-0000-0000-000000000001",
            "email": "default@admin"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/trojan-ws"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "trojan"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIP"
      }
    }
  ]
}
EOF

    # ✅ CONFIG MIX (AVEC SSH dokodemo-door)
    cat <<EOF | sudo tee /etc/v2ray/config-mix.json > /dev/null
{
  "log": {
    "loglevel": "info"
  },
  "inbounds": [
    {
      "port": 5401,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1",
        "port": 22,
        "network": "tcp"
      },
      "tag": "ssh"
    },
    {
      "port": 5401,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "00000000-0000-0000-0000-000000000001",
            "email": "default@admin"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vless-ws"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "vless"
    },
    {
      "port": 5401,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "00000000-0000-0000-0000-000000000001",
            "alterId": 0,
            "email": "default@admin"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess-ws"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "vmess"
    },
    {
      "port": 5401,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "00000000-0000-0000-0000-000000000001",
            "email": "default@admin"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/trojan-ws"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "trojan"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIP"
      }
    }
  ]
}
EOF

    # ✅ PAR DÉFAUT : V2RAY ONLY
    sudo cp /etc/v2ray/config-v2only.json /etc/v2ray/config.json

    # ✅ SERVICE SYSTEMD MODERNE
    sudo tee /etc/systemd/system/v2ray.service > /dev/null <<EOF
[Unit]
Description=V2Ray Service (WS 5401)
After=network.target
Wants=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/v2ray run -config /etc/v2ray/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    # 🚀 DÉMARRAGE + LOGS TEMPS RÉEL
    echo -e "${YELLOW}🔄 Démarrage V2Ray + LOGS TEMPS RÉEL...${RESET}"
    sudo iptables -I INPUT -p tcp --dport 5401 -j ACCEPT
    sudo netfilter-persistent save 2>/dev/null || true

    sudo systemctl daemon-reload
    sudo systemctl enable v2ray.service
    sudo systemctl restart v2ray.service &

    # LOGS TEMPS RÉEL 10s
    echo -e "${CYAN}📊 SUIVI LOGS V2Ray (5s)...${RESET}"
    timeout 5 sudo journalctl -u v2ray.service -f --no-pager | grep -E "(listener|transport|started|error)" || true

    # VÉRIFICATION FINALE
    sleep 2
    if systemctl is-active --quiet v2ray.service && ss -tuln | grep -q :5401; then
        echo -e "${GREEN}🎉 V2Ray 100% ACTIF !${RESET}"
        echo -e "${GREEN}✅ Service: $(systemctl is-active v2ray.service)${RESET}"
        echo -e "${GREEN}✅ Port: $(ss -tuln | grep :5401 | awk '{print $4" → "$5}')${RESET}"
        echo ""
        echo -e "${YELLOW}📱 CLIENT VLESS, VMESS, TROJAN :${RESET}"
        echo -e "${GREEN}IP:${RESET} $domaine:5401"
        echo -e "${GREEN}UUID:${RESET} 00000000-0000-0000-0000-000000000001"
        echo -e "${GREEN}Path:${RESET} /vless-ws | /vmess-ws | /trojan-ws"
        echo -e "${RED}⚠️ → TCP 5401 ALLOW !${RESET}"
    else
        echo -e "${RED}❌ V2Ray ÉCHEC !${RESET}"
        sudo journalctl -u v2ray.service -n 20 --no-pager
    fi

    read -p "Entrée pour continuer..."
}
