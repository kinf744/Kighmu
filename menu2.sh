#!/bin/bash
# menu2.sh
# Créer un utilisateur test

# Charger la configuration globale si elle existe
if [ -f ./config.sh ]; then
    source ./config.sh
fi

echo "+--------------------------------------------+"
echo "|         CRÉATION D'UTILISATEUR TEST       |"
echo "+--------------------------------------------+"

# Demander les informations
read -p "Nom d'utilisateur : " username
read -s -p "Mot de passe : " password
echo ""
read -p "Nombre d'appareils autorisés : " limite
read -p "Durée de validité (en minutes) : " minutes

# Calculer la date d'expiration
expire_date=$(date -d "+$minutes minutes" '+%Y-%m-%d %H:%M:%S')

# Créer l'utilisateur système
useradd -M -s /bin/false $username
echo "$username:$password" | chpasswd

# Définir les ports et services (exemple)
SSH_PORT=22
SYSTEM_DNS=53
SOCKS_PORT=80
WEB_NGINX=81
DROPBEAR=90
SSL_PORT=443
BADVPN1=7200
BADVPN2=7300
SLOWDNS_PORT=5300
UDP_CUSTOM="1-65535"
DOMAIN="${DOMAIN:-myserver.example.com}"
HOST_IP=$(curl -s https://api.ipify.org)
SLOWDNS_KEY="7fbd1f8aa0abfe15a7903e837f78aba39cf61d36f183bd604daa2fe4ef3b7b59"
read -p "SlowDNS NameServer (NS) : " SLOWDNS_NS

# Afficher résumé
echo ""
echo "*NOUVEAU UTILISATEUR CRÉÉ*"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "∘ SSH: $SSH_PORT            ∘ System-DNS: $SYSTEM_DNS"
echo "∘ SOCKS/PYTHON: $SOCKS_PORT   ∘ WEB-NGinx: $WEB_NGINX"
echo "∘ DROPBEAR: $DROPBEAR       ∘ SSL: $SSL_PORT"
echo "∘ BadVPN: $BADVPN1       ∘ BadVPN: $BADVPN2"
echo "∘ SlowDNS: $SLOWDNS_PORT      ∘ UDP-Custom: $UDP_CUSTOM"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "DOMAIN  : $DOMAIN"
echo "Host/IP-Address : $HOST_IP"
echo "USUARIO : $username"
echo "PASSWD  : [protégé]"
echo "LIMITE  : $limite"
echo "VALIDEZ : $expire_date"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "En APPS comme HTTP Inyector,CUSTOM,KPN Rev,etc"
echo ""
echo "🙍 HTTP-Direct  : $HOST_IP:90@$username:$password"
echo "🙍 SSL/TLS(SNI) : $HOST_IP:443@$username:$password"
echo "🙍 Proxy(WS) : $DOMAIN:80@$username:$password"
echo "🙍 SSH UDP  : $HOST_IP:1-65535@$username:$password"
echo ""
echo "━━━━━━━━━━━  SLOWDNS CONFIGS PORT 22 ━━━━━━━━━━━"
echo "Pub KEY : $SLOWDNS_KEY"
echo "NameServer (NS) : $SLOWDNS_NS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Compte créé avec succès"
