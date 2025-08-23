#!/bin/bash
# menu2.sh
# Créer un utilisateur test avec sauvegarde dans users.list

# Couleur bleu marine pour les cadres
BLUE="\e[34m"
RESET="\e[0m"

# Fonction pour encadrer un texte
draw_frame() {
    local text="$1"
    local width=50
    echo -e "${BLUE}+$(printf '%.0s-' $(seq 1 $width))+${RESET}"
    printf "|%*s%*s|\n" $(( (width + ${#text})/2 )) "$text" $(( (width - ${#text})/2 )) ""
    echo -e "${BLUE}+$(printf '%.0s-' $(seq 1 $width))+${RESET}"
}

# Charger les infos globales Kighmu
if [ -f ~/.kighmu_info ]; then
    source ~/.kighmu_info
else
    echo "Erreur : fichier ~/.kighmu_info introuvable, informations globales manquantes."
    exit 1
fi

# Charger la clé publique SlowDNS
if [ -f /etc/slowdns/server.pub ]; then
    SLOWDNS_KEY=$(cat /etc/slowdns/server.pub)
else
    SLOWDNS_KEY="Clé publique SlowDNS non trouvée!"
fi

# Affichage du panneau d’accueil
clear
draw_frame "CRÉATION D'UTILISATEUR TEST"

# Demander les informations
read -p "Nom d'utilisateur : " username
read -s -p "Mot de passe : " password
echo ""
read -p "Nombre d'appareils autorisés : " limite
read -p "Durée de validité (en minutes) : " minutes

# Calculer la date d'expiration
expire_date=$(date -d "+$minutes minutes" '+%Y-%m-%d %H:%M:%S')

# Créer l'utilisateur système
useradd -M -s /bin/false "$username"
echo "$username:$password" | chpasswd

# Définir les ports et services (exemple)
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

# Remplacer NS par celui chargé des infos globales si vide
SLOWDNS_NS="${SLOWDNS_NS:-slowdns5.kighmup.ddns-ip.net}"

# Sauvegarder les infos utilisateur dans le fichier dédié
USER_FILE="/etc/kighmu/users.list"
mkdir -p /etc/kighmu
touch "$USER_FILE"
chmod 600 "$USER_FILE"
echo "$username|$password|$limite|$expire_date|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> "$USER_FILE"

# Affichage résumé
echo ""
draw_frame "NOUVEAU UTILISATEUR TEST CRÉÉ"
echo "∘ SSH: $SSH_PORT            ∘ System-DNS: $SYSTEM_DNS"
echo "∘ SOCKS/PYTHON: $SOCKS_PORT   ∘ WEB-NGINX: $WEB_NGINX"
echo "∘ DROPBEAR: $DROPBEAR       ∘ SSL: $SSL_PORT"
echo "∘ BadVPN: $BADVPN1       ∘ BadVPN: $BADVPN2"
echo "∘ SlowDNS: $SLOWDNS_PORT      ∘ UDP-Custom: $UDP_CUSTOM"
echo "--------------------------------------------------"
echo "DOMAIN        : $DOMAIN"
echo "Host/IP-Address : $HOST_IP"
echo "UTILISATEUR   : $username"
echo "MOT DE PASSE  : $password"
echo "LIMITE        : $limite"
echo "DATE EXPIRÉE  : $expire_date"
echo "--------------------------------------------------"
echo "En APPS comme HTTP Injector, CUSTOM, KPN Rev, etc."
echo ""
echo "🙍 HTTP-Direct  : $HOST_IP:90@$username:$password"
echo "🙍 SSL/TLS(SNI) : $HOST_IP:443@$username:$password"
echo "🙍 Proxy(WS)    : $DOMAIN:8080@$username:$password"
echo "🙍 SSH UDP      : $HOST_IP:1-65535@$username:$password"
echo ""
draw_frame "CONFIGS SLOWDNS PORT 22"
echo "Pub KEY :"
echo "$SLOWDNS_KEY"
echo "NameServer (NS) : $SLOWDNS_NS"
echo "--------------------------------------------------"
echo "Compte test créé avec succès"
