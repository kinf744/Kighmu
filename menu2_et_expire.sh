#!/bin/bash
# menu2_et_expire.sh
# Usage :
# ./menu2_et_expire.sh create   => Création utilisateur test
# ./menu2_et_expire.sh expire   => Vérification expiration minute (pour cron)
# ./menu2_et_expire.sh restore  => Restaurer règles iptables sauvegardées (ex: au démarrage)

USER_FILE="/etc/kighmu/users.list"
LOG_FILE="/var/log/expire_users.log"
IPTABLES_BACKUP="/etc/iptables.rules.v4"

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

    # Création utilisateur avec home et shell nologin
    useradd -m -s /usr/sbin/nologin "$username" || { echo "Erreur création utilisateur."; exit 1; }
    echo "$username:$password" | chpasswd
    chage -E "$expire_day" "$username"

    # Ouvrir les ports VPN dans iptables
    for rule in \
        "-I INPUT -p tcp --dport 8080 -j ACCEPT" \
        "-I INPUT -p udp --dport 5300 -j ACCEPT" \
        "-I INPUT -p udp --dport 54000 -j ACCEPT"
    do
        if ! iptables -C ${rule#-I } 2>/dev/null; then
            iptables $rule
        fi
    done

    # Sauvegarde règles iptables
    iptables-save > "$IPTABLES_BACKUP"

    SSH_PORT=22
    SYSTEM_DNS=53
    SOCKS_PORT=8080
    WEB_NGINX=81
    DROPBEAR=90
    SSL_PORT=443
    BADVPN1=54000
    BADVPN2=7300
    SLOWDNS_PORT=5300
    UDP_CUSTOM="54000"
    HOST_IP=$(curl -s https://api.ipify.org)
    SLOWDNS_NS="${SLOWDNS_NS:-slowdns5.kighmup.ddns-ip.net}"

    mkdir -p /etc/kighmu
    [ ! -f "$USER_FILE" ] && touch "$USER_FILE"
    chmod 600 "$USER_FILE"
    echo "$username|$password|$limite|$expire_full|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> "$USER_FILE"

    # Affichage complet info utilisateur
    echo ""
    echo "+--------------------------------------------------+"
    echo "|             INFOS UTILISATEUR TEST               |"
    echo "+--------------------------------------------------+"
    echo "IP Serveur       : $HOST_IP"
    echo "Domaine          : $DOMAIN"
    echo "Nom utilisateur  : $username"
    echo "Mot de passe     : $password"
    echo "Nombre appareils : $limite"
    echo "Date expiration  : $expire_full"
    echo ""
    echo "Clé publique SlowDNS :"
    echo "$SLOWDNS_KEY"
    echo ""
    echo "NameServer (NS)  : $SLOWDNS_NS"
    echo "+--------------------------------------------------+"
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

restore_iptables() {
    if [ -f "$IPTABLES_BACKUP" ]; then
        iptables-restore < "$IPTABLES_BACKUP"
        echo "Règles iptables restaurées depuis $IPTABLES_BACKUP"
    else
        echo "Aucune sauvegarde iptables trouvée ($IPTABLES_BACKUP)"
    fi
}

case "$1" in
    create)
        create_user
        ;;
    expire)
        expire_users
        ;;
    restore)
        restore_iptables
        ;;
    *)
        echo "Usage: $0 create    # Pour création utilisateur test"
        echo "       $0 expire    # Pour vérifier/désactiver les expirés à la minute (à utiliser avec cron)"
        echo "       $0 restore   # Restaurer règles iptables sauvegardées (ex: au démarrage)"
        exit 1
        ;;
esac
