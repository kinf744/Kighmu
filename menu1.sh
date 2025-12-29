#!/bin/bash
# ===============================================
# Kighmu VPS Manager - Création Utilisateur Test
# Compatible BOT Telegram + Local
# ===============================================
set -euo pipefail

# ===============================
# DÉTECTION MODE BOT
# ===============================
BOT_MODE=false
if [[ $# -ge 4 ]]; then
    BOT_MODE=true
    username="$1"
    password="$2"
    limite="$3"
    minutes="$4"
fi

# ===============================
# COULEURS (désactivées en mode BOT)
# ===============================
if $BOT_MODE; then
    RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""; BOLD=""; RESET=""
    export TERM=dumb
else
    RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"
    MAGENTA="\e[35m"; CYAN="\e[36m"; BOLD="\e[1m"; RESET="\e[0m"
fi

# ===============================
# ROOT
# ===============================
if [[ $EUID -ne 0 ]]; then
  echo "Erreur : ce script doit être lancé avec les droits root."
  exit 1
fi

# ===============================
# CONFIG GLOBALE
# ===============================
if [ -f ~/.kighmu_info ]; then
    source ~/.kighmu_info
else
    echo "Erreur : fichier ~/.kighmu_info introuvable."
    exit 1
fi

# ===============================
# AUTO SSH SHELL
# ===============================
detect_ssh_shell() {
    if pgrep -x dropbear >/dev/null 2>&1 || systemctl is-active --quiet dropbear 2>/dev/null; then
        echo "/usr/sbin/nologin"
        return
    fi
    if pgrep -x sshd >/dev/null 2>&1 || systemctl is-active --quiet ssh 2>/dev/null; then
        echo "/bin/bash"
        return
    fi
    echo "/usr/sbin/nologin"
}

# ===============================
# SLOWDNS
# ===============================
SLOWDNS_KEY=$(cat /etc/slowdns/server.pub 2>/dev/null || echo "N/A")
SLOWDNS_NS=$(cat /etc/slowdns/ns.conf 2>/dev/null || echo "N/A")

# ===============================
# FICHIERS
# ===============================
USER_FILE="/etc/kighmu/users.list"
LOCK_FILE="/etc/kighmu/users.list.lock"
TEST_DIR="/etc/kighmu/userteste"
mkdir -p /etc/kighmu "$TEST_DIR"
touch "$USER_FILE"
chmod 600 "$USER_FILE"

# Clear uniquement si terminal local
if [[ -t 1 && "$BOT_MODE" = false ]]; then
    clear
fi

echo "+==================================================+"
echo "|              CRÉATION D'UTILISATEUR TEST       |"
echo "+==================================================+"

# ===============================
# SAISIE LOCALE
# ===============================
if ! $BOT_MODE; then
    read -p "Nom d'utilisateur : " username
    read -s -p "Mot de passe : " password; echo
    read -p "Nombre d'appareils autorisés : " limite
    read -p "Durée de validité (en minutes) : " minutes
fi

# ===============================
# VALIDATION
# ===============================
[[ -z "${username:-}" ]] && { echo "Nom d'utilisateur vide."; exit 1; }
[[ -z "${password:-}" ]] && { echo "Mot de passe vide."; exit 1; }
id "$username" &>/dev/null && { echo "Utilisateur déjà existant."; exit 1; }
[[ ! "$limite" =~ ^[0-9]+$ ]] && { echo "Limite invalide."; exit 1; }
[[ ! "$minutes" =~ ^[0-9]+$ ]] && { echo "Durée invalide."; exit 1; }

# ===============================
# CRÉATION UTILISATEUR
# ===============================
USER_SHELL=$(detect_ssh_shell)
useradd -M -s "$USER_SHELL" "$username"
echo "$username:$password" | chpasswd

expire_date=$(date -d "+$minutes minutes" '+%Y-%m-%d %H:%M:%S')
HOST_IP=$(hostname -I | awk '{print $1}')

# ===============================
# ENREGISTREMENT
# ===============================
(
  flock -x 200
  echo "$username|$password|$limite|$expire_date|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> "$USER_FILE"
) 200>"$LOCK_FILE"

# ===============================
# AUTO-SUPPRESSION
# ===============================
CLEAN_SCRIPT="$TEST_DIR/$username-clean.sh"
cat > "$CLEAN_SCRIPT" <<EOF
#!/bin/bash
pkill -u "$username" 2>/dev/null
userdel --force "$username" 2>/dev/null
(
  flock -x 200
  grep -v "^$username|" $USER_FILE > /tmp/users.tmp
  mv /tmp/users.tmp $USER_FILE
) 200>"$LOCK_FILE"
rm -f "$CLEAN_SCRIPT"
EOF
chmod +x "$CLEAN_SCRIPT"

command -v at >/dev/null && echo "bash $CLEAN_SCRIPT" | at now + "$minutes" min >/dev/null 2>&1 || true

# ===============================
# BANNIÈRE
# ===============================
USER_HOME="/home/$username"
mkdir -p "$USER_HOME"
chown "$username:$username" "$USER_HOME"

cat > "$USER_HOME/.bashrc" <<EOF
[ -f /etc/ssh/sshd_banner ] && cat /etc/ssh/sshd_banner
EOF
chown "$username:$username" "$USER_HOME/.bashrc"

# ===============================
# AFFICHAGE FINAL (PLAIN TEXT pour BOT)
# ===============================
echo "+=================================================================+"
echo "*NOUVEAU UTILISATEUR TEST CRÉÉ*"
echo "─────────────────────────────────────────────────────────────────"
echo "∘ SSH: 22      ∘ System-DNS: 53"
echo "∘ SSH WS: 80   ∘ WEB-NGINX: 81"
echo "∘ DROPBEAR: 2222   ∘ SSL: 444"
echo "∘ BadVPN: 7200    ∘ BadVPN: 7300"
echo "∘ FASTDNS: 5300   ∘ UDP-Custom: 54000"
echo "∘ Hysteria: 22000  ∘ Proxy WS: 9090"
echo "─────────────────────────────────────────────────────────────────"
echo "DOMAIN         : $DOMAIN"
echo "Host/IP-Address : $HOST_IP"
echo "UTILISATEUR    : $username"
echo "MOT DE PASSE   : $password"
echo "LIMITE         : $limite"
echo "DATE EXPIRÉE   : $expire_date"
echo "─────────────────────────────────────────────────────────────────"
echo "En APPS comme HTTP Injector, CUSTOM, SOCKSIP TUNNEL, SSC, etc."
echo "SSH WS          : $DOMAIN:80@$username:$password"
echo "SSL/TLS (SNI)   : $HOST_IP:444@$username:$password"
echo "Proxy WS        : $HOST_IP:9090@$username:$password"
echo "SSH UDP         : $HOST_IP:54000@$username:$password"
echo "Hysteria (UDP)  : $DOMAIN:22000@$username:$password"
echo "PAYLOAD WS      : GET / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]"
echo "─────────────────────────────────────────────────────────────────"
echo "CONFIGS FASTDNS PORT 5300"
echo "Pub KEY :"
echo "$SLOWDNS_KEY"
echo "NameServer (NS) : $SLOWDNS_NS"
echo "+=================================================================+"
echo "Compte test créé avec succès"

# Pause seulement en mode local
if [[ "$BOT_MODE" = false ]]; then
    read -p "Appuyez sur Entrée pour revenir au menu..."
fi
