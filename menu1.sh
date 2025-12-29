#!/usr/bin/env bash
# menu1.sh — Création utilisateur (BOT COMPATIBLE)
set -euo pipefail

# ===== ARGUMENTS =====
USERNAME="${1:-}"
PASSWORD="${2:-}"
LIMITE="${3:-}"
DAYS="${4:-}"

if [[ -z "$USERNAME" || -z "$PASSWORD" || -z "$LIMITE" || -z "$DAYS" ]]; then
  echo "❌ Paramètres manquants
Usage : menu1.sh <username> <password> <limite> <jours>"
  exit 1
fi

if ! [[ "$LIMITE" =~ ^[0-9]+$ ]] || ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
  echo "❌ Limite ou durée invalide"
  exit 1
fi

# ===== CHARGEMENT CONFIG =====
if [[ -f ~/.kighmu_info ]]; then
  source ~/.kighmu_info
else
  echo "❌ Erreur : ~/.kighmu_info introuvable"
  exit 1
fi

# ===== SLOWDNS =====
SLOWDNS_KEY=""
SLOWDNS_NS=""

[[ -f /etc/slowdns/server.pub ]] && SLOWDNS_KEY=$(cat /etc/slowdns/server.pub)
[[ -f /etc/slowdns/ns.conf ]] && SLOWDNS_NS=$(cat /etc/slowdns/ns.conf)

# ===== VÉRIFICATIONS =====
if id "$USERNAME" &>/dev/null; then
  echo "❌ L'utilisateur '$USERNAME' existe déjà"
  exit 1
fi

# ===== CRÉATION =====
EXPIRE_DATE=$(date -d "+$DAYS days" '+%Y-%m-%d')
HOST_IP=$(hostname -I | awk '{print $1}')

useradd -m -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
chage -E "$EXPIRE_DATE" "$USERNAME"

# ===== SAUVEGARDE =====
USER_FILE="/etc/kighmu/users.list"
mkdir -p /etc/kighmu
touch "$USER_FILE"
chmod 600 "$USER_FILE"

echo "$USERNAME|$PASSWORD|$LIMITE|$EXPIRE_DATE|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> "$USER_FILE"

# ===== MESSAGE FINAL (INCHANGÉ) =====
cat <<EOF
+=================================================================+
*NOUVEAU UTILISATEUR CRÉÉ*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
∘ SSH: 22                  ∘ System-DNS: 53
∘ SSH WS: 80       ∘ WEB-NGINX: 81
∘ DROPBEAR: 2222             ∘ SSL: 444
∘ BadVPN: 7200             ∘ BadVPN: 7300
∘ FASTDNS: 5300            ∘ UDP-Custom: 1-65535
∘ Hysteria: 22000          ∘ Proxy WS: 9090
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DOMAIN          : $DOMAIN
Host/IP-Address : $HOST_IP
UTILISATEUR     : $USERNAME
MOT DE PASSE    : $PASSWORD
LIMITE          : $LIMITE
DATE EXPIRÉE    : $EXPIRE_DATE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🙍 SSH WS        : $DOMAIN:80@$USERNAME:$PASSWORD
🙍 SSL/TLS(SNI)  : $HOST_IP:444@$USERNAME:$PASSWORD
🙍 Proxy(WS)     : $HOST_IP:9090@$USERNAME:$PASSWORD
🙍 SSH UDP       : $HOST_IP:1-65535@$USERNAME:$PASSWORD
🙍 Hysteria UDP  : $DOMAIN:22000@$USERNAME:$PASSWORD

━━━━━━━━━━━━━━ FASTDNS PORT 5300 ━━━━━━━━━━━━━━
PUB KEY :
$SLOWDNS_KEY
NameServer (NS) : $SLOWDNS_NS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Compte créé avec succès
EOF
