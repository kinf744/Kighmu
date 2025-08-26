#!/bin/bash
# menu2_et_expire.sh
# Usage :
# ./menu2_et_expire.sh create   => Création utilisateur test
# ./menu2_et_expire.sh expire   => Vérification expiration minute (pour cron)

USER_FILE="/etc/kighmu/users.list"
LOG_FILE="/var/log/expire_users.log"

create_user() {
    if [ -f ~/.kighmu_info ]; then
        source ~/.kighmu_info
    else
        echo "Erreur : fichier ~/.kighmu_info introuvable, informations globales manquantes."
        exit 1
    fi

    if [ -f /etc/slowdns/server.pub ]; then
        SLOWDNS_KEY=$(cat /etc/slowdns/server.pub)
    else
        SLOWDNS_KEY="Clé publique SlowDNS non trouvée!"
    fi

    echo "+--------------------------------------------+"
    echo "|         CRÉATION D'UTILISATEUR TEST       |"
    echo "+--------------------------------------------+"

    read -p "Nom d'utilisateur : " username
    read -s -p "Mot de passe : " password
    echo ""
    read -p "Nombre d'appareils autorisés : " limite
    read -p "Durée de validité (en minutes) : " minutes

    expire_full=$(date -d "+$minutes minutes" '+%Y-%m-%d %H:%M:%S')
    expire_day=$(date -d "+$minutes minutes" '+%Y-%m-%d')
    today=$(date '+%Y-%m-%d')
    if [[ "$expire_day" < "$today" ]]; then
        expire_day=$today
    fi

    useradd -M -s /bin/false "$username" || { echo "Erreur création utilisateur."; exit 1; }
    echo "$username:$password" | chpasswd
    chage -E "$expire_day" "$username"

    SSH_PORT=22
    SYSTEM_DNS=53
    SOCKS_PORT=8080
    WEB_NGINX=81
    DROPBEAR=90
    SSL_PORT=443
    BADVPN1=7200
    BADVPN2=7300
    SLOWDNS_PORT=5300
    UDP_CUSTOM="1-65535"
    HOST_IP=$(curl -s https://api.ipify.org)
    SLOWDNS_NS="${SLOWDNS_NS:-slowdns5.kighmup.ddns-ip.net}"

    mkdir -p /etc/kighmu
    touch "$USER_FILE"
    chmod 600 "$USER_FILE"
    echo "$username|$password|$limite|$expire_full|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> "$USER_FILE"

    echo ""
    echo "*NOUVEAU UTILISATEUR CRÉÉ*"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "∘ SSH: $SSH_PORT            ∘ System-DNS: $SYSTEM_DNS"
    echo "∘ SOCKS/PYTHON: $SOCKS_PORT   ∘ WEB-NGINX: $WEB_NGINX"
    echo "∘ DROPBEAR: $DROPBEAR       ∘ SSL: $SSL_PORT"
    echo "∘ BadVPN: $BADVPN1       ∘ BadVPN: $BADVPN2"
    echo "∘ SlowDNS: $SLOWDNS_PORT      ∘ UDP-Custom: $UDP_CUSTOM"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "DOMAIN        : $DOMAIN"
    echo "Host/IP-Address : $HOST_IP"
    echo "UTILISATEUR   : $username"
    echo "MOT DE PASSE  : $password"
    echo "LIMITE       : $limite"
    echo "DATE EXPIRÉE : $expire_full"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "En APPS comme HTTP Injector, CUSTOM, KPN Rev, etc."
    echo ""
    echo "🙍 HTTP-Direct  : $HOST_IP:90@$username:$password"
    echo "🙍 SSL/TLS(SNI) : $HOST_IP:443@$username:$password"
    echo "🙍 Proxy(WS)    : $DOMAIN:8080@$username:$password"
    echo "🙍 SSH UDP     : $HOST_IP:1-65535@$username:$password"
    echo ""
    echo "━━━━━━━━━━━  CONFIGS SLOWDNS PORT 22 ━━━━━━━━━━━"
    echo "Pub KEY :"
    echo "$SLOWDNS_KEY"
    echo "NameServer (NS) : $SLOWDNS_NS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Compte créé avec succès"
}

expire_users() {
    NOW=$(date '+%Y-%m-%d %H:%M:%S')
    TMP_FILE="${USER_FILE}.tmp"
    > "$TMP_FILE"
    mkdir -p $(dirname "$LOG_FILE")
    touch "$LOG_FILE"
    chmod 600 "$LOG_FILE"

    while IFS="|" read -r user pass limit expire_date rest; do
        if [[ "$NOW" > "$expire_date" ]]; then
            usermod -L "$user"
            echo "$(date '+%Y-%m-%d %H:%M:%S') : Utilisateur $user désactivé (expiration $expire_date)" >> "$LOG_FILE"
        else
            echo "$user|$pass|$limit|$expire_date|$rest" >> "$TMP_FILE"
        fi
    done < "$USER_FILE"
    mv "$TMP_FILE" "$USER_FILE"
}

case "$1" in
    create)
        create_user
        ;;
    expire)
        expire_users
        ;;
    *)
        echo "Usage: $0 create    # Pour création utilisateur test"
        echo "       $0 expire    # Pour vérifier/désactiver les expirés à la minute (à utiliser avec cron)"
        exit 1
        ;;
esac
