#!/bin/bash
# menu1.sh
# Créer un utilisateur normal et sauvegarder ses infos

# Charger la configuration globale si elle existe
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

echo "+--------------------------------------------+"
echo "|         CRÉATION D'UTILISATEUR            |"
echo "+--------------------------------------------+"

# Demander les informations
read -p "Nom d'utilisateur : " username

if id "$username" &>/dev/null; then
    echo "L'utilisateur existe déjà."
    exit 1
fi

# Lecture mot de passe visible (sans masquage)
read -p "Mot de passe : " password

read -p "Nombre d'appareils autorisés : " limite
read -p "Durée de validité (en jours) : " days

# Validation simple
if ! [[ "$limite" =~ ^[0-9]+$ ]] || ! [[ "$days" =~ ^[0-9]+$ ]]; then
    echo "Nombre d'appareils ou durée non valides."
    exit 1
fi

# Calculer la date d'expiration
expire_date=$(date -d "+$days days" '+%Y-%m-%d')

# Création utilisateur sans home et shell bloqué
useradd -M -s /bin/false "$username" || { echo "Erreur lors de la création"; exit 1; }
echo "$username:$password" | chpasswd

# Appliquer la date d'expiration du compte
chage -E "$expire_date" "$username"

# Préparer fichier d'utilisateurs
USER_FILE="/etc/kighmu/users.list"
mkdir -p /etc/kighmu
touch "$USER_FILE"
chmod 600 "$USER_FILE"

HOST_IP=$(hostname -I | awk '{print $1}')

# Vérification que SLOWDNS_NS est bien défini
if [ -z "$SLOWDNS_NS" ]; then
    echo "Erreur : variable SLOWDNS_NS non définie dans la configuration globale."
    exit 1
fi

# Sauvegarder les infos utilisateur
echo "$username|$password|$limite|$expire_date|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> "$USER_FILE"

# Afficher résumé
echo ""
echo "*NOUVEAU UTILISATEUR CRÉÉ*"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "∘ SSH: 22                  ∘ System-DNS: 53"
echo "∘ SOCKS/PYTHON: 8080       ∘ WEB-NGINX: 81"
echo "∘ DROPBEAR: 90             ∘ SSL: 443"
echo "∘ BadVPN: 7200             ∘ BadVPN: 7300"
echo "∘ SlowDNS: 5300            ∘ UDP-Custom: 1-65535"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "DOMAIN         : $DOMAIN"
echo "Host/IP-Address: $HOST_IP"
echo "UTILISATEUR    : $username"
echo "MOT DE PASSE   : $password"
echo "LIMITE         : $limite"
echo "DATE EXPIRÉE   : $expire_date"
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
