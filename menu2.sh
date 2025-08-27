#!/bin/bash
# ===============================================
# Kighmu VPS Manager - Création Utilisateur Test
# ===============================================

# Charger les infos globales Kighmu
if [ -f ~/.kighmu_info ]; then
    source ~/.kighmu_info
else
    echo "Erreur : fichier ~/.kighmu_info introuvable, informations globales manquantes."
    exit 1
fi

# Charger la clé publique SlowDNS
if [ -f /etc/slowdns/server.pub ]; then
    SLOWDNS_KEY=$(< /etc/slowdns/server.pub)
else
    SLOWDNS_KEY="Clé publique SlowDNS non trouvée!"
fi

# Fichiers et dossiers nécessaires
USER_FILE="/etc/kighmu/users.list"
mkdir -p /etc/kighmu
touch "$USER_FILE"
chmod 600 "$USER_FILE"

TEST_DIR="/etc/kighmu/userteste"
mkdir -p "$TEST_DIR"

echo "+--------------------------------------------+"
echo "|         CRÉATION D'UTILISATEUR TEST       |"
echo "+--------------------------------------------+"

# Lecture des informations
read -p "Nom d'utilisateur : " username
if [[ -z "$username" ]]; then
    echo "Nom d'utilisateur vide, annulation."
    exit 1
fi

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
if ! [[ "$limite" =~ ^[0-9]+$ ]]; then
    echo "Limite invalide, annulation."
    exit 1
fi

read -p "Durée de validité (en minutes) : " minutes
if ! [[ "$minutes" =~ ^[0-9]+$ ]]; then
    echo "Durée invalide, annulation."
    exit 1
fi

# Création utilisateur système sans home ni shell interactif
useradd -M -s /bin/false "$username"

# Définition du mot de passe
echo "$username:$password" | chpasswd

# Calcul de la date d'expiration rigoureuse au format ISO 8601
expire_date=$(date -d "+$minutes minutes" '+%Y-%m-%d %H:%M:%S')

# Récupération infos serveur
HOST_IP=$(curl -s https://api.ipify.org)
SLOWDNS_NS="${SLOWDNS_NS:-slowdns5.kighmup.ddns-ip.net}"

# Sauvegarde des infos utilisateur dans le fichier
echo "$username|$password|$limite|$expire_date|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> "$USER_FILE"

# Création du script de suppression automatique
CLEAN_SCRIPT="$TEST_DIR/$username-clean.sh"
cat > "$CLEAN_SCRIPT" <<EOF
#!/bin/bash
pkill -f "$username"
userdel --force "$username"
grep -v "^$username|" $USER_FILE > /tmp/users.tmp && mv /tmp/users.tmp $USER_FILE
rm -f "$CLEAN_SCRIPT"
exit 0
EOF
chmod +x "$CLEAN_SCRIPT"

# Planification suppression avec at
echo "bash $CLEAN_SCRIPT" | at now + $minutes minutes 2>/dev/null

# Affichage résumé
cat <<EOF

*NOUVEAU UTILISATEUR CRÉÉ*
──────────────────────────────────────────────
DOMAIN        : $DOMAIN
Adresse IP    : $HOST_IP
Utilisateur   : $username
Mot de passe  : $password
Limite       : $limite
Date d'expire : $expire_date
──────────────────────────────────────────────
En APPS comme HTTP Injector, KPN Rev, etc.

🙍 HTTP-Direct  : $HOST_IP:90@$username:$password
🙍 SSL/TLS(SNI) : $HOST_IP:443@$username:$password
🙍 Proxy(WS)    : $DOMAIN:8080@$username:$password
🙍 SSH UDP     : $HOST_IP:1-65535@$username:$password

──────────────────── CONFIG SLOWDNS ───────────────
Pub Key :
$SLOWDNS_KEY
NameServer (NS) : $SLOWDNS_NS
──────────────────────────────────────────────

Le compte sera supprimé automatiquement après $minutes minutes.

Compte créé avec succès.

EOF

exit 0
