#!/bin/bash
# menu1.sh
# Créer un utilisateur normal et sauvegarder ses infos

# Définition des couleurs (comme dans le panneau principal)
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

clear

# Charger la configuration globale si elle existe
if [ -f ~/.kighmu_info ]; then
    source ~/.kighmu_info
else
    echo -e "${RED}Erreur : fichier ~/.kighmu_info introuvable, informations globales manquantes.${RESET}"
    read -p "Appuyez sur Entrée pour revenir au menu..." 
    exit 1
fi

# Charger la clé publique SlowDNS
if [ -f /etc/slowdns/server.pub ]; then
    SLOWDNS_KEY=$(cat /etc/slowdns/server.pub)
else
    SLOWDNS_KEY="${RED}Clé publique SlowDNS non trouvée!${RESET}"
fi

# Charger le NameServer SlowDNS exact depuis le fichier de config, sinon valeur vide
if [ -f /etc/slowdns/ns.conf ]; then
    SLOWDNS_NS=$(cat /etc/slowdns/ns.conf)
else
    SLOWDNS_NS=""
    echo -e "${YELLOW}Attention : fichier /etc/slowdns/ns.conf introuvable. Poursuite sans NS.${RESET}"
fi

echo -e "${CYAN}+==================================================+${RESET}"
echo -e "|                CRÉATION D'UTILISATEUR             |"
echo -e "${CYAN}+==================================================+${RESET}"

# Demander les informations
read -p "Nom d'utilisateur : " username

if id "$username" &>/dev/null; then
    echo -e "${RED}L'utilisateur existe déjà.${RESET}"
    read -p "Appuyez sur Entrée pour revenir au menu..."
    exit 1
fi

# Lecture mot de passe visible (sans masquage)
read -p "Mot de passe : " password

read -p "Nombre d'appareils autorisés : " limite
read -p "Durée de validité (en jours) : " days

# Validation simple
if ! [[ "$limite" =~ ^[0-9]+$ ]] || ! [[ "$days" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Nombre d'appareils ou durée non valides.${RESET}"
    read -p "Appuyez sur Entrée pour revenir au menu..."
    exit 1
fi

# Calculer la date d'expiration
expire_date=$(date -d "+$days days" '+%Y-%m-%d')

# Création utilisateur sans home et shell bloqué
useradd -M -s /bin/false "$username" || { echo -e "${RED}Erreur lors de la création${RESET}"; read -p "Appuyez sur Entrée pour revenir au menu..."; exit 1; }
echo "$username:$password" | chpasswd

# Appliquer la date d'expiration du compte
chage -E "$expire_date" "$username"

# Préparer fichier d'utilisateurs
USER_FILE="/etc/kighmu/users.list"
mkdir -p /etc/kighmu
touch "$USER_FILE"
chmod 600 "$USER_FILE"

HOST_IP=$(hostname -I | awk '{print $1}')

# Sauvegarder les infos utilisateur dans le format attendu par hysteria.sh
echo "$username|$password|$limite|$expire_date|$HOST_IP|$DOMAIN|$SLOWDNS_NS" >> "$USER_FILE"

# Ajout automatique de l'affichage du banner personnalisé au login shell
BANNER_PATH="/etc/ssh/sshd_banner"  # Chemin vers le fichier banner, à adapter

# Comme pas de home créé (avec -M), .bashrc n'existe pas => créer dossier home minimal et fichier .bashrc pour banner
USER_HOME="/home/$username"
if [ ! -d "$USER_HOME" ]; then
    mkdir -p "$USER_HOME"
    chown "$username":"$username" "$USER_HOME"
fi

echo -e "
# Affichage du banner Kighmu VPS Manager
if [ -f $BANNER_PATH ]; then
    cat \$BANNER_PATH
fi
" > "$USER_HOME/.bashrc"

chown "$username":"$username" "$USER_HOME/.bashrc"
chmod 644 "$USER_HOME/.bashrc"

# Résumé affichage coloré des informations utilisateur avec hysteria inclus
echo -e "${CYAN}+=================================================================+${RESET}"
echo -e "*NOUVEAU UTILISATEUR CRÉÉ*"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "∘ SSH: 22                  ∘ System-DNS: 53"
echo -e "∘ SOCKS/PYTHON: 8080       ∘ WEB-NGINX: 81"
echo -e "∘ DROPBEAR: 90             ∘ SSL: 443"
echo -e "∘ BadVPN: 7200             ∘ BadVPN: 7300"
echo -e "∘ SlowDNS: 5300            ∘ UDP-Custom: 1-65535"
echo -e "∘ Hysteria: 22000          ∘ Proxy WS: 80"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${YELLOW}DOMAIN         :${RESET} $DOMAIN"
echo -e "${YELLOW}Host/IP-Address:${RESET} $HOST_IP"
echo -e "${YELLOW}UTILISATEUR    :${RESET} $username"
echo -e "${YELLOW}MOT DE PASSE   :${RESET} $password"
echo -e "${YELLOW}LIMITE         :${RESET} $limite"
echo -e "${YELLOW}DATE EXPIRÉE   :${RESET} $expire_date"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo "En APPS comme HTTP Injector, CUSTOM, SOCKSIP TUNNEL, SSC, etc."
echo ""
echo -e "🙍 HTTP-Direct     : ${GREEN}$HOST_IP:8080@$username:$password${RESET}"
echo -e "🙍 SSL/TLS(SNI)    : ${GREEN}$HOST_IP:444@$username:$password${RESET}"
echo -e "🙍 Proxy(WS)       : ${GREEN}$DOMAIN:80@$username:$password${RESET}"
echo -e "🙍 SSH UDP         : ${GREEN}$HOST_IP:1-65535@$username:$password${RESET}"
echo -e "🙍 Hysteria (UDP)  : ${GREEN}$DOMAIN:22000@$username:$password${RESET}"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━  CONFIGS SLOWDNS PORT 5300 ━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${YELLOW}Pub KEY :${RESET}"
echo "$SLOWDNS_KEY"
echo -e "${YELLOW}NameServer (NS) :${RESET} $SLOWDNS_NS"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}Compte créé avec succès${RESET}"

read -p "Appuyez sur Entrée pour revenir au menu..."
