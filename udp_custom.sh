#!/bin/bash
# UDP Custom v2.0 - Auth PAM Linux (fichier unique)
set -euo pipefail

UDP_PORT=36712
BIN_PATH="/usr/local/bin/udp-custom"
CONFIG_FILE="/etc/udp-custom/config.json"
AUTH_SCRIPT="/usr/local/bin/udp-auth.sh"
SERVICE_NAME="udp-custom.service"

# ─────────────────────────────────────────
# 1️⃣ CLEAN TOTAL
# ─────────────────────────────────────────
echo "🧹 Nettoyage..."
systemctl stop "$SERVICE_NAME" 2>/dev/null || true
rm -f "/etc/systemd/system/$SERVICE_NAME"
rm -rf /opt/udp-custom /var/log/udp-custom
userdel udpuser 2>/dev/null || true

# ─────────────────────────────────────────
# 2️⃣ DÉPENDANCES
# ─────────────────────────────────────────
echo "📦 Installation des dépendances..."
apt-get install -y python3 python3-pam 2>/dev/null || true

# ─────────────────────────────────────────
# 3️⃣ BINAIRE
# ─────────────────────────────────────────
echo "⬇️ Téléchargement du binaire..."
wget -q "https://github.com/kinf744/Kighmu/releases/download/v1.0.0/udp-custom" -O "$BIN_PATH"
chmod +x "$BIN_PATH"

# ─────────────────────────────────────────
# 4️⃣ SCRIPT AUTH PAM (embarqué)
# ─────────────────────────────────────────
echo "🔐 Création du script d'authentification PAM..."
cat > "$AUTH_SCRIPT" << 'AUTHEOF'
#!/bin/bash
# udp-auth.sh - Authentification PAM Linux pour UDP Custom
USERNAME="$1"
PASSWORD="$2"

# Arguments manquants
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    exit 1
fi

# Utilisateur inexistant
if ! id "$USERNAME" &>/dev/null; then
    exit 1
fi

# Compte expiré
EXPIRE=$(chage -l "$USERNAME" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
if [ "$EXPIRE" != "never" ] && [ -n "$EXPIRE" ]; then
    EXPIRE_TS=$(date -d "$EXPIRE" +%s 2>/dev/null || echo 0)
    NOW_TS=$(date +%s)
    if [ "$EXPIRE_TS" -lt "$NOW_TS" ]; then
        exit 1
    fi
fi

# Méthode 1 : python3-pam (recommandée)
if command -v python3 &>/dev/null && python3 -c "import pam" &>/dev/null 2>&1; then
    python3 - "$USERNAME" "$PASSWORD" << 'PYEOF'
import pam, sys
p = pam.pam()
sys.exit(0 if p.authenticate(sys.argv[1], sys.argv[2]) else 1)
PYEOF
    exit $?
fi

# Méthode 2 : fallback /etc/shadow
SHADOW_ENTRY=$(getent shadow "$USERNAME" 2>/dev/null)
if [ -z "$SHADOW_ENTRY" ]; then exit 1; fi

SHADOW_HASH=$(echo "$SHADOW_ENTRY" | cut -d: -f2)
if [[ "$SHADOW_HASH" == "!"* ]] || [[ "$SHADOW_HASH" == "*"* ]]; then exit 1; fi

HASH_TYPE=$(echo "$SHADOW_HASH" | cut -d'$' -f2)
SALT=$(echo "$SHADOW_HASH" | cut -d'$' -f3)

case "$HASH_TYPE" in
    6)
        INPUT_HASH=$(python3 -c "
import crypt, sys
print(crypt.crypt(sys.argv[1], '\$6\$' + sys.argv[2]))
" "$PASSWORD" "$SALT" 2>/dev/null) ;;
    5)
        INPUT_HASH=$(python3 -c "
import crypt, sys
print(crypt.crypt(sys.argv[1], '\$5\$' + sys.argv[2]))
" "$PASSWORD" "$SALT" 2>/dev/null) ;;
    *)
        exit 1 ;;
esac

[ "$SHADOW_HASH" = "$INPUT_HASH" ] && exit 0 || exit 1
AUTHEOF
chmod +x "$AUTH_SCRIPT"

# ─────────────────────────────────────────
# 5️⃣ CONFIG UDP CUSTOM
# ─────────────────────────────────────────
echo "⚙️ Création de la configuration..."
mkdir -p /etc/udp-custom
cat > "$CONFIG_FILE" << EOF
{
  "listen": ":${UDP_PORT}",
  "exclude_port": [53, 5300, 5667, 20000, 4466],
  "timeout": 600,
  "auth": {
    "mode": "cmd",
    "config": ["$AUTH_SCRIPT"]
  }
}
EOF

# ─────────────────────────────────────────
# 6️⃣ IPTABLES
# ─────────────────────────────────────────
echo "🔥 Configuration iptables..."
iptables -C INPUT -p udp --dport "$UDP_PORT" -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport "$UDP_PORT" -j ACCEPT
netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4

# ─────────────────────────────────────────
# 7️⃣ SYSTEMD
# ─────────────────────────────────────────
echo "🔧 Création du service systemd..."
cat > "/etc/systemd/system/$SERVICE_NAME" << EOF
[Unit]
Description=UDP Custom Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BIN_PATH server -c $CONFIG_FILE
Restart=always
RestartSec=5
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal
SyslogIdentifier=udp-custom

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

# ─────────────────────────────────────────
# 8️⃣ TEST FINAL
# ─────────────────────────────────────────
sleep 3
echo ""
if systemctl is-active --quiet "$SERVICE_NAME"; then
    IP=$(hostname -I | awk '{print $1}')
    echo "✅ UDP Custom OK → $IP:$UDP_PORT"
    echo "🔐 Auth : PAM Linux (username/password système)"
    echo "📱 Connexion : udp://$IP:$UDP_PORT"
    echo ""
    ss -ulnp | grep "$UDP_PORT" || true
else
    echo "❌ ÉCHEC → Logs:"
    journalctl -u "$SERVICE_NAME" -n 20
    exit 1
fi
