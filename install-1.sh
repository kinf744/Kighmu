#!/bin/bash
# ================================================================
#   KIGHMU PANEL v2 — Installateur interactif
#   Ubuntu 20.04+ / Debian 11+
#   Compatibilité Xray : Nginx panel sur port 81
# ================================================================

# --- Couleurs ---
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; B='\033[1m'; P='\033[0;35m'; NC='\033[0m'

# --- Constantes ---
INSTALL_DIR="/opt/kighmu-panel"
NODE_PORT="3000"          # Port interne Node.js (jamais exposé directement)
NGINX_PORT="8585"         # Port public Nginx → Xray utilise 81, SSH WS utilise 80
DB_NAME="kighmu_panel"
DB_USER="kighmu_user"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_SECRET=$(openssl rand -hex 20 2>/dev/null || echo "kighmu-report-$(date +%s)")
TRAFFIC_SCRIPT="/etc/kighmu/traffic-collect.sh"
TRAFFIC_LOG="/var/log/kighmu-traffic.log"

# ================================================================
# FONCTIONS UTILITAIRES
# ================================================================
banner() {
  clear
  echo -e "${C}${B}"
  cat << 'EOF'
  ██╗  ██╗██╗ ██████╗ ██╗  ██╗███╗   ███╗██╗   ██╗
  ██║ ██╔╝██║██╔════╝ ██║  ██║████╗ ████║██║   ██║
  █████╔╝ ██║██║  ███╗███████║██╔████╔██║██║   ██║
  ██╔═██╗ ██║██║   ██║██╔══██║██║╚██╔╝██║██║   ██║
  ██║  ██╗██║╚██████╔╝██║  ██║██║ ╚═╝ ██║╚██████╔╝
  ╚═╝  ╚═╝╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝
EOF
  echo -e "${NC}"
  echo -e "  ${C}Panel v2${NC} — Gestionnaire de tunnels VPN"
  echo -e "  ${P}Compatible Xray / V2Ray / SSH / UDP${NC}"
  echo -e "  ${Y}Nginx panel : port ${NGINX_PORT} (Xray=81, SSH WS=80 déjà pris)${NC}"
  echo ""
  echo -e "  ${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

info()  { echo -e "  ${C}[•]${NC} $1"; }
ok()    { echo -e "  ${G}[✓]${NC} $1"; }
warn()  { echo -e "  ${Y}[!]${NC} $1"; }
err()   { echo -e "  ${R}[✗]${NC} $1"; }
die()   { err "$1"; exit 1; }
sep()   { echo -e "  ${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

pause() {
  echo ""
  read -rp "  $(echo -e "${Y}Appuyez sur [Entrée] pour continuer...${NC}")" _
}

confirm() {
  local msg="$1"
  echo ""
  read -rp "  $(echo -e "${Y}${msg} [o/N] : ${NC}")" rep
  [[ "$rep" =~ ^[oOyY]$ ]]
}

# ================================================================
# FONCTION CRÉATION ADMIN (réutilisée à l'install et au reset)
# ================================================================
_create_admin() {
  local uname="$1"
  local upass="$2"
  local idir="${INSTALL_DIR:-/opt/kighmu-panel}"
  local dbname="${DB_NAME:-kighmu_panel}"

  # Écrire le script JS dans le dossier du panel pour avoir accès aux node_modules
  cat > "${idir}/tmp_hash.js" << 'JSEOF'
const b   = require('./node_modules/bcryptjs');
const m   = require('./node_modules/mysql2/promise');
const env = require('./node_modules/dotenv');
env.config({ path: require('path').join(__dirname, '.env') });

async function run() {
  const user = process.env.K_USER;
  const pass = process.env.K_PASS;
  if (!user || !pass) throw new Error('K_USER ou K_PASS manquant');

  const hash = b.hashSync(pass, 12);
  const ok   = b.compareSync(pass, hash);
  if (!ok) throw new Error('Verification bcrypt echouee');

  const db = await m.createConnection({
    host:     process.env.DB_HOST     || '127.0.0.1',
    user:     process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
    connectTimeout: 8000,
  });
  await db.execute('DELETE FROM admins');
  await db.execute('INSERT INTO admins (username, password) VALUES (?, ?)', [user, hash]);
  const [rows] = await db.execute('SELECT id, username FROM admins');
  await db.end();
  process.stdout.write('OK:' + rows[0].username);
}
run().catch(e => { process.stderr.write('ERR:' + e.message); process.exit(1); });
JSEOF

  local result
  result=$(cd "${idir}" && K_USER="${uname}" K_PASS="${upass}" node tmp_hash.js 2>&1)
  rm -f "${idir}/tmp_hash.js"

  if echo "${result}" | grep -q "^OK:"; then
    return 0
  else
    echo "  [DEBUG] _create_admin: ${result}" >&2
    return 1
  fi
}

# ================================================================
# MENU PRINCIPAL
# ================================================================
main_menu() {
  while true; do
    banner
    echo -e "  ${B}MENU PRINCIPAL${NC}"
    echo ""
    echo -e "  ${G}[1]${NC}  🚀  Installer Kighmu Panel"
    echo -e "  ${R}[2]${NC}  🗑   Désinstaller / Nettoyer le panel"
    echo -e "  ${C}[3]${NC}  ℹ   Statut du panel installé"
    echo -e "  ${Y}[4]${NC}  🔑  Reinitialiser le mot de passe admin"
    echo -e "  ${C}[5]${NC}  📊  Collecte de trafic (Xray / SSH / V2Ray)"
    echo -e "  ${Y}[0]${NC}  ←   Quitter"
    echo ""
    sep
    echo ""
    read -rp "  $(echo -e "${B}Votre choix : ${NC}")" choice

    case "$choice" in
      1) menu_install ;;
      2) menu_uninstall ;;
      3) menu_status ;;
      4) menu_reset_admin ;;
      5) menu_traffic ;;
      0) echo -e "\n  ${C}Au revoir.${NC}\n"; exit 0 ;;
      *) warn "Option invalide. Réessayez."; sleep 1 ;;
    esac
  done
}

# ================================================================
# MENU INSTALLATION
# ================================================================
menu_install() {
  while true; do
    banner
    echo -e "  ${B}INSTALLATION — Configuration${NC}"
    echo ""
    echo -e "  ${C}[1]${NC}  🌐  Domaine avec TLS (HTTPS — Certbot)"
    echo -e "  ${C}[2]${NC}  🖥   Adresse IP sans TLS (HTTP)"
    echo -e "  ${Y}[0]${NC}  ←   Retour au menu principal"
    echo ""
    sep
    echo ""
    read -rp "  $(echo -e "${B}Mode d'accès : ${NC}")" mode

    case "$mode" in
      1) collect_config "domain"; break ;;
      2) collect_config "ip";     break ;;
      0) return ;;
      *) warn "Option invalide."; sleep 1 ;;
    esac
  done
}

# ================================================================
# COLLECTE DE LA CONFIGURATION
# ================================================================
collect_config() {
  local mode="$1"

  banner
  echo -e "  ${B}INSTALLATION — Paramètres${NC}"
  echo ""

  # --- Adresse / Domaine ---
  if [[ "$mode" == "domain" ]]; then
    echo -e "  ${C}Mode :${NC} Domaine avec TLS (HTTPS)"
    echo ""
    while true; do
      read -rp "  $(echo -e "${B}Nom de domaine ${Y}(ex: panel.mondomaine.com)${B} : ${NC}")" DOMAIN
      DOMAIN="${DOMAIN,,}"
      [[ -z "$DOMAIN" ]] && { warn "Le domaine ne peut pas être vide."; continue; }
      [[ "$DOMAIN" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]] && break
      warn "Format de domaine invalide. Réessayez."
    done
    USE_TLS=1
    ACCESS_URL="https://${DOMAIN}"
  else
    echo -e "  ${C}Mode :${NC} Adresse IP sans TLS (HTTP port ${NGINX_PORT})"
    echo ""
    MY_IP=$(curl -s --max-time 4 ifconfig.me 2>/dev/null || curl -s --max-time 4 api.ipify.org 2>/dev/null || echo "")
    if [[ -n "$MY_IP" ]]; then
      echo -e "  ${Y}IP détectée automatiquement : ${B}${MY_IP}${NC}"
      read -rp "  $(echo -e "${B}Adresse IP ${Y}(Entrée pour utiliser ${MY_IP})${B} : ${NC}")" input_ip
      DOMAIN="${input_ip:-$MY_IP}"
    else
      while true; do
        read -rp "  $(echo -e "${B}Adresse IP du VPS : ${NC}")" DOMAIN
        [[ -z "$DOMAIN" ]] && { warn "L'adresse IP ne peut pas être vide."; continue; }
        break
      done
    fi
    USE_TLS=0
    ACCESS_URL="http://${DOMAIN}:${NGINX_PORT}"
  fi

  echo ""
  sep
  echo ""

  # --- Identifiant Admin ---
  echo -e "  ${C}Compte administrateur du panel${NC}"
  echo ""
  while true; do
    read -rp "  $(echo -e "${B}Nom d'utilisateur admin ${Y}(ex: admin)${B} : ${NC}")" ADMIN_USER
    [[ -z "$ADMIN_USER" ]] && { warn "Le nom d'utilisateur ne peut pas être vide."; continue; }
    [[ "${#ADMIN_USER}" -lt 3 ]] && { warn "Minimum 3 caractères."; continue; }
    [[ "$ADMIN_USER" =~ ^[a-zA-Z0-9_-]+$ ]] && break
    warn "Utilisez uniquement des lettres, chiffres, _ ou -"
  done

  echo -e "  ${Y}Caractères autorisés : lettres, chiffres, @  #  _  -  .${NC}"
  echo -e "  ${Y}Evitez les caracteres speciaux comme : point dexclamation dollar guillemets backtick${NC}"
  echo ""
  while true; do
    read -rsp "  $(echo -e "${B}Mot de passe admin ${Y}(min. 8 caractères)${B} : ${NC}")" ADMIN_PASS
    echo ""
    [[ -z "$ADMIN_PASS" ]] && { warn "Le mot de passe ne peut pas être vide."; continue; }
    [[ "${#ADMIN_PASS}" -lt 8 ]] && { warn "Minimum 8 caractères requis."; continue; }
    # Vérifier les caractères interdits qui cassent bash
    if printf "%s" "$ADMIN_PASS" | LC_ALL=C grep -q "[^a-zA-Z0-9@#_. -]"; then
      warn "Caractère interdit détecté. Utilisez uniquement : lettres chiffres @ # _ - ."
      continue
    fi
    read -rsp "  $(echo -e "${B}Confirmez le mot de passe : ${NC}")" ADMIN_PASS2
    echo ""
    [[ "$ADMIN_PASS" == "$ADMIN_PASS2" ]] && break
    warn "Les mots de passe ne correspondent pas. Réessayez."
  done

  echo ""
  sep
  echo ""

  # --- Récapitulatif ---
  echo -e "  ${B}RÉCAPITULATIF${NC}"
  echo ""
  echo -e "  ${C}Mode :${NC}        $([ $USE_TLS -eq 1 ] && echo "HTTPS avec TLS" || echo "HTTP sans TLS")"
  echo -e "  ${C}Adresse :${NC}     ${B}${ACCESS_URL}${NC}"
  echo -e "  ${C}Admin URL :${NC}   ${B}${ACCESS_URL}/admin${NC}"
  echo -e "  ${C}Username :${NC}    ${B}${ADMIN_USER}${NC}"
  echo -e "  ${C}Password :${NC}    ${B}${ADMIN_PASS//?/*}${NC} (masqué)"
  echo -e "  ${C}Port Nginx :${NC}  ${B}${NGINX_PORT}${NC} (compatible Xray)"
  echo -e "  ${C}Port Node :${NC}   ${B}${NODE_PORT}${NC} (interne uniquement)"
  echo ""

  if ! confirm "Lancer l'installation avec ces paramètres ?"; then
    warn "Installation annulée."
    pause
    return
  fi

  # Lancer l'installation
  do_install
}

# ================================================================
# INSTALLATION PRINCIPALE
# ================================================================
do_install() {
  # Vérifications root + fichiers
  [[ $EUID -ne 0 ]] && die "Exécutez en root : sudo bash install.sh"

  for f in server.js schema.sql admin.html reseller.html; do
    [[ ! -f "$SCRIPT_DIR/$f" ]] && die "Fichier manquant : $f (doit être dans le même dossier que install.sh)"
  done

  # Vérifier si déjà installé
  if [[ -d "$INSTALL_DIR" ]]; then
    warn "Un panel est déjà installé dans $INSTALL_DIR."
    if ! confirm "Écraser l'installation existante ?"; then
      warn "Installation annulée."
      pause
      return
    fi
    info "Suppression de l'ancienne installation..."
    pm2 delete kighmu-panel 2>/dev/null || true
    rm -rf "$INSTALL_DIR"
  fi

  banner
  echo -e "  ${B}INSTALLATION EN COURS...${NC}"
  echo ""
  sep
  echo ""

  # Générer les secrets
  DB_PASS=$(openssl rand -base64 20 | tr -d '=/+' | head -c 24)
  JWT_SECRET=$(openssl rand -base64 64 | tr -d '=/+\n' | head -c 72)

  # ── 1. Mise à jour système ──────────────────────────────────
  info "Mise à jour des paquets système..."
  apt-get update -qq 2>/dev/null
  apt-get upgrade -y -qq 2>/dev/null
  ok "Système à jour"

  # ── 2. Node.js 20 ──────────────────────────────────────────
  if ! command -v node &>/dev/null || [[ $(node -v 2>/dev/null | cut -dv -f2 | cut -d. -f1) -lt 18 ]]; then
    info "Installation de Node.js 20..."
    apt-get install -y -qq curl 2>/dev/null
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
    apt-get install -y -qq nodejs 2>/dev/null
  fi
  ok "Node.js $(node -v)"

  # ── 3. MySQL ────────────────────────────────────────────────
  if ! command -v mysql &>/dev/null; then
    info "Installation de MySQL Server..."
    apt-get install -y -qq mysql-server 2>/dev/null
    systemctl start mysql
    systemctl enable mysql
  fi
  ok "MySQL $(mysql --version | awk '{print $3}')"

  # ── 4. Base de données ──────────────────────────────────────
  info "Création de la base de données..."
  mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || die "Erreur MySQL : impossible de créer la base"
  mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';" 2>/dev/null
  mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null
  # Import du schéma
  mysql "${DB_NAME}" < "$SCRIPT_DIR/schema.sql" 2>/dev/null || die "Erreur import schema.sql"
  # Hash admin généré après npm install (voir étape 7)
  ADMIN_HASH=""  # sera généré après npm install

  # ── 5. Déploiement des fichiers ─────────────────────────────
  info "Déploiement des fichiers du panel..."
  mkdir -p "$INSTALL_DIR/frontend/admin" "$INSTALL_DIR/frontend/reseller"
  cp "$SCRIPT_DIR/server.js"      "$INSTALL_DIR/server.js"
  cp "$SCRIPT_DIR/admin.html"     "$INSTALL_DIR/frontend/admin/index.html"
  cp "$SCRIPT_DIR/reseller.html"  "$INSTALL_DIR/frontend/reseller/index.html"

  # Page d'accueil
  cat > "$INSTALL_DIR/frontend/index.html" << 'LANDING'
<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Kighmu Panel</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{background:#030712;color:#e2e8f0;font-family:'Courier New',monospace;min-height:100vh;display:flex;align-items:center;justify-content:center;overflow:hidden}.grid{position:fixed;inset:0;background-image:linear-gradient(rgba(0,200,255,.025) 1px,transparent 1px),linear-gradient(90deg,rgba(0,200,255,.025) 1px,transparent 1px);background-size:50px 50px}.glow{position:fixed;width:600px;height:600px;border-radius:50%;background:radial-gradient(circle,rgba(0,150,255,.08),transparent 70%);top:50%;left:50%;transform:translate(-50%,-50%);animation:pulse 4s ease-in-out infinite}@keyframes pulse{0%,100%{opacity:.5;transform:translate(-50%,-50%) scale(1)}50%{opacity:1;transform:translate(-50%,-50%) scale(1.1)}}.box{position:relative;z-index:1;text-align:center;padding:2rem}.logo{font-size:3rem;font-weight:700;letter-spacing:.3em;background:linear-gradient(135deg,#00c8ff,#7c3aed);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text;text-transform:uppercase;margin-bottom:.5rem}.sub{color:#475569;font-size:.72rem;letter-spacing:.4em;text-transform:uppercase;margin-bottom:3rem}.sep{width:200px;height:1px;background:linear-gradient(90deg,transparent,#00c8ff,transparent);margin:0 auto 3rem}.btns{display:flex;gap:1.5rem;justify-content:center;flex-wrap:wrap}.btn{display:inline-block;padding:1rem 2.5rem;text-decoration:none;font-family:'Courier New',monospace;font-size:.85rem;letter-spacing:.2em;text-transform:uppercase;border-radius:4px;transition:all .3s}.ba{background:transparent;border:1px solid #00c8ff;color:#00c8ff}.ba:hover{background:#00c8ff;color:#030712;box-shadow:0 0 30px rgba(0,200,255,.5)}.br{background:transparent;border:1px solid #7c3aed;color:#a78bfa}.br:hover{background:#7c3aed;color:#fff;box-shadow:0 0 30px rgba(124,58,237,.5)}.ver{position:fixed;bottom:1rem;right:1rem;color:#334155;font-size:.7rem}</style>
</head><body><div class="grid"></div><div class="glow"></div>
<div class="box"><div class="logo">KIGHMU</div><div class="sub">Tunnel Management System v2</div><div class="sep"></div>
<div class="btns"><a href="/admin" class="btn ba">⬡ Admin Panel</a><a href="/reseller" class="btn br">⬡ Reseller Panel</a></div></div>
<div class="ver">KIGHMU v2.0</div></body></html>
LANDING
  ok "Fichiers déployés dans $INSTALL_DIR"

  # ── 6. Fichier .env ─────────────────────────────────────────
  info "Génération du fichier de configuration .env..."
  cat > "$INSTALL_DIR/.env" << ENVFILE
# ============================================================
# KIGHMU PANEL v2 — Configuration générée par install.sh
# ============================================================
PORT=${NODE_PORT}
NODE_ENV=production

# Base de données MySQL
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASS}

# Sécurité JWT
JWT_SECRET=${JWT_SECRET}
JWT_EXPIRES_IN=8h
BCRYPT_ROUNDS=12

# Protection brute-force
MAX_LOGIN_ATTEMPTS=5
BLOCK_DURATION_MINUTES=30

# Chemins des configurations tunnel
XRAY_CONFIG=/etc/xray/config.json
V2RAY_CONFIG=/etc/v2ray/config.json
HYSTERIA_USERS=/etc/hysteria/users.json
ZIVPN_USERS=/etc/udp/users.txt

# Collecte trafic (script traffic-collect.sh)
REPORT_SECRET=${REPORT_SECRET}
ENVFILE
  ok "Fichier .env créé"

  # ── 7. package.json + npm install ──────────────────────────
  info "Création du package.json..."
  cat > "$INSTALL_DIR/package.json" << 'PKG'
{
  "name": "kighmu-panel",
  "version": "2.0.0",
  "description": "Kighmu VPN Tunnel Management Panel",
  "main": "server.js",
  "scripts": { "start": "node server.js" },
  "dependencies": {
    "express": "^4.18.2",
    "mysql2": "^3.6.5",
    "bcryptjs": "^2.4.3",
    "jsonwebtoken": "^9.0.2",
    "dotenv": "^16.3.1",
    "helmet": "^7.1.0",
    "cors": "^2.8.5",
    "uuid": "^9.0.0",
    "node-cron": "^3.0.3",
    "systeminformation": "^5.21.20",
    "express-rate-limit": "^7.1.5"
  }
}
PKG

  info "Installation des dépendances Node.js..."
  cd "$INSTALL_DIR" && npm install --production --quiet 2>/dev/null
  ok "Dépendances npm installées"

  # ── Création compte admin ───────────────────────────────────
  info "Création du compte administrateur..."
  _create_admin "${ADMIN_USER}" "${ADMIN_PASS}" && \
    ok "Admin '${ADMIN_USER}' configuré avec votre mot de passe" || \
    { warn "Fallback : admin / Admin2024"; ADMIN_USER="admin"; ADMIN_PASS="Admin2024"; _create_admin "admin" "Admin2024"; }

  # ── 8. PM2 ──────────────────────────────────────────────────
  info "Installation et démarrage PM2..."
  npm install -g pm2 --quiet 2>/dev/null
  pm2 delete kighmu-panel 2>/dev/null || true
  cd "$INSTALL_DIR"
  pm2 start server.js --name kighmu-panel --time --cwd "$INSTALL_DIR"
  pm2 save --force >/dev/null 2>&1
  # Activer le démarrage automatique
  PM2_STARTUP=$(pm2 startup 2>/dev/null | grep "sudo" | head -1)
  if [[ -n "$PM2_STARTUP" ]]; then
    eval "$PM2_STARTUP" >/dev/null 2>&1 || true
  fi
  ok "Panel démarré avec PM2"

  # ── 9. Nginx ────────────────────────────────────────────────
  info "Installation et configuration Nginx (port ${NGINX_PORT})..."
  apt-get install -y -qq nginx 2>/dev/null

  # Arrêter Nginx proprement avant de reconfigurer
  systemctl stop nginx 2>/dev/null || true

  # Désactiver le site default qui pourrait entrer en conflit
  rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

  # ── CORRECTION CRITIQUE : certificats SSL manquants ──────────
  # Nginx peut refuser de démarrer si d'autres configs (ex: Xray)
  # référencent des certificats SSL qui n'existent pas encore.
  # On détecte et corrige automatiquement ce cas.
  _fix_missing_ssl_certs() {
    info "Vérification des certificats SSL référencés dans Nginx..."

    # Trouver tous les fichiers ssl_certificate dans /etc/nginx/
    local broken=0
    while IFS= read -r certpath; do
      # Ignorer les lignes commentées
      [[ "$certpath" =~ ^[[:space:]]*# ]] && continue
      # Extraire le chemin du certificat
      local path
      path=$(echo "$certpath" | grep -oP '(?<=ssl_certificate\s)[^;]+' | tr -d ' ')
      [[ -z "$path" ]] && continue

      if [[ ! -f "$path" ]]; then
        warn "Certificat manquant référencé dans Nginx : $path"
        broken=1

        # Chercher le certificat via acme.sh (méthode la plus commune avec Xray)
        local domain
        domain=$(basename "$(dirname "$path")")  # ex: /etc/xray/ → xray
        # Chercher dans acme.sh par nom de domaine ou pattern
        local acme_cert
        acme_cert=$(find /root/.acme.sh/ -name "fullchain.cer" 2>/dev/null | head -1)
        local acme_key
        acme_key=$(find /root/.acme.sh/ -name "*.key" 2>/dev/null | head -1)

        if [[ -n "$acme_cert" && -n "$acme_key" ]]; then
          local cert_dir
          cert_dir=$(dirname "$path")
          mkdir -p "$cert_dir"
          cp "$acme_cert" "$path"
          # Trouver le fichier .key correspondant (ssl_certificate_key)
          local keypath
          keypath=$(grep -r "ssl_certificate_key" /etc/nginx/ 2>/dev/null \
            | grep -v "^#" \
            | grep -oP '(?<=ssl_certificate_key\s)[^;]+' \
            | tr -d ' ' | head -1)
          if [[ -n "$keypath" && ! -f "$keypath" ]]; then
            mkdir -p "$(dirname "$keypath")"
            cp "$acme_key" "$keypath"
            chmod 600 "$keypath"
            ok "Clé privée restaurée → $keypath"
          fi
          ok "Certificat restauré depuis acme.sh → $path"

          # Configurer le renouvellement automatique pour ce domaine
          local acme_domain
          acme_domain=$(basename "$(dirname "$acme_cert")" | sed 's/_ecc$//')
          if [[ -n "$acme_domain" ]]; then
            /root/.acme.sh/acme.sh --install-cert -d "$acme_domain" --ecc \
              --cert-file "$path" \
              --key-file "${keypath:-$cert_dir/xray.key}" \
              --reloadcmd "systemctl reload nginx" \
              >/dev/null 2>&1 && ok "Renouvellement automatique configuré pour $acme_domain" || true
          fi
        else
          # Pas de certificat acme.sh trouvé — commenter le bloc SSL cassé
          warn "Aucun certificat acme.sh trouvé. Désactivation temporaire du bloc SSL cassé..."
          local conffile
          conffile=$(grep -rl "$path" /etc/nginx/ 2>/dev/null | head -1)
          if [[ -n "$conffile" ]]; then
            # Sauvegarder et commenter les lignes ssl_certificate cassées
            cp "$conffile" "${conffile}.bak.$(date +%s)"
            sed -i "s|ssl_certificate[^_]|# ssl_certificate |g" "$conffile"
            sed -i "s|ssl_certificate_key|# ssl_certificate_key|g" "$conffile"
            sed -i "s|listen.*ssl|# listen_ssl_disabled|g" "$conffile"
            warn "Config SSL désactivée temporairement dans : $conffile"
            warn "Sauvegarde : ${conffile}.bak.*"
          fi
        fi
      fi
    done < <(grep -rh "ssl_certificate " /etc/nginx/ 2>/dev/null)

    if [[ $broken -eq 0 ]]; then
      ok "Tous les certificats SSL Nginx sont présents"
    fi
  }

  _fix_missing_ssl_certs

  # ── Écrire la config Kighmu ──────────────────────────────────
  if [[ $USE_TLS -eq 1 ]]; then
    # Config HTTP temporaire pour la validation Certbot
    cat > /etc/nginx/sites-available/kighmu << NGINXTEMP
server {
    listen ${NGINX_PORT};
    listen [::]:${NGINX_PORT};
    server_name ${DOMAIN};
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    location / {
        proxy_pass         http://127.0.0.1:${NODE_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
    }
}
NGINXTEMP

    ln -sf /etc/nginx/sites-available/kighmu /etc/nginx/sites-enabled/kighmu

    # Test + démarrage avant Certbot
    if nginx -t 2>/tmp/nginx_test.log; then
      systemctl start nginx && systemctl enable nginx
      ok "Nginx démarré (HTTP temporaire)"
    else
      err "Nginx échoue encore après correction des certificats :"
      cat /tmp/nginx_test.log
      die "Corrigez la config Nginx manuellement puis relancez."
    fi

    # Certbot pour obtenir le certificat TLS
    command -v certbot &>/dev/null || apt-get install -y -qq certbot python3-certbot-nginx 2>/dev/null
    info "Obtention du certificat TLS pour ${DOMAIN}..."
    warn "Port 80 ouvert brièvement pour la validation ACME..."
    ufw allow 80/tcp >/dev/null 2>&1 || true

    if certbot certonly --webroot -w /var/www/html \
        -d "${DOMAIN}" --non-interactive --agree-tos \
        --register-unsafely-without-email 2>/tmp/certbot.log; then
      ok "Certificat TLS obtenu pour ${DOMAIN}"
      ufw delete allow 80/tcp >/dev/null 2>&1 || true

      # Réécrire la config en HTTPS sur le port choisi
      cat > /etc/nginx/sites-available/kighmu << NGINXSSL
server {
    listen ${NGINX_PORT} ssl;
    listen [::]:${NGINX_PORT} ssl;
    server_name ${DOMAIN};
    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    location / {
        proxy_pass         http://127.0.0.1:${NODE_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto https;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
    }
}
NGINXSSL
      ACCESS_URL="https://${DOMAIN}:${NGINX_PORT}"
      nginx -t 2>/dev/null && systemctl reload nginx
      ok "TLS activé → ${ACCESS_URL}"
    else
      warn "Certbot échoué (voir /tmp/certbot.log) — panel en HTTP sur port ${NGINX_PORT}"
      ufw delete allow 80/tcp >/dev/null 2>&1 || true
      ACCESS_URL="http://${DOMAIN}:${NGINX_PORT}"
    fi

  else
    # Config HTTP simple (accès par IP)
    cat > /etc/nginx/sites-available/kighmu << NGINXHTTP
server {
    listen ${NGINX_PORT};
    listen [::]:${NGINX_PORT};
    server_name ${DOMAIN} _;
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    location / {
        proxy_pass         http://127.0.0.1:${NODE_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
    }
}
NGINXHTTP
    ln -sf /etc/nginx/sites-available/kighmu /etc/nginx/sites-enabled/kighmu
    ACCESS_URL="http://${DOMAIN}:${NGINX_PORT}"
  fi

  # ── Démarrage final Nginx avec diagnostic clair ──────────────
  if nginx -t 2>/tmp/nginx_test.log; then
    systemctl start nginx 2>/dev/null || true
    systemctl enable nginx 2>/dev/null || true
    sleep 1
    if systemctl is-active nginx >/dev/null 2>&1; then
      ok "Nginx actif sur le port ${NGINX_PORT}"
    else
      err "Nginx a démarré puis s'est arrêté immédiatement."
      warn "Consultez les logs : journalctl -u nginx -n 20 --no-pager"
    fi
  else
    err "La configuration Nginx contient encore des erreurs :"
    cat /tmp/nginx_test.log
    echo ""
    warn "Le panel Node.js fonctionne sur http://127.0.0.1:${NODE_PORT}"
    warn "Corrigez Nginx manuellement puis : systemctl start nginx"
    warn "Fichiers de config Nginx : /etc/nginx/conf.d/ et /etc/nginx/sites-enabled/"
  fi

  # ── 10. Firewall ────────────────────────────────────────────
  if command -v ufw &>/dev/null; then
    ufw allow ${NGINX_PORT}/tcp >/dev/null 2>&1 || true
    ufw deny  ${NODE_PORT}/tcp  >/dev/null 2>&1 || true
    ok "Firewall : port ${NGINX_PORT} ouvert, ${NODE_PORT} bloqué (interne uniquement)"
  fi



  # ── Déploiement du script de collecte de trafic ─────────────
  info "Déploiement du script de collecte de trafic..."
  setup_traffic_cron "silent"
  ok "Collecte trafic configurée (cron toutes les 10 min)"

  # ── Sauvegarde des infos ─────────────────────────────────────
  cat > "$INSTALL_DIR/.install_info" << INFOFILE
DOMAIN=${DOMAIN}
ADMIN_USER=${ADMIN_USER}
USE_TLS=${USE_TLS}
ACCESS_URL=${ACCESS_URL}
NGINX_PORT=${NGINX_PORT}
NODE_PORT=${NODE_PORT}
INSTALL_DATE=$(date '+%Y-%m-%d %H:%M:%S')
INFOFILE

  # ── Test final ───────────────────────────────────────────────
  echo ""
  info "Vérification finale..."
  sleep 2
  NODE_OK=0; NGINX_OK=0
  curl -sf --max-time 5 "http://127.0.0.1:${NODE_PORT}/health" | grep -q '"panel"' && NODE_OK=1
  curl -sf --max-time 5 "http://127.0.0.1:${NGINX_PORT}/"      | grep -qi "kighmu\|html" && NGINX_OK=1
  [[ $NODE_OK  -eq 1 ]] && ok "Node.js opérationnel (port ${NODE_PORT})" || warn "Node.js ne répond pas → pm2 logs kighmu-panel"
  [[ $NGINX_OK -eq 1 ]] && ok "Nginx proxy opérationnel (port ${NGINX_PORT})" || warn "Nginx ne répond pas → nginx -t && systemctl status nginx"

  # ── Résumé ───────────────────────────────────────────────────
  echo ""
  sep
  echo ""
  echo -e "  ${G}${B}╔══════════════════════════════════════════════════╗${NC}"
  echo -e "  ${G}${B}║      KIGHMU PANEL v2 — INSTALLATION RÉUSSIE !    ║${NC}"
  echo -e "  ${G}${B}╚══════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${C}🌐 Accès :${NC}"
  echo -e "     ${B}${ACCESS_URL}${NC}"
  echo -e "     ${B}${ACCESS_URL}/admin${NC}     ← Admin"
  echo -e "     ${B}${ACCESS_URL}/reseller${NC}  ← Revendeur"
  echo ""
  echo -e "  ${C}🔑 Identifiants admin :${NC}"
  echo -e "     Username : ${B}${ADMIN_USER}${NC}"
  echo -e "     Password : ${B}${ADMIN_PASS}${NC}"
  echo ""
  echo -e "  ${C}🔧 Architecture :${NC}  Internet → Nginx:${B}${NGINX_PORT}${NC} → Node:${B}${NODE_PORT}${NC} (interne)"
  echo -e "  ${C}📋 Commandes :${NC}"
  echo -e "     ${Y}pm2 logs kighmu-panel${NC}    — Logs Node.js"
  echo -e "     ${Y}pm2 restart kighmu-panel${NC} — Redémarrer Node.js"
  echo -e "     ${Y}systemctl restart nginx${NC}  — Redémarrer Nginx"
  echo -e "     ${Y}nginx -t${NC}                 — Tester config Nginx"
  echo ""
  sep

  pause
}
# ================================================================
# MENU DÉSINSTALLATION
# ================================================================
menu_uninstall() {
  while true; do
    banner
    echo -e "  ${R}${B}DÉSINSTALLATION / NETTOYAGE${NC}"
    echo ""

    # Afficher ce qui est installé
    if [[ -d "$INSTALL_DIR" ]]; then
      echo -e "  ${G}Panel installé détecté :${NC} $INSTALL_DIR"
      if [[ -f "$INSTALL_DIR/.install_info" ]]; then
        source "$INSTALL_DIR/.install_info" 2>/dev/null
        echo -e "  ${C}Domaine/IP :${NC} ${DOMAIN:-inconnu}"
        echo -e "  ${C}Admin :${NC}      ${ADMIN_USER:-inconnu}"
        echo -e "  ${C}Installé le :${NC} ${INSTALL_DATE:-inconnu}"
      fi
    else
      echo -e "  ${Y}Aucun panel installé détecté dans $INSTALL_DIR${NC}"
    fi

    echo ""
    echo -e "  ${R}[1]${NC}  💣  Désinstallation complète (panel + DB + Nginx)"
    echo -e "  ${Y}[2]${NC}  🔄  Désinstaller uniquement le panel (garder DB)"
    echo -e "  ${Y}[3]${NC}  🗄   Supprimer uniquement la base de données"
    echo -e "  ${C}[0]${NC}  ←   Retour au menu principal"
    echo ""
    sep
    echo ""
    read -rp "  $(echo -e "${B}Votre choix : ${NC}")" choice

    case "$choice" in
      1) uninstall_full ;;
      2) uninstall_panel_only ;;
      3) uninstall_db_only ;;
      0) return ;;
      *) warn "Option invalide."; sleep 1 ;;
    esac
  done
}

uninstall_full() {
  banner
  echo -e "  ${R}${B}DÉSINSTALLATION COMPLÈTE${NC}"
  echo ""
  echo -e "  ${Y}Cette action va supprimer :${NC}"
  echo -e "   • Le panel dans $INSTALL_DIR"
  echo -e "   • La base de données MySQL '${DB_NAME}'"
  echo -e "   • L'utilisateur MySQL '${DB_USER}'"
  echo -e "   • La configuration Nginx kighmu"
  echo -e "   • Le processus PM2 kighmu-panel"
  echo ""

  if ! confirm "Confirmer la désinstallation COMPLÈTE ? Cette action est irréversible."; then
    warn "Désinstallation annulée."
    pause
    return
  fi

  _stop_pm2
  _remove_nginx
  _remove_database
  _remove_files

  echo ""
  ok "Désinstallation complète terminée."
  echo -e "  ${C}Le panel Kighmu a été entièrement supprimé.${NC}"
  pause
}

uninstall_panel_only() {
  banner
  echo -e "  ${Y}${B}DÉSINSTALLATION DU PANEL (base de données conservée)${NC}"
  echo ""

  if ! confirm "Supprimer le panel (fichiers + PM2 + Nginx) mais garder la base de données ?"; then
    warn "Annulé."
    pause
    return
  fi

  _stop_pm2
  _remove_nginx
  _remove_files

  echo ""
  ok "Panel supprimé. Base de données conservée."
  pause
}

uninstall_db_only() {
  banner
  echo -e "  ${Y}${B}SUPPRESSION DE LA BASE DE DONNÉES${NC}"
  echo ""

  if ! confirm "Supprimer la base de données '${DB_NAME}' et l'utilisateur '${DB_USER}' ?"; then
    warn "Annulé."
    pause
    return
  fi

  _remove_database
  echo ""
  ok "Base de données supprimée."
  pause
}

_stop_pm2() {
  info "Arrêt du panel (PM2)..."
  if command -v pm2 &>/dev/null; then
    pm2 stop kighmu-panel 2>/dev/null || true
    pm2 delete kighmu-panel 2>/dev/null || true
    pm2 save --force >/dev/null 2>&1 || true
    ok "Processus PM2 arrêté et supprimé"
  else
    warn "PM2 non trouvé — rien à arrêter"
  fi
}

_remove_nginx() {
  info "Suppression de la configuration Nginx..."
  rm -f /etc/nginx/sites-enabled/kighmu 2>/dev/null || true
  rm -f /etc/nginx/sites-available/kighmu 2>/dev/null || true
  if command -v nginx &>/dev/null && nginx -t 2>/dev/null; then
    systemctl reload nginx 2>/dev/null || true
    ok "Configuration Nginx supprimée"
  fi
  # Retirer la règle firewall
  ufw delete allow ${NGINX_PORT}/tcp >/dev/null 2>&1 || true
}

_remove_database() {
  info "Suppression de la base de données MySQL..."
  if command -v mysql &>/dev/null; then
    mysql -e "DROP DATABASE IF EXISTS ${DB_NAME};" 2>/dev/null && ok "Base de données '${DB_NAME}' supprimée" || warn "Impossible de supprimer la base de données"
    mysql -e "DROP USER IF EXISTS '${DB_USER}'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null && ok "Utilisateur MySQL '${DB_USER}' supprimé" || warn "Impossible de supprimer l'utilisateur MySQL"
  else
    warn "MySQL non trouvé"
  fi
}

_remove_files() {
  info "Suppression des fichiers du panel..."
  if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    ok "Dossier $INSTALL_DIR supprimé"
  else
    warn "Dossier $INSTALL_DIR introuvable"
  fi
}

# ================================================================
# STATUT DU PANEL
# ================================================================
menu_status() {
  banner
  echo -e "  ${B}STATUT DU PANEL${NC}"
  echo ""

  # Fichiers
  if [[ -d "$INSTALL_DIR" ]]; then
    echo -e "  ${G}[✓]${NC} Fichiers installés dans : ${C}$INSTALL_DIR${NC}"
    if [[ -f "$INSTALL_DIR/.install_info" ]]; then
      source "$INSTALL_DIR/.install_info" 2>/dev/null
      echo -e "  ${G}[✓]${NC} Domaine / IP : ${C}${DOMAIN:-?}${NC}"
      echo -e "  ${G}[✓]${NC} Admin        : ${C}${ADMIN_USER:-?}${NC}"
      echo -e "  ${G}[✓]${NC} URL d'accès  : ${C}${ACCESS_URL:-?}${NC}"
      echo -e "  ${G}[✓]${NC} Date install : ${C}${INSTALL_DATE:-?}${NC}"
    fi
  else
    echo -e "  ${R}[✗]${NC} Panel non installé ($INSTALL_DIR introuvable)"
  fi

  echo ""

  # PM2
  if command -v pm2 &>/dev/null; then
    PM2_STATUS=$(pm2 list 2>/dev/null | grep kighmu-panel | awk '{print $12}' || echo "")
    if [[ "$PM2_STATUS" == "online" ]]; then
      echo -e "  ${G}[✓]${NC} PM2 : ${G}online${NC}"
    elif [[ -n "$PM2_STATUS" ]]; then
      echo -e "  ${Y}[!]${NC} PM2 : ${Y}${PM2_STATUS}${NC}"
    else
      echo -e "  ${R}[✗]${NC} PM2 : non démarré"
    fi
  else
    echo -e "  ${R}[✗]${NC} PM2 non installé"
  fi

  # Nginx
  if command -v nginx &>/dev/null; then
    if nginx -t 2>/dev/null; then
      echo -e "  ${G}[✓]${NC} Nginx : opérationnel (port ${NGINX_PORT})"
    else
      echo -e "  ${Y}[!]${NC} Nginx : erreur de configuration"
    fi
  else
    echo -e "  ${R}[✗]${NC} Nginx non installé"
  fi

  # MySQL
  if command -v mysql &>/dev/null; then
    if mysql -e "USE ${DB_NAME};" 2>/dev/null; then
      echo -e "  ${G}[✓]${NC} MySQL : base de données '${DB_NAME}' accessible"
    else
      echo -e "  ${Y}[!]${NC} MySQL : base de données '${DB_NAME}' inaccessible"
    fi
  else
    echo -e "  ${R}[✗]${NC} MySQL non installé"
  fi

  # Port en écoute
  echo ""
  if command -v ss &>/dev/null; then
    if ss -tlnp 2>/dev/null | grep -q ":${NODE_PORT} "; then
      echo -e "  ${G}[✓]${NC} Port Node.js ${NODE_PORT} : en écoute"
    else
      echo -e "  ${R}[✗]${NC} Port Node.js ${NODE_PORT} : non actif"
    fi
    if ss -tlnp 2>/dev/null | grep -q ":${NGINX_PORT} "; then
      echo -e "  ${G}[✓]${NC} Port Nginx ${NGINX_PORT} : en écoute"
    else
      echo -e "  ${R}[✗]${NC} Port Nginx ${NGINX_PORT} : non actif"
    fi
  fi

  echo ""
  sep
  pause
}

# ================================================================
# RESET MOT DE PASSE ADMIN
# ================================================================
menu_reset_admin() {
  banner
  echo -e "  ${Y}${B}RÉINITIALISATION MOT DE PASSE ADMIN${NC}"
  echo ""

  if [[ ! -d "$INSTALL_DIR" ]]; then
    err "Panel non installé ($INSTALL_DIR introuvable)."
    pause; return
  fi

  # Saisie nouveau username
  while true; do
    read -rp "  $(echo -e "${B}Nouveau username admin : ${NC}")" NEW_USER
    [[ -z "$NEW_USER" ]] && { warn "Ne peut pas être vide."; continue; }
    [[ "${#NEW_USER}" -lt 3 ]] && { warn "Minimum 3 caractères."; continue; }
    [[ "$NEW_USER" =~ ^[a-zA-Z0-9_-]+$ ]] && break
    warn "Lettres, chiffres, _ ou - uniquement."
  done

  # Saisie nouveau mot de passe
  echo -e "  ${Y}Caractères autorisés : lettres chiffres @ # _ - .${NC}"
  while true; do
    read -rsp "  $(echo -e "${B}Nouveau mot de passe (min. 8 car.) : ${NC}")" NEW_PASS
    echo ""
    [[ -z "$NEW_PASS" ]] && { warn "Ne peut pas être vide."; continue; }
    [[ "${#NEW_PASS}" -lt 8 ]] && { warn "Minimum 8 caractères."; continue; }
    if printf "%s" "$NEW_PASS" | LC_ALL=C grep -q "[^a-zA-Z0-9@#_. -]"; then
      warn "Caractère interdit. Utilisez : lettres chiffres @ # _ - ."
      continue
    fi
    read -rsp "  $(echo -e "${B}Confirmez le mot de passe : ${NC}")" NEW_PASS2
    echo ""
    [[ "$NEW_PASS" == "$NEW_PASS2" ]] && break
    warn "Les mots de passe ne correspondent pas."
  done

  echo ""
  info "Mise à jour du compte admin..."

  if _create_admin "${NEW_USER}" "${NEW_PASS}"; then
    echo ""
    ok "Compte admin réinitialisé avec succès !"
    echo ""
    echo -e "  ${C}Username :${NC} ${B}${NEW_USER}${NC}"
    echo -e "  ${C}Password :${NC} ${B}${NEW_PASS}${NC}"
    echo ""
    # Redémarrer PM2 pour vider le cache JWT
    pm2 restart kighmu-panel >/dev/null 2>&1 && ok "Panel redémarré (cache JWT vidé)" || true
  else
    err "Echec de la réinitialisation. Vérifiez :"
    warn "  • MySQL actif :  systemctl status mysql"
    warn "  • .env correct : cat /opt/kighmu-panel/.env"
  fi

  pause
}


# ================================================================
# COLLECTE DE TRAFIC VPN — Script + Cron
# ================================================================
setup_traffic_cron() {
  local silent="${1:-}"

  # Lire le REPORT_SECRET depuis le .env si installé
  local secret="${REPORT_SECRET:-}"
  if [[ -z "$secret" && -f "$INSTALL_DIR/.env" ]]; then
    secret=$(grep '^REPORT_SECRET=' "$INSTALL_DIR/.env" 2>/dev/null | cut -d'=' -f2)
  fi
  [[ -z "$secret" ]] && secret="kighmu-report-$(date +%s)"

  local panel_url="http://127.0.0.1:${NODE_PORT}"

  # Créer le répertoire kighmu
  mkdir -p /etc/kighmu

  # ── Écrire le script traffic-collect.sh ──────────────────
  cat > "$TRAFFIC_SCRIPT" << TRAFFIC_EOF
#!/bin/bash
# =============================================================
# KIGHMU PANEL v2 — Collecte des statistiques de trafic VPN
# Généré par install.sh — NE PAS MODIFIER MANUELLEMENT
# =============================================================
PANEL_URL="${panel_url}"
SECRET="${secret}"
XRAY_BIN="\${XRAY_BIN:-/usr/local/bin/xray}"
XRAY_API="\${XRAY_API:-127.0.0.1:10085}"
V2RAY_BIN="\${V2RAY_BIN:-/usr/local/bin/v2ray}"
V2RAY_API="\${V2RAY_API:-127.0.0.1:10086}"
TS="\$(date '+%Y-%m-%d %H:%M:%S')"

send_stats() {
  local json="\$1"
  local resp
  resp=\$(curl -s --max-time 10 -X POST "\${PANEL_URL}/api/report/traffic" \\
    -H "Content-Type: application/json" \\
    -H "x-report-secret: \${SECRET}" \\
    -d "\${json}" 2>/dev/null)
  echo "[\${TS}] → \${resp:-no response}"
}

# ── XRAY : API gRPC statsquery ──────────────────────────────
collect_xray() {
  [ ! -x "\$XRAY_BIN" ] && return
  local raw
  raw=\$("\$XRAY_BIN" api statsquery --server="\$XRAY_API" 2>/dev/null) || return
  [ -z "\$raw" ] && return

  local json='{"stats":[' first=1
  declare -A up_map down_map

  while IFS= read -r line; do
    if [[ "\$line" =~ name:\"user\>\>\>([^\>]+)\>\>\>traffic\>\>\>(up|down)link\" ]]; then
      local user="\${BASH_REMATCH[1]}" dir="\${BASH_REMATCH[2]}"
      local val; [[ "\$line" =~ value:\"([0-9]+)\" ]] && val="\${BASH_REMATCH[1]}" || val=0
      [[ "\$dir" == "up"   ]] && up_map["\$user"]=\$(( \${up_map["\$user"]:-0}   + val ))
      [[ "\$dir" == "down" ]] && down_map["\$user"]=\$(( \${down_map["\$user"]:-0} + val ))
    fi
  done <<< "\$raw"

  for user in "\${!up_map[@]}" "\${!down_map[@]}"; do
    local up="\${up_map[\$user]:-0}" dn="\${down_map[\$user]:-0}"
    (( up + dn == 0 )) && continue
    [ \$first -eq 0 ] && json+=","
    json+="{\"username\":\"\$user\",\"upload_bytes\":\$up,\"download_bytes\":\$dn}"
    first=0
  done

  json+=']}' 
  [ "\$first" -ne 1 ] && { echo "[\${TS}] [XRAY] Envoi stats..."; send_stats "\$json"; } || echo "[\${TS}] [XRAY] Aucune stat"
}

# ── V2RAY : même format qu'Xray ─────────────────────────────
collect_v2ray() {
  [ ! -x "\$V2RAY_BIN" ] && return
  local raw
  raw=\$("\$V2RAY_BIN" api statsquery --server="\$V2RAY_API" 2>/dev/null) || return
  [ -z "\$raw" ] && return

  local json='{"stats":[' first=1
  declare -A up_map down_map

  while IFS= read -r line; do
    if [[ "\$line" =~ name:\"user\>\>\>([^\>]+)\>\>\>traffic\>\>\>(up|down)link\" ]]; then
      local user="\${BASH_REMATCH[1]}" dir="\${BASH_REMATCH[2]}"
      local val; [[ "\$line" =~ value:\"([0-9]+)\" ]] && val="\${BASH_REMATCH[1]}" || val=0
      [[ "\$dir" == "up"   ]] && up_map["\$user"]=\$(( \${up_map["\$user"]:-0}   + val ))
      [[ "\$dir" == "down" ]] && down_map["\$user"]=\$(( \${down_map["\$user"]:-0} + val ))
    fi
  done <<< "\$raw"

  for user in "\${!up_map[@]}" "\${!down_map[@]}"; do
    local up="\${up_map[\$user]:-0}" dn="\${down_map[\$user]:-0}"
    (( up + dn == 0 )) && continue
    [ \$first -eq 0 ] && json+=","
    json+="{\"username\":\"\$user\",\"upload_bytes\":\$up,\"download_bytes\":\$dn}"
    first=0
  done

  json+=']}' 
  [ "\$first" -ne 1 ] && send_stats "\$json" || echo "[\${TS}] [V2RAY] Aucune stat"
}

# ── SSH : comptage via iptables par uid ─────────────────────
collect_ssh() {
  local USER_FILE="/etc/kighmu/users.list"
  [ ! -f "\$USER_FILE" ] && return
  command -v iptables &>/dev/null || return

  local json='{"stats":[' first=1

  while IFS='|' read -r username _rest; do
    [ -z "\$username" ] && continue
    local uid; uid=\$(id -u "\$username" 2>/dev/null) || continue
    local dn up
    dn=\$(iptables -n -L OUTPUT -v -x 2>/dev/null | awk -v u="\$uid" '\$0 ~ "uid-owner " u {sum+=\$2} END{print sum+0}')
    up=\$(iptables -n -L INPUT  -v -x 2>/dev/null | awk -v u="\$uid" '\$0 ~ "uid-owner " u {sum+=\$2} END{print sum+0}')
    (( \${up:-0} + \${dn:-0} == 0 )) && continue
    [ \$first -eq 0 ] && json+=","
    json+="{\"username\":\"\$username\",\"upload_bytes\":\${up:-0},\"download_bytes\":\${dn:-0}}"
    first=0
  done < "\$USER_FILE"

  json+=']}' 
  [ "\$first" -ne 1 ] && send_stats "\$json"
}

echo "[\${TS}] === Collecte trafic KIGHMU démarrée ==="
collect_xray
collect_v2ray
collect_ssh
echo "[\${TS}] === Terminé ==="
TRAFFIC_EOF

  chmod +x "$TRAFFIC_SCRIPT"

  # ── Ajouter le cron (toutes les 10 minutes) ───────────────
  local cron_line="*/10 * * * * $TRAFFIC_SCRIPT >> $TRAFFIC_LOG 2>&1"
  # Supprimer ancienne entrée si existe
  crontab -l 2>/dev/null | grep -v "$TRAFFIC_SCRIPT" | crontab - 2>/dev/null || true
  # Ajouter la nouvelle
  ( crontab -l 2>/dev/null; echo "$cron_line" ) | crontab -

  # Créer le fichier log
  touch "$TRAFFIC_LOG"
  chmod 640 "$TRAFFIC_LOG"

  if [[ "$silent" != "silent" ]]; then
    ok "Script déployé : $TRAFFIC_SCRIPT"
    ok "Cron configuré : toutes les 10 minutes"
    ok "Logs : $TRAFFIC_LOG"
  fi
}

# ================================================================
# MENU COLLECTE TRAFIC
# ================================================================
menu_traffic() {
  while true; do
    banner
    echo -e "  ${B}COLLECTE DE TRAFIC VPN${NC}"
    echo ""

    # Statut actuel
    if [[ -f "$TRAFFIC_SCRIPT" ]]; then
      echo -e "  ${G}[✓]${NC} Script installé : ${C}$TRAFFIC_SCRIPT${NC}"
    else
      echo -e "  ${R}[✗]${NC} Script non installé"
    fi

    if crontab -l 2>/dev/null | grep -q "$TRAFFIC_SCRIPT"; then
      echo -e "  ${G}[✓]${NC} Cron actif (toutes les 10 min)"
    else
      echo -e "  ${R}[✗]${NC} Cron non configuré"
    fi

    if [[ -f "$TRAFFIC_LOG" ]]; then
      local last_line
      last_line=$(tail -1 "$TRAFFIC_LOG" 2>/dev/null)
      echo -e "  ${C}[i]${NC} Dernier log : ${last_line:-(vide)}"
    fi

    echo ""
    echo -e "  ${G}[1]${NC}  ▶   Installer / Réinstaller le script + cron"
    echo -e "  ${C}[2]${NC}  ▷   Lancer une collecte manuellement maintenant"
    echo -e "  ${C}[3]${NC}  📄  Voir les derniers logs de collecte (50 lignes)"
    echo -e "  ${R}[4]${NC}  ✕   Désactiver la collecte (supprimer cron + script)"
    echo -e "  ${Y}[0]${NC}  ←   Retour au menu principal"
    echo ""
    sep
    echo ""
    read -rp "  $(echo -e "${B}Votre choix : ${NC}")" choice

    case "$choice" in
      1)
        banner
        echo -e "  ${B}Installation du script de collecte...${NC}"
        echo ""
        setup_traffic_cron
        echo ""
        sep
        pause
        ;;
      2)
        if [[ -x "$TRAFFIC_SCRIPT" ]]; then
          banner
          echo -e "  ${B}Collecte manuelle en cours...${NC}"
          echo ""
          bash "$TRAFFIC_SCRIPT"
          echo ""
          sep
          pause
        else
          warn "Script non installé. Utilisez l'option [1] d'abord."
          sleep 2
        fi
        ;;
      3)
        banner
        echo -e "  ${B}LOGS DE COLLECTE (50 dernières lignes)${NC}"
        echo ""
        if [[ -f "$TRAFFIC_LOG" ]]; then
          tail -50 "$TRAFFIC_LOG"
        else
          warn "Aucun log disponible ($TRAFFIC_LOG introuvable)"
        fi
        echo ""
        sep
        pause
        ;;
      4)
        if confirm "Désactiver la collecte de trafic (supprimer cron + script) ?"; then
          crontab -l 2>/dev/null | grep -v "$TRAFFIC_SCRIPT" | crontab - 2>/dev/null || true
          rm -f "$TRAFFIC_SCRIPT"
          ok "Collecte désactivée"
        fi
        sleep 1
        ;;
      0) return ;;
      *) warn "Option invalide."; sleep 1 ;;
    esac
  done
}

# ================================================================
# POINT D'ENTRÉE
# ================================================================
[[ $EUID -ne 0 ]] && {
  echo -e "${R}[✗] Ce script doit être exécuté en root.${NC}"
  echo -e "    Utilisez : ${Y}sudo bash install.sh${NC}"
  exit 1
}

main_menu
