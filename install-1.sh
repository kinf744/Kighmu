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
NGINX_PORT="81"           # Port public Nginx → compatible Xray qui utilise le 80
DB_NAME="kighmu_panel"
DB_USER="kighmu_user"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
  echo -e "  ${Y}Nginx panel : port ${NGINX_PORT} (Xray utilise le port 80)${NC}"
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
    echo -e "  ${Y}[0]${NC}  ←   Quitter"
    echo ""
    sep
    echo ""
    read -rp "  $(echo -e "${B}Votre choix : ${NC}")" choice

    case "$choice" in
      1) menu_install ;;
      2) menu_uninstall ;;
      3) menu_status ;;
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

  while true; do
    read -rsp "  $(echo -e "${B}Mot de passe admin ${Y}(min. 8 caractères)${B} : ${NC}")" ADMIN_PASS
    echo ""
    [[ -z "$ADMIN_PASS" ]] && { warn "Le mot de passe ne peut pas être vide."; continue; }
    [[ "${#ADMIN_PASS}" -lt 8 ]] && { warn "Minimum 8 caractères."; continue; }
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
  # Mettre à jour le compte admin avec username + mot de passe personnalisés
  # Générer le hash bcrypt via Node.js (cohérent avec bcryptjs dans server.js)
  ADMIN_HASH=$(node -e "const b=require('bcryptjs');console.log(b.hashSync('${ADMIN_PASS}',12));" 2>/dev/null || echo "")
  if [[ -z "$ADMIN_HASH" ]]; then
    # bcryptjs pas encore installé, on l'installe temporairement
    npm install -g bcryptjs --quiet 2>/dev/null || true
    ADMIN_HASH=$(node -e "const b=require('bcryptjs');console.log(b.hashSync('${ADMIN_PASS}',12));" 2>/dev/null || echo "")
  fi
  if [[ -n "$ADMIN_HASH" ]]; then
    mysql "${DB_NAME}" -e "DELETE FROM admins;" 2>/dev/null
    mysql "${DB_NAME}" -e "INSERT INTO admins (username, password) VALUES ('${ADMIN_USER}', '${ADMIN_HASH}');" 2>/dev/null
    ok "Admin '${ADMIN_USER}' créé avec votre mot de passe"
  else
    warn "Hash bcrypt impossible à générer — admin par défaut conservé (admin/Admin@2024)"
    warn "Changez le mot de passe depuis le panel après installation."
  fi

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
DB_HOST=localhost
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

  # Regénérer le hash si besoin (maintenant bcryptjs est dans node_modules)
  if [[ -z "$ADMIN_HASH" ]]; then
    ADMIN_HASH=$(node -e "const b=require('./node_modules/bcryptjs');console.log(b.hashSync('${ADMIN_PASS}',12));" 2>/dev/null || echo "")
    if [[ -n "$ADMIN_HASH" ]]; then
      mysql "${DB_NAME}" -e "DELETE FROM admins;" 2>/dev/null
      mysql "${DB_NAME}" -e "INSERT INTO admins (username, password) VALUES ('${ADMIN_USER}', '${ADMIN_HASH}');" 2>/dev/null
      ok "Admin '${ADMIN_USER}' configuré avec succès"
    fi
  fi

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

  # ── 9. Nginx ── PORT 81 (Xray utilise le 80) ────────────────
  info "Installation et configuration Nginx (port ${NGINX_PORT})..."
  apt-get install -y -qq nginx 2>/dev/null

  # Désactiver le site default
  rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

  if [[ $USE_TLS -eq 1 ]]; then
    # ── Configuration Nginx HTTP temporaire pour Certbot ──
    cat > /etc/nginx/sites-available/kighmu << NGINXHTTP
server {
    listen ${NGINX_PORT};
    listen [::]:${NGINX_PORT};
    server_name ${DOMAIN};

    # Sécurité
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
    nginx -t 2>/dev/null && systemctl reload nginx
    ok "Nginx configuré (port ${NGINX_PORT}) → ${DOMAIN}"

    # ── Certbot pour TLS ──
    if command -v certbot &>/dev/null; then
      info "Certbot déjà installé"
    else
      info "Installation de Certbot..."
      apt-get install -y -qq certbot python3-certbot-nginx 2>/dev/null
    fi

    info "Obtention du certificat TLS pour ${DOMAIN}..."
    warn "Assurez-vous que le port 80 est accessible depuis internet pour la validation ACME"
    echo ""

    # Ouvrir temporairement le port 80 pour Certbot
    ufw allow 80/tcp >/dev/null 2>&1 || true

    if certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos \
        --register-unsafely-without-email \
        --redirect 2>/dev/null; then

      # Après Certbot : forcer le port 81 pour HTTPS aussi
      cat > /etc/nginx/sites-available/kighmu << NGINXHTTPS
server {
    listen ${NGINX_PORT} ssl;
    listen [::]:${NGINX_PORT} ssl;
    server_name ${DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header Strict-Transport-Security "max-age=31536000" always;

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

# Redirection HTTP → HTTPS (port 80 → port 81)
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    return 301 https://\$host:${NGINX_PORT}\$request_uri;
}
NGINXHTTPS

      ACCESS_URL="https://${DOMAIN}:${NGINX_PORT}"
      nginx -t 2>/dev/null && systemctl reload nginx
      ok "TLS activé → ${ACCESS_URL}"
      # Refermer le port 80 (Xray en a besoin)
      ufw delete allow 80/tcp >/dev/null 2>&1 || true
    else
      warn "Certbot a échoué — le panel fonctionne en HTTP sur le port ${NGINX_PORT}"
      warn "Vérifiez que ${DOMAIN} pointe bien vers ce serveur et que le port 80 est ouvert."
      ACCESS_URL="http://${DOMAIN}:${NGINX_PORT}"
    fi

  else
    # ── Configuration Nginx HTTP simple (IP) ──
    cat > /etc/nginx/sites-available/kighmu << NGINXIP
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
NGINXIP

    ln -sf /etc/nginx/sites-available/kighmu /etc/nginx/sites-enabled/kighmu
    nginx -t 2>/dev/null && systemctl reload nginx
    ok "Nginx configuré (port ${NGINX_PORT}) → http://${DOMAIN}:${NGINX_PORT}"
  fi

  # ── 10. Firewall ────────────────────────────────────────────
  if command -v ufw &>/dev/null; then
    ufw allow ${NGINX_PORT}/tcp >/dev/null 2>&1 || true
    # NE PAS ouvrir le port NODE_PORT (3000) — il ne doit pas être accessible directement
    ok "Firewall : port ${NGINX_PORT} autorisé (port ${NODE_PORT} interne uniquement)"
  fi

  # ── Sauvegarde des infos d'installation ─────────────────────
  cat > "$INSTALL_DIR/.install_info" << INFO
DOMAIN=${DOMAIN}
ADMIN_USER=${ADMIN_USER}
USE_TLS=${USE_TLS}
ACCESS_URL=${ACCESS_URL}
NGINX_PORT=${NGINX_PORT}
NODE_PORT=${NODE_PORT}
INSTALL_DATE=$(date '+%Y-%m-%d %H:%M:%S')
INFO

  # ── RÉSUMÉ FINAL ────────────────────────────────────────────
  echo ""
  sep
  echo ""
  echo -e "  ${G}${B}╔══════════════════════════════════════════════════╗${NC}"
  echo -e "  ${G}${B}║      KIGHMU PANEL v2 — INSTALLATION RÉUSSIE !    ║${NC}"
  echo -e "  ${G}${B}╚══════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${C}🌐 Accès au panel :${NC}"
  echo -e "     ${B}${ACCESS_URL}${NC}"
  echo -e "     ${B}${ACCESS_URL}/admin${NC}    ← Panel Admin"
  echo -e "     ${B}${ACCESS_URL}/reseller${NC} ← Panel Revendeur"
  echo ""
  echo -e "  ${C}🔑 Identifiants Admin :${NC}"
  echo -e "     Username : ${B}${ADMIN_USER}${NC}"
  echo -e "     Password : ${B}${ADMIN_PASS}${NC}"
  echo ""
  echo -e "  ${C}🔧 Port Nginx :${NC}   ${B}${NGINX_PORT}${NC}  (Xray garde le port 80)"
  echo -e "  ${C}🔧 Port Node.js :${NC} ${B}${NODE_PORT}${NC} (interne uniquement)"
  echo ""
  echo -e "  ${C}📋 Commandes utiles :${NC}"
  echo -e "     ${Y}pm2 status${NC}                  — Statut"
  echo -e "     ${Y}pm2 logs kighmu-panel${NC}        — Logs en temps réel"
  echo -e "     ${Y}pm2 restart kighmu-panel${NC}     — Redémarrer"
  echo -e "     ${Y}pm2 stop kighmu-panel${NC}        — Arrêter"
  echo ""
  echo -e "  ${Y}⚠  Base de données :${NC} ${DB_NAME} / ${DB_USER}"
  echo -e "  ${Y}⚠  Mot de passe DB :${NC} Voir ${INSTALL_DIR}/.env"
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
# POINT D'ENTRÉE
# ================================================================
[[ $EUID -ne 0 ]] && {
  echo -e "${R}[✗] Ce script doit être exécuté en root.${NC}"
  echo -e "    Utilisez : ${Y}sudo bash install.sh${NC}"
  exit 1
}

main_menu
