#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║          VOANH AI — PANNEAU DE CONTRÔLE VPS v1.0                ║
# ║          Développé pour l'environnement VOANH AI                ║
# ╚══════════════════════════════════════════════════════════════════╝

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VOANH_DIR="/opt/voanh"
LOG_DIR="$VOANH_DIR/logs"
CHATS_DIR="$VOANH_DIR/chats"
UPLOADS_DIR="$VOANH_DIR/uploads"
WORKSPACES_DIR="$VOANH_DIR/workspaces"
SERVICE_BACKEND="voanh-backend"
SERVICE_TERMINAL="voanh-terminal"
NODE_PORT=4000
WS_PORT=4001
NGINX_CONF="/etc/nginx/sites-available/voanh"

# ─── COLORS ────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; RESET='\033[0m'; DIM='\033[2m'
NC='\033[0m'

# ─── HELPERS ───────────────────────────────────────────────────────
log()     { echo -e "${CYAN}[VOANH]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*"; exit 1; }
sep()     { echo -e "${DIM}──────────────────────────────────────────────────${NC}"; }

require_root() {
  [[ $EUID -eq 0 ]] || error "Ce script doit être exécuté en tant que root (sudo ./voanh-server.sh)"
}

banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  cat << 'EOF'
 ██╗   ██╗ ██████╗  █████╗ ███╗   ██╗██╗  ██╗     █████╗ ██╗
 ██║   ██║██╔═══██╗██╔══██╗████╗  ██║██║  ██║    ██╔══██╗██║
 ██║   ██║██║   ██║███████║██╔██╗ ██║███████║    ███████║██║
 ╚██╗ ██╔╝██║   ██║██╔══██║██║╚██╗██║██╔══██║    ██╔══██║██║
  ╚████╔╝ ╚██████╔╝██║  ██║██║ ╚████║██║  ██║    ██║  ██║██║
   ╚═══╝   ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝    ╚═╝  ╚═╝╚═╝
EOF
  echo -e "${RESET}${DIM}           VOANH AI — Panneau de Contrôle VPS v1.0${NC}"
  sep
}

# ─── STATUS ────────────────────────────────────────────────────────
show_status() {
  echo -e "\n${BOLD}  ÉTAT DES SERVICES${NC}"
  sep
  for svc in "$SERVICE_BACKEND" "$SERVICE_TERMINAL" nginx; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      echo -e "  ${GREEN}● $svc${NC}  ${DIM}[ACTIF]${NC}"
    else
      echo -e "  ${RED}○ $svc${NC}  ${DIM}[INACTIF]${NC}"
    fi
  done
  sep
  echo -e "  ${DIM}Backend  API:${NC}  http://localhost:${NODE_PORT}"
  echo -e "  ${DIM}Terminal  WS:${NC}  ws://localhost:${WS_PORT}"
  echo -e "  ${DIM}Répertoire:${NC}    $VOANH_DIR"
  sep
}

# ═══════════════════════════════════════════════════════════════════
# OPTION 1 — INSTALLATION COMPLÈTE
# ═══════════════════════════════════════════════════════════════════
install_all() {
  require_root
  log "Démarrage de l'installation complète VOANH AI..."
  sep

  # ── Paquets système ──────────────────────────────────────────────
  log "Mise à jour du système..."
  apt-get update -qq
  apt-get install -y -qq \
    curl wget git build-essential \
    nginx certbot python3-certbot-nginx \
    htop tmux screen vim nano \
    unzip zip tar \
    python3 python3-pip python3-venv \
    jq net-tools lsof \
    ufw fail2ban \
    > /dev/null 2>&1
  success "Paquets système installés"

  # ── Node.js 20 LTS ───────────────────────────────────────────────
  if ! command -v node &>/dev/null || [[ $(node -v | cut -d. -f1 | tr -d v) -lt 18 ]]; then
    log "Installation de Node.js 20 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
    apt-get install -y -qq nodejs > /dev/null 2>&1
    success "Node.js $(node -v) installé"
  else
    success "Node.js $(node -v) déjà présent"
  fi

  # ── Répertoires ──────────────────────────────────────────────────
  log "Création de l'arborescence VOANH..."
  mkdir -p "$VOANH_DIR"/{logs,chats,uploads,workspaces,public,config,backups}
  mkdir -p "$WORKSPACES_DIR"/{default,projects,scripts,tools}
  chmod 750 "$VOANH_DIR"
  success "Arborescence créée dans $VOANH_DIR"

  # ── Backend Node.js (API REST + WebSocket terminal) ──────────────
  log "Création du serveur backend VOANH..."
  cat > "$VOANH_DIR/package.json" << 'PKGJSON'
{
  "name": "voanh-backend",
  "version": "1.0.0",
  "description": "VOANH AI Backend — API + Terminal WebSocket",
  "main": "server.js",
  "scripts": { "start": "node server.js", "dev": "node --watch server.js" },
  "dependencies": {
    "express": "^4.18.2",
    "ws": "^8.16.0",
    "cors": "^2.8.5",
    "node-pty": "^1.0.0",
    "multer": "^1.4.5-lts.1",
    "fs-extra": "^11.2.0",
    "uuid": "^9.0.0",
    "helmet": "^7.1.0",
    "express-rate-limit": "^7.2.0",
    "morgan": "^1.10.0"
  }
}
PKGJSON

  cat > "$VOANH_DIR/server.js" << 'SERVERJS'
'use strict';
const express    = require('express');
const http       = require('http');
const WebSocket  = require('ws');
const pty        = require('node-pty');
const cors       = require('cors');
const helmet     = require('helmet');
const rateLimit  = require('express-rate-limit');
const multer     = require('multer');
const fs         = require('fs-extra');
const path       = require('path');
const { v4: uuidv4 } = require('uuid');
const morgan     = require('morgan');

// ── Config ──────────────────────────────────────────────────────
const PORT_HTTP = process.env.PORT_HTTP || 4000;
const PORT_WS   = process.env.PORT_WS   || 4001;
const VOANH_DIR = process.env.VOANH_DIR || '/opt/voanh';
const CHATS_DIR = path.join(VOANH_DIR, 'chats');
const UPLOADS_DIR = path.join(VOANH_DIR, 'uploads');
const WORK_DIR  = path.join(VOANH_DIR, 'workspaces');
const TOKEN     = process.env.VOANH_TOKEN || 'changeme-voanh-secret';

fs.ensureDirSync(CHATS_DIR);
fs.ensureDirSync(UPLOADS_DIR);
fs.ensureDirSync(WORK_DIR);

// ── Express App ─────────────────────────────────────────────────
const app = express();
app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors({ origin: '*', methods: ['GET','POST','DELETE','PUT','PATCH'] }));
app.use(express.json({ limit: '50mb' }));
app.use(morgan('combined', { stream: { write: m => process.stdout.write(m) } }));

const limiter = rateLimit({ windowMs: 60_000, max: 200 });
app.use(limiter);

// ── Auth Middleware ──────────────────────────────────────────────
function auth(req, res, next) {
  const t = req.headers['x-voanh-token'] || req.query.token;
  if (t !== TOKEN) return res.status(401).json({ error: 'Unauthorized' });
  next();
}

// ── Multer Upload ────────────────────────────────────────────────
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(UPLOADS_DIR, req.params.workspace || 'default');
    fs.ensureDirSync(dir);
    cb(null, dir);
  },
  filename: (req, file, cb) => cb(null, `${Date.now()}_${file.originalname}`)
});
const upload = multer({ storage, limits: { fileSize: 100 * 1024 * 1024 } });

// ══════════════════════════════════════════════════════════════════
// ROUTES — HEALTH
// ══════════════════════════════════════════════════════════════════
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', version: '1.0.0', time: new Date().toISOString() });
});

// ══════════════════════════════════════════════════════════════════
// ROUTES — CHATS (historique serveur)
// ══════════════════════════════════════════════════════════════════
// Lister tous les chats
app.get('/api/chats', auth, async (req, res) => {
  try {
    const files = await fs.readdir(CHATS_DIR);
    const chats = [];
    for (const f of files.filter(f => f.endsWith('.json'))) {
      try {
        const data = await fs.readJson(path.join(CHATS_DIR, f));
        chats.push({ id: data.id, title: data.title, updated: data.updated, msgCount: (data.messages||[]).length });
      } catch {}
    }
    chats.sort((a,b) => (b.updated||0)-(a.updated||0));
    res.json(chats);
  } catch(e) { res.status(500).json({ error: e.message }); }
});

// Lire un chat
app.get('/api/chats/:id', auth, async (req, res) => {
  try {
    const file = path.join(CHATS_DIR, `${req.params.id}.json`);
    if (!await fs.pathExists(file)) return res.status(404).json({ error: 'Not found' });
    res.json(await fs.readJson(file));
  } catch(e) { res.status(500).json({ error: e.message }); }
});

// Sauvegarder/mettre à jour un chat
app.post('/api/chats', auth, async (req, res) => {
  try {
    const chat = req.body;
    if (!chat.id) chat.id = uuidv4();
    chat.updated = Date.now();
    await fs.writeJson(path.join(CHATS_DIR, `${chat.id}.json`), chat, { spaces: 2 });
    res.json({ ok: true, id: chat.id });
  } catch(e) { res.status(500).json({ error: e.message }); }
});

// Supprimer un chat
app.delete('/api/chats/:id', auth, async (req, res) => {
  try {
    const file = path.join(CHATS_DIR, `${req.params.id}.json`);
    await fs.remove(file);
    res.json({ ok: true });
  } catch(e) { res.status(500).json({ error: e.message }); }
});

// Supprimer tous les chats
app.delete('/api/chats', auth, async (req, res) => {
  try {
    await fs.emptyDir(CHATS_DIR);
    res.json({ ok: true });
  } catch(e) { res.status(500).json({ error: e.message }); }
});

// ══════════════════════════════════════════════════════════════════
// ROUTES — FILESYSTEM
// ══════════════════════════════════════════════════════════════════
function safePath(base, rel) {
  const resolved = path.resolve(base, rel || '');
  if (!resolved.startsWith(base)) throw new Error('Path traversal detected');
  return resolved;
}

// Lister un répertoire (limité aux workspaces sauf admin)
app.get('/api/fs/list', auth, async (req, res) => {
  try {
    const rel  = req.query.path || '';
    const base = req.query.root === 'system' ? '/' : WORK_DIR;
    const full = base === '/' ? path.resolve('/' + rel) : safePath(base, rel);
    const entries = await fs.readdir(full, { withFileTypes: true });
    const result = await Promise.all(entries.map(async e => {
      const ep = path.join(full, e.name);
      const stat = await fs.stat(ep).catch(() => null);
      return {
        name: e.name,
        type: e.isDirectory() ? 'dir' : 'file',
        size: stat?.size || 0,
        modified: stat?.mtime?.getTime() || 0
      };
    }));
    res.json({ path: full, entries: result.sort((a,b) => a.type===b.type?a.name.localeCompare(b.name):a.type==='dir'?-1:1) });
  } catch(e) { res.status(500).json({ error: e.message }); }
});

// Lire un fichier
app.get('/api/fs/read', auth, async (req, res) => {
  try {
    const full = req.query.root === 'system' ? path.resolve('/' + (req.query.path||'')) : safePath(WORK_DIR, req.query.path||'');
    const stat = await fs.stat(full);
    if (stat.size > 5 * 1024 * 1024) return res.status(413).json({ error: 'File too large (>5MB)' });
    const content = await fs.readFile(full, 'utf8');
    res.json({ path: full, content });
  } catch(e) { res.status(500).json({ error: e.message }); }
});

// Écrire un fichier
app.post('/api/fs/write', auth, async (req, res) => {
  try {
    const { path: relPath, content, root } = req.body;
    const full = root === 'system' ? path.resolve('/' + relPath) : safePath(WORK_DIR, relPath);
    await fs.ensureDir(path.dirname(full));
    await fs.writeFile(full, content, 'utf8');
    res.json({ ok: true, path: full });
  } catch(e) { res.status(500).json({ error: e.message }); }
});

// Créer un dossier
app.post('/api/fs/mkdir', auth, async (req, res) => {
  try {
    const { path: relPath, root } = req.body;
    const full = root === 'system' ? path.resolve('/' + relPath) : safePath(WORK_DIR, relPath);
    await fs.ensureDir(full);
    res.json({ ok: true, path: full });
  } catch(e) { res.status(500).json({ error: e.message }); }
});

// Supprimer un fichier/dossier
app.delete('/api/fs/delete', auth, async (req, res) => {
  try {
    const relPath = req.body.path || req.query.path;
    const root    = req.body.root || req.query.root;
    const full = root === 'system' ? path.resolve('/' + relPath) : safePath(WORK_DIR, relPath);
    await fs.remove(full);
    res.json({ ok: true });
  } catch(e) { res.status(500).json({ error: e.message }); }
});

// Upload fichier vers workspace
app.post('/api/fs/upload/:workspace', auth, upload.array('files'), (req, res) => {
  res.json({ ok: true, files: req.files.map(f => ({ name: f.filename, size: f.size })) });
});

// ══════════════════════════════════════════════════════════════════
// ROUTES — PACKAGES
// ══════════════════════════════════════════════════════════════════
const { exec } = require('child_process');
function execCmd(cmd) {
  return new Promise((resolve, reject) => {
    exec(cmd, { timeout: 300_000, maxBuffer: 10 * 1024 * 1024 }, (err, stdout, stderr) => {
      if (err) reject(new Error(stderr || err.message));
      else resolve(stdout);
    });
  });
}

app.post('/api/packages/npm', auth, async (req, res) => {
  try {
    const { packages, workspace, dev } = req.body;
    const cwd = path.join(WORK_DIR, workspace || 'default');
    await fs.ensureDir(cwd);
    const flag = dev ? '--save-dev' : '--save';
    const out = await execCmd(`cd "${cwd}" && npm install ${flag} ${packages.join(' ')} 2>&1`);
    res.json({ ok: true, output: out });
  } catch(e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/packages/pip', auth, async (req, res) => {
  try {
    const { packages, workspace } = req.body;
    const out = await execCmd(`pip3 install ${packages.join(' ')} 2>&1`);
    res.json({ ok: true, output: out });
  } catch(e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/packages/apt', auth, async (req, res) => {
  try {
    const { packages } = req.body;
    const out = await execCmd(`apt-get install -y ${packages.join(' ')} 2>&1`);
    res.json({ ok: true, output: out });
  } catch(e) { res.status(500).json({ error: e.message }); }
});

// ══════════════════════════════════════════════════════════════════
// ROUTES — SYSTEM INFO
// ══════════════════════════════════════════════════════════════════
app.get('/api/system/info', auth, async (req, res) => {
  try {
    const [uptime, mem, disk, cpu] = await Promise.all([
      execCmd('uptime -p').catch(()=>''),
      execCmd("free -m | awk 'NR==2{printf \"%s/%s\", $3, $2}'").catch(()=>''),
      execCmd("df -h / | awk 'NR==2{printf \"%s/%s (%s)\", $3, $2, $5}'").catch(()=>''),
      execCmd("top -bn1 | grep 'Cpu(s)' | awk '{print $2+$4}'").catch(()=>'')
    ]);
    res.json({ uptime: uptime.trim(), memory: mem.trim(), disk: disk.trim(), cpu: cpu.trim() + '%' });
  } catch(e) { res.status(500).json({ error: e.message }); }
});

// ── HTTP Server ──────────────────────────────────────────────────
const httpServer = http.createServer(app);
httpServer.listen(PORT_HTTP, () => console.log(`[VOANH] API backend listening on :${PORT_HTTP}`));

// ══════════════════════════════════════════════════════════════════
// WEBSOCKET — TERMINAL PTY
// ══════════════════════════════════════════════════════════════════
const wss = new WebSocket.Server({ port: PORT_WS });

wss.on('connection', (ws, req) => {
  // Token auth via URL query
  const urlParams = new URLSearchParams(req.url.split('?')[1] || '');
  if (urlParams.get('token') !== TOKEN) {
    ws.send(JSON.stringify({ type: 'error', data: 'Unauthorized' }));
    ws.close();
    return;
  }

  const shell = process.env.SHELL || '/bin/bash';
  const cwd   = urlParams.get('cwd') || WORK_DIR;

  const ptyProc = pty.spawn(shell, [], {
    name: 'xterm-256color',
    cols: parseInt(urlParams.get('cols') || '120'),
    rows: parseInt(urlParams.get('rows') || '40'),
    cwd: fs.existsSync(cwd) ? cwd : WORK_DIR,
    env: { ...process.env, TERM: 'xterm-256color', COLORTERM: 'truecolor', HOME: process.env.HOME || '/root' }
  });

  console.log(`[VOANH] Terminal PTY spawned PID=${ptyProc.pid}`);

  ptyProc.onData(data => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'output', data }));
    }
  });

  ptyProc.onExit(({ exitCode }) => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'exit', code: exitCode }));
    }
  });

  ws.on('message', raw => {
    try {
      const msg = JSON.parse(raw);
      if (msg.type === 'input')   ptyProc.write(msg.data);
      if (msg.type === 'resize')  ptyProc.resize(msg.cols, msg.rows);
      if (msg.type === 'ping')    ws.send(JSON.stringify({ type: 'pong' }));
    } catch {}
  });

  ws.on('close', () => {
    try { ptyProc.kill(); } catch {}
    console.log(`[VOANH] Terminal closed PID=${ptyProc.pid}`);
  });
});

console.log(`[VOANH] Terminal WebSocket listening on :${PORT_WS}`);
SERVERJS

  # Installer les dépendances Node
  log "Installation des dépendances Node.js..."
  cd "$VOANH_DIR"
  npm install --quiet > /dev/null 2>&1
  success "Dépendances Node.js installées"

  # ── Systemd service — Backend ────────────────────────────────────
  log "Création du service systemd voanh-backend..."
  cat > "/etc/systemd/system/${SERVICE_BACKEND}.service" << SVCBK
[Unit]
Description=VOANH AI Backend (API + WS Terminal)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${VOANH_DIR}
ExecStart=/usr/bin/node ${VOANH_DIR}/server.js
Restart=always
RestartSec=5
Environment=NODE_ENV=production
Environment=PORT_HTTP=${NODE_PORT}
Environment=PORT_WS=${WS_PORT}
Environment=VOANH_DIR=${VOANH_DIR}
Environment=VOANH_TOKEN=changeme-voanh-secret
StandardOutput=append:${LOG_DIR}/backend.log
StandardError=append:${LOG_DIR}/backend-error.log

[Install]
WantedBy=multi-user.target
SVCBK

  # ── Watchdog service (keepalive) ─────────────────────────────────
  cat > "/etc/systemd/system/voanh-watchdog.service" << SVCWD
[Unit]
Description=VOANH AI Watchdog — Keepalive
After=${SERVICE_BACKEND}.service

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do systemctl is-active --quiet ${SERVICE_BACKEND} || systemctl start ${SERVICE_BACKEND}; sleep 30; done'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SVCWD

  # ── Timer logrotate ──────────────────────────────────────────────
  cat > "/etc/systemd/system/voanh-logrotate.service" << SVCLR
[Unit]
Description=VOANH AI Log Rotation

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'find ${LOG_DIR} -name "*.log" -size +50M -exec truncate -s 0 {} \;'
SVCLR

  cat > "/etc/systemd/system/voanh-logrotate.timer" << SVCLRT
[Unit]
Description=VOANH AI Log Rotation — Timer

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
SVCLRT

  # ── Nginx config ─────────────────────────────────────────────────
  log "Configuration Nginx..."
  cat > "$NGINX_CONF" << 'NGINXCFG'
server {
    listen 80;
    server_name _;

    # Interface HTML VOANH
    root /opt/voanh/public;
    index index.html;

    # CORS global
    add_header 'Access-Control-Allow-Origin' '*' always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, DELETE, PUT, PATCH, OPTIONS' always;
    add_header 'Access-Control-Allow-Headers' 'Content-Type, Authorization, X-VOANH-Token' always;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # Proxy API REST
    location /api/ {
        proxy_pass http://127.0.0.1:4000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Connection "";
        proxy_read_timeout 300;
        client_max_body_size 100M;
    }

    # Proxy WebSocket Terminal
    location /ws/ {
        proxy_pass http://127.0.0.1:4001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }
}
NGINXCFG

  ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/voanh 2>/dev/null || true
  rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
  nginx -t > /dev/null 2>&1 && success "Nginx configuré" || warn "Vérifiez la config nginx manuellement"

  # ── Copier l'interface HTML ──────────────────────────────────────
  if [[ -f "$SCRIPT_DIR/index.html" ]]; then
    cp "$SCRIPT_DIR/index.html" "$VOANH_DIR/public/index.html"
    success "Interface HTML copiée dans $VOANH_DIR/public/"
  else
    warn "index.html non trouvé dans $SCRIPT_DIR — copiez-le manuellement dans $VOANH_DIR/public/"
  fi

  # ── UFW Firewall ─────────────────────────────────────────────────
  log "Configuration du pare-feu..."
  ufw allow ssh      > /dev/null 2>&1 || true
  ufw allow 80/tcp   > /dev/null 2>&1 || true
  ufw allow 443/tcp  > /dev/null 2>&1 || true
  ufw allow "${NODE_PORT}/tcp" > /dev/null 2>&1 || true
  ufw allow "${WS_PORT}/tcp"   > /dev/null 2>&1 || true
  ufw --force enable > /dev/null 2>&1 || true
  success "Pare-feu configuré"

  # ── Activer & démarrer les services ─────────────────────────────
  log "Activation et démarrage des services..."
  systemctl daemon-reload
  systemctl enable --quiet "$SERVICE_BACKEND" voanh-watchdog voanh-logrotate.timer
  systemctl start "$SERVICE_BACKEND" voanh-watchdog voanh-logrotate.timer
  systemctl enable --quiet nginx && systemctl restart nginx
  success "Tous les services démarrés"

  sep
  echo -e "\n${GREEN}${BOLD}  ╔═══════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}${BOLD}  ║   VOANH AI — INSTALLATION TERMINÉE ! ✓   ║${NC}"
  echo -e "${GREEN}${BOLD}  ╚═══════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${CYAN}Interface Web:${NC}  http://$(hostname -I | awk '{print $1}')"
  echo -e "  ${CYAN}API Backend:${NC}    http://localhost:${NODE_PORT}/api/health"
  echo -e "  ${CYAN}WS Terminal:${NC}    ws://localhost:${WS_PORT}"
  echo ""
  echo -e "  ${YELLOW}IMPORTANT:${NC} Modifiez le token secret dans"
  echo -e "  /etc/systemd/system/${SERVICE_BACKEND}.service"
  echo -e "  Variable: ${BOLD}VOANH_TOKEN=changeme-voanh-secret${NC}"
  echo ""
  echo -e "  ${DIM}Puis: systemctl daemon-reload && systemctl restart ${SERVICE_BACKEND}${NC}"
  sep
}

# ═══════════════════════════════════════════════════════════════════
# OPTION 2 — DÉSINSTALLATION COMPLÈTE
# ═══════════════════════════════════════════════════════════════════
uninstall_all() {
  require_root
  echo ""
  echo -e "${RED}${BOLD}  ╔═══════════════════════════════════════════════╗${NC}"
  echo -e "${RED}${BOLD}  ║  ⚠  DÉSINSTALLATION COMPLÈTE VOANH AI  ⚠   ║${NC}"
  echo -e "${RED}${BOLD}  ╚═══════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${RED}Cette action va :${NC}"
  echo -e "  ${DIM}• Arrêter tous les services VOANH${NC}"
  echo -e "  ${DIM}• Supprimer les fichiers dans $VOANH_DIR${NC}"
  echo -e "  ${DIM}• Supprimer les services systemd${NC}"
  echo -e "  ${DIM}• Supprimer la config Nginx${NC}"
  echo ""
  read -rp "  Tapez 'SUPPRIMER' pour confirmer : " confirm
  [[ "$confirm" != "SUPPRIMER" ]] && { warn "Annulé."; return; }

  # Arrêter et désactiver les services
  log "Arrêt de tous les services VOANH..."
  for svc in "$SERVICE_BACKEND" voanh-watchdog voanh-logrotate.timer; do
    systemctl stop  "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
  done
  success "Services arrêtés"

  # Supprimer les fichiers systemd
  log "Suppression des services systemd..."
  rm -f "/etc/systemd/system/${SERVICE_BACKEND}.service"
  rm -f "/etc/systemd/system/voanh-watchdog.service"
  rm -f "/etc/systemd/system/voanh-logrotate.service"
  rm -f "/etc/systemd/system/voanh-logrotate.timer"
  systemctl daemon-reload
  success "Services systemd supprimés"

  # Supprimer la config Nginx
  log "Suppression de la config Nginx..."
  rm -f "$NGINX_CONF"
  rm -f /etc/nginx/sites-enabled/voanh
  systemctl reload nginx 2>/dev/null || true
  success "Config Nginx supprimée"

  # Sauvegarder les chats avant suppression
  if [[ -d "$CHATS_DIR" ]] && [[ $(ls -A "$CHATS_DIR" 2>/dev/null) ]]; then
    log "Sauvegarde des chats dans /tmp/voanh-chats-backup.tar.gz..."
    tar -czf "/tmp/voanh-chats-backup.tar.gz" -C "$VOANH_DIR" chats/
    success "Chats sauvegardés dans /tmp/voanh-chats-backup.tar.gz"
  fi

  # Supprimer le répertoire VOANH
  log "Suppression de $VOANH_DIR..."
  rm -rf "$VOANH_DIR"
  success "$VOANH_DIR supprimé"

  sep
  echo -e "${GREEN}  VOANH AI désinstallé avec succès.${NC}"
  echo -e "  ${DIM}Vos chats ont été sauvegardés dans /tmp/voanh-chats-backup.tar.gz${NC}"
  sep
}

# ═══════════════════════════════════════════════════════════════════
# FONCTIONS UTILITAIRES
# ═══════════════════════════════════════════════════════════════════
restart_services() {
  require_root
  log "Redémarrage des services VOANH..."
  systemctl restart "$SERVICE_BACKEND" voanh-watchdog
  systemctl reload nginx 2>/dev/null || true
  success "Services redémarrés"
}

view_logs() {
  echo -e "\n${CYAN}Choix des logs :${NC}"
  echo "  1) Backend (temps réel)"
  echo "  2) Backend erreurs"
  echo "  3) Nginx access"
  echo "  4) Nginx error"
  read -rp "  Votre choix : " lchoice
  case $lchoice in
    1) journalctl -u "$SERVICE_BACKEND" -f --no-pager ;;
    2) tail -f "$LOG_DIR/backend-error.log" 2>/dev/null || journalctl -u "$SERVICE_BACKEND" -f --no-pager ;;
    3) tail -f /var/log/nginx/access.log ;;
    4) tail -f /var/log/nginx/error.log ;;
    *) warn "Choix invalide" ;;
  esac
}

update_token() {
  require_root
  echo -e "\n${CYAN}Mise à jour du token VOANH_TOKEN${NC}"
  read -rsp "  Nouveau token (invisible) : " new_token
  echo ""
  [[ ${#new_token} -lt 12 ]] && { warn "Token trop court (minimum 12 caractères)"; return; }
  sed -i "s/VOANH_TOKEN=.*/VOANH_TOKEN=${new_token}/" "/etc/systemd/system/${SERVICE_BACKEND}.service"
  systemctl daemon-reload
  systemctl restart "$SERVICE_BACKEND"
  success "Token mis à jour et service redémarré"
}

backup_chats() {
  require_root
  local bk="/tmp/voanh-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -czf "$bk" -C "$VOANH_DIR" chats/ workspaces/ 2>/dev/null || true
  success "Sauvegarde créée : $bk"
}

# ═══════════════════════════════════════════════════════════════════
# MENU PRINCIPAL
# ═══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    show_status
    echo ""
    echo -e "  ${BOLD}MENU PRINCIPAL${NC}"
    sep
    echo -e "  ${GREEN}1)${NC} Installation complète VOANH AI"
    echo -e "  ${RED}2)${NC} Désinstallation complète (arrêt de tout)"
    echo -e "  ${YELLOW}3)${NC} Quitter"
    sep
    echo -e "  ${DIM}──── OPTIONS AVANCÉES ────${NC}"
    echo -e "  ${CYAN}r)${NC} Redémarrer les services"
    echo -e "  ${CYAN}l)${NC} Voir les logs"
    echo -e "  ${CYAN}t)${NC} Mettre à jour le token secret"
    echo -e "  ${CYAN}b)${NC} Sauvegarder chats + workspaces"
    sep
    echo ""
    read -rp "  Votre choix : " choice
    echo ""
    case $choice in
      1) install_all ;;
      2) uninstall_all ;;
      3) echo -e "${CYAN}Au revoir !${NC}"; exit 0 ;;
      r|R) restart_services ;;
      l|L) view_logs ;;
      t|T) update_token ;;
      b|B) backup_chats ;;
      *) warn "Choix invalide" ;;
    esac
    echo ""
    read -rp "  Appuyez sur Entrée pour continuer..."
  done
}

# ── Entrypoint ────────────────────────────────────────────────────
if [[ "${1:-}" == "--install" ]]; then
  require_root; install_all
elif [[ "${1:-}" == "--uninstall" ]]; then
  require_root; uninstall_all
elif [[ "${1:-}" == "--status" ]]; then
  show_status
else
  main_menu
fi
