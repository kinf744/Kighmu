#!/bin/bash
# ==================================================
# Kighmu VPS Manager - Création Utilisateur (Jours)
# Compatible BOT Telegram + Local
# ==================================================

set -o pipefail

# ===============================
# DÉTECTION MODE BOT
# ===============================
BOT_MODE=false
if [[ $# -ge 4 ]]; then
    BOT_MODE=true
    username="$1"
    password="$2"
    limite="$3"
    jours="$4"
fi

# ===============================
# SÉCURITÉ MODE BOT
# ===============================
if $BOT_MODE; then
    set +e
    set +u
    RED=""; GREEN=""; YELLOW=""; BLUE=""
    MAGENTA=""; CYAN=""; BOLD=""; RESET=""
else
    set -euo pipefail
fi

# ===============================
# COULEURS (LOCAL UNIQUEMENT)
# ===============================
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# ===============================
# ROOT
# ===============================
if [[ $EUID -ne 0 ]]; then
    echo "Erreur : ce script doit être exécuté en root"
    exit 1
fi

# ===============================
# CONFIG GLOBALE
# ===============================
if [[ -f ~/.kighmu_info ]]; then
    source ~/.kighmu_info
else
    echo "Erreur : ~/.kighmu_info introuvable"
    exit 1
fi

# ===============================
# AUTO SSH SHELL
# ===============================
detect_ssh_shell() {
    if pgrep -x dropbear >/dev/null 2>&1; then
        echo "/usr/sbin/nologin"
    elif pgrep -x sshd >/dev/null 2>&1; then
        echo "/bin/bash"
    else
        echo "/usr/sbin/nologin"
    fi
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
mkdir -p /etc/kighmu
touch "$USER_FILE"
chmod 600 "$USER_FILE"

# ===============================
# CLEAR LOCAL
# ===============================
if [[ -t 1 && "$BOT_MODE" = false ]]; then
    clear || true
fi

echo "${CYAN}+==================================================+${RESET}"
echo "|        CRÉATION D'UTILISATEUR KIGHMU VPS         |"
echo "${CYAN}+==================================================+${RESET}"

# ===============================
# SAISIE LOCALE
# ===============================
if ! $BOT_MODE; then
    read -p "Nom d'utilisateur : " username
    read -s -p "Mot de passe : " password; echo
    read -p "Nombre d'appareils autorisés : " limite
    read -p "Durée de validité (en jours) : " jours
fi

# ===============================
# VALIDATION
# ===============================
[[ -z "${username:-}" ]] && { echo "Utilisateur vide"; exit 1; }
[[ -z "${password:-}" ]] && { echo "Mot de passe vide"; exit 1; }
id "$username" &>/dev/null && { echo "Utilisateur existe déjà"; exit 1; }
[[ ! "$limite" =~ ^[0-9]+$ ]] && { echo "Limite invalide"; exit 1; }
[[ ! "$jours" =~ ^[0-9]+$ ]] && { echo "Durée invalide"; exit 1; }

# ===============================
# CRÉATION UTILISATEUR
# ===============================
USER_SHELL=$(detect_ssh_shell)
useradd -M -s "$USER_SHELL" "$username"
echo "$username:$password" | chpasswd

expire_date=$(date -d "+$jours days" '+%Y-%m-%d')
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
HOST_IP=${HOST_IP:-127.0.0.1}

# ===============================
# ENREGISTREMENT
# ===============================
(
    flock -x 200
    echo "$username|$password|$limite|$expire_date|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> "$USER_FILE"
) 200>"$LOCK_FILE"

# ===============================
# BANNIÈRE SSH
# ===============================
USER_HOME="/home/$username"
mkdir -p "$USER_HOME"
chown "$username:$username" "$USER_HOME"

cat > "$USER_HOME/.bashrc" <<EOF
[ -f /etc/ssh/sshd_banner ] && cat /etc/ssh/sshd_banner
EOF
chown "$username:$username" "$USER_HOME/.bashrc"

# ===============================
# AFFICHAGE FINAL
# ===============================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "UTILISATEUR CRÉÉ AVEC SUCCÈS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "DOMAIN        : $DOMAIN"
echo "IP/HOST       : $HOST_IP"
echo "UTILISATEUR   : $username"
echo "MOT DE PASSE  : $password"
echo "LIMITE        : $limite"
echo "EXPIRATION    : $expire_date"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "SSH WS   : $DOMAIN:80@$username:$password"
echo "SSL/TLS  : $HOST_IP:444@$username:$password"
echo "UDP      : $HOST_IP:54000@$username:$password"
echo "HYSTERIA : $DOMAIN:22000@$username:$password"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "FASTDNS (5300)"
echo "PUB KEY :"
echo "$SLOWDNS_KEY"
echo "NS      : $SLOWDNS_NS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Compte créé avec succès ✔"

if [[ "$BOT_MODE" = false ]]; then
    read -p "Appuyez sur Entrée pour revenir au menu..."
fi
