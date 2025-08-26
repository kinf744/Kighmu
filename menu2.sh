#!/bin/bash
# Création d'un utilisateur test avec expiration temporaire et suppression
# Adaptation de DarkSSH pour intégration avec paramètres Kighmu

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

# Dossiers nécessaires et fichiers
USER_FILE="/etc/kighmu/users.list"
mkdir -p /etc/kighmu
touch "$USER_FILE"
chmod 600 "$USER_FILE"

TEST_DIR="/etc/kighmu/userteste"
mkdir -p "$TEST_DIR"

echo "+--------------------------------------------+"
echo "|         CRÉATION D'UTILISATEUR TEST       |"
echo "+--------------------------------------------+"

# Demander les informations
read -p "Nom d'utilisateur : " username
if [[ -z "$username" ]]; then
    echo "Nom d'utilisateur vide, annulation."
    exit 1
fi

# Vérifier si utilisateur existe
if id "$username" &>/dev/null; then
    echo "Cet utilisateur existe déjà."
    exit 1
fi

read -s -p "Mot de passe : " password
echo ""
if [[ -z "$password" ]]; then
    echo "Mot de passe vide, annulation."
    exit 1
fi

read -p "Nombre d'appareils autorisés : " limite
if [[ -z "$limite" ]]; then
    echo "Limite invalide, annulation."
    exit 1
fi

read -p "Durée de validité (en minutes) : " minutes
if [[ -z "$minutes" || ! "$minutes" =~ ^[0-9]+$ ]]; then
    echo "Durée invalide, annulation."
    exit 1
fi

# Création utilisateur système sans home, shell bloqué
useradd -M -s /bin/false "$username"

# Définition du mot de passe
echo "$username:$password" | chpasswd

# Sauvegarder les infos utilisateur
HOST_IP=$(curl -s https://api.ipify.org)
SLOWDNS_NS="${SLOWDNS_NS:-slowdns5.kighmup.ddns-ip.net}"
expire_date=$(date -d "+$minutes minutes" '+%Y-%m-%d %H:%M:%S')

echo "$username|$password|$limite|$expire_date|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> "$USER_FILE"

# Création du script de suppression automatique
CLEAN_SCRIPT="$TEST_DIR/$username.sh"
cat > "$CLEAN_SCRIPT" <<EOF
#!/bin/bash
pkill -f "$username"
userdel --force "$username"
grep -v ^$username[[:space:]] $USER_FILE > /tmp/clean_users && mv /tmp/clean_users $USER_FILE
rm -f $CLEAN_SCRIPT
exit 0
EOF
chmod +x "$CLEAN_SCRIPT"

# Planifier la suppression automatique après la durée
at -f "$CLEAN_SCRIPT" now + "$minutes" min &>/dev/null

# Affichage résumé
echo ""
echo "*NOUVEAU UTILISATEUR CRÉÉ*"
echo "──────────────────────────────────────────────"
echo "DOMAIN        : $DOMAIN"
echo "Adresse IP    : $HOST_IP"
echo "Utilisateur   : $username"
echo "Mot de passe  : $password"
echo "Limite       : $limite"
echo "Date d'expire : $expire_date"
echo "──────────────────────────────────────────────"
echo "En APPS comme HTTP Injector, KPN Rev, etc."
echo ""
echo "🙍 HTTP-Direct  : $HOST_IP:90@$username:$password"
echo "🙍 SSL/TLS(SNI) : $HOST_IP:443@$username:$password"
echo "🙍 Proxy(WS)    : $DOMAIN:8080@$username:$password"
echo "🙍 SSH UDP     : $HOST_IP:1-65535@$username:$password"
echo ""
echo "──────────────────── CONFIG SLOWDNS ───────────────"
echo "Pub Key :"
echo "$SLOWDNS_KEY"
echo "NameServer (NS) : $SLOWDNS_NS"
echo "──────────────────────────────────────────────"
echo "Le compte sera supprimé automatiquement après $minutes minutes."
echo ""
echo "Compte créé avec succès."

exit 0
