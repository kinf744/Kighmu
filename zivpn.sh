#!/bin/bash
set -euo pipefail

echo "=== Installation ZIVPN UDP (clean & nftables) ==="

# ===================== DEPENDANCES =====================
apt update -y
apt install -y wget curl jq nftables openssl socat

systemctl stop zivpn.service >/dev/null 2>&1 || true

# ===================== INSTALL BINARY =====================
echo "[+] Téléchargement ZIVPN"
wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 \
    -O /usr/local/bin/zivpn
chmod +x /usr/local/bin/zivpn

# ===================== CONFIG =====================
mkdir -p /etc/zivpn

cat <<EOF > /etc/zivpn/config.json
{
  "listen": ":5667",
  "config": []
}
EOF

# ===================== CERTIFICATS TLS =====================
TLS_DIR="/etc/ssl/kighmu"
CERT="$TLS_DIR/fullchain.crt"
KEY="$TLS_DIR/private.key"
DOMAIN_FILE="/etc/xray/domain"   # ou autre fichier contenant ton domaine

mkdir -p "$TLS_DIR"

if [[ ! -f "$DOMAIN_FILE" ]]; then
    echo "❌ Domaine introuvable ($DOMAIN_FILE)"
    exit 1
fi

EMAIL="adrienkiaje@gmail.com"

DOMAIN_FILE="/etc/xray/domain"
TLS_DIR="/etc/ssl/kighmu"

# Créer les dossiers si nécessaire
mkdir -p "$(dirname "$DOMAIN_FILE")"
mkdir -p "$TLS_DIR"

# Vérifier si le domaine existe
if [[ -f "$DOMAIN_FILE" ]]; then
    DOMAIN=$(cat "$DOMAIN_FILE")
else
    read -rp "Entrez votre nom de domaine pour ZIVPN : " DOMAIN
    if [[ -z "$DOMAIN" ]]; then
        echo "❌ Domaine non valide."
        exit 1
    fi
    echo "$DOMAIN" > "$DOMAIN_FILE"
fi

# Certificat déjà existant → réutilisation
if [[ -f "$CERT" && -f "$KEY" ]]; then
    echo "🔐 Certificat TLS existant trouvé → réutilisation"
else
    echo "[+] Génération certificat TLS via acme.sh pour $DOMAIN"
    # Installer acme.sh si absent
    if [[ ! -d "$HOME/.acme.sh" ]]; then
        curl -s https://get.acme.sh | sh
    fi

    ~/.acme.sh/acme.sh --register-account -m "$EMAIL" || true
    ~/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN" --force
    ~/.acme.sh/acme.sh --installcert -d "$DOMAIN" \
        --fullchainpath "$CERT" \
        --keypath "$KEY"

    chmod 600 "$KEY"
    echo "✅ Certificat TLS généré avec succès"
fi

# Lien vers ZIVPN
ln -sf "$CERT" /etc/zivpn/zivpn.crt
ln -sf "$KEY" /etc/zivpn/zivpn.key

# ===================== SYSCTL (persistant) =====================
cat <<EOF > /etc/sysctl.d/99-zivpn.conf
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF
sysctl --system >/dev/null

# ===================== SYSTEMD =====================
cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=ZIVPN UDP Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
WorkingDirectory=/etc/zivpn
Restart=always
RestartSec=3
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable zivpn
systemctl start zivpn

# ===================== NFTABLES =====================
echo "[+] Configuration nftables"

mkdir -p /etc/nftables.d

cat <<EOF > /etc/nftables.d/zivpn.nft
table inet zivpn {

    chain prerouting {
        type nat hook prerouting priority -100;
        udp dport 6000-19999 dnat to :5667
    }

    chain input {
        type filter hook input priority 0;
        udp dport 5667 accept
        udp dport 6000-19999 accept
    }
}
EOF

# Activer nftables
systemctl enable nftables
systemctl start nftables

# Charger la règle
nft -f /etc/nftables.d/zivpn.nft

# Rendre persistant
if ! grep -q nftables.d /etc/nftables.conf 2>/dev/null; then
    echo 'include "/etc/nftables.d/*.nft"' >> /etc/nftables.conf
fi

systemctl restart nftables

# ===================== FIN =====================
echo ""
echo "✅ ZIVPN installé avec succès"
echo "➡️ Port interne : 5667"
echo "➡️ Ports externes : UDP 6000–19999"
echo "➡️ Authentification : gérée par menu1.sh"
echo "➡️ Firewall : nftables"
echo "➡️ Certificat TLS : $CERT / $KEY"
echo ""
