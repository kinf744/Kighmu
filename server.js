// ============================================================
// KIGHMU PANEL v2 - Backend complet
// ============================================================
'use strict';

// ── Chargement .env AVANT tout ──────────────────────────────
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const express   = require('express');
const mysql     = require('mysql2/promise');
const bcrypt    = require('bcryptjs');
const jwt       = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const helmet    = require('helmet');
const cors      = require('cors');
const rateLimit = require('express-rate-limit');
const cron      = require('node-cron');
const si        = require('systeminformation');
const fs        = require('fs');
const { exec }  = require('child_process');

// ── Vérification des variables obligatoires ─────────────────
const REQUIRED_ENV = ['DB_USER', 'DB_PASSWORD', 'DB_NAME', 'JWT_SECRET'];
const missing = REQUIRED_ENV.filter(k => !process.env[k]);
if (missing.length) {
  console.error(`[FATAL] Variables .env manquantes : ${missing.join(', ')}`);
  console.error(`[FATAL] Vérifiez le fichier : ${path.join(__dirname, '.env')}`);
  process.exit(1);
}

const app = express();

// ── Pool MySQL ───────────────────────────────────────────────
let db;
async function initDB() {
  try {
    db = mysql.createPool({
      host:               process.env.DB_HOST     || '127.0.0.1',
      port:           parseInt(process.env.DB_PORT || '3306'),
      database:           process.env.DB_NAME,
      user:               process.env.DB_USER,
      password:           process.env.DB_PASSWORD,
      waitForConnections: true,
      connectionLimit:    20,
      queueLimit:         0,
      enableKeepAlive:    true,
      keepAliveInitialDelay: 0,
      connectTimeout:     10000,
    });
    // Test de connexion immédiat
    const conn = await db.getConnection();
    await conn.ping();
    conn.release();
    console.log(`[DB] Connexion MySQL OK → ${process.env.DB_NAME}@${process.env.DB_HOST || '127.0.0.1'}`);
    return true;
  } catch (e) {
    console.error(`[DB] ERREUR connexion MySQL : ${e.message}`);
    console.error(`[DB] Host: ${process.env.DB_HOST || '127.0.0.1'}, User: ${process.env.DB_USER}, DB: ${process.env.DB_NAME}`);
    return false;
  }
}

// ── Middleware global ────────────────────────────────────────
app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors({ origin: '*', credentials: true }));
app.use(express.json({ limit: '10kb' }));
app.set('trust proxy', 1);
app.use(rateLimit({ windowMs: 15 * 60 * 1000, max: 500, standardHeaders: true, legacyHeaders: false }));

// ── Health check — AVANT express.static pour ne pas être masqué ──
app.get('/health', (req, res) => {
  res.json({
    status: db ? 'ok' : 'db_error',
    panel: 'kighmu-v2',
    uptime: Math.floor(process.uptime()) + 's',
    node: process.version,
    db: db ? 'connected' : 'disconnected',
    time: new Date().toISOString()
  });
});

// ── Middleware DB check — AVANT les routes /api ──────────────
app.use('/api', (req, res, next) => {
  if (!db) return res.status(503).json({ error: 'Base de données non connectée. Vérifiez MySQL.' });
  next();
});

// ── Fichiers statiques — APRÈS /health et /api ───────────────
const FRONTEND = path.join(__dirname, 'frontend');
if (fs.existsSync(FRONTEND)) {
  app.use(express.static(FRONTEND));
  console.log(`[STATIC] Dossier frontend : ${FRONTEND}`);
} else {
  console.error(`[STATIC] ERREUR : dossier frontend introuvable → ${FRONTEND}`);
}

// ============================================================
// PROTECTION BRUTE-FORCE
// ============================================================
const MAX_ATT   = parseInt(process.env.MAX_LOGIN_ATTEMPTS   || '5');
const BLOCK_MIN = parseInt(process.env.BLOCK_DURATION_MINUTES || '30');

async function checkBruteForce(ip) {
  try {
    const [rows] = await db.query('SELECT * FROM login_attempts WHERE ip_address = ?', [ip]);
    if (!rows.length) return null;
    const r = rows[0];
    if (r.blocked_until && new Date(r.blocked_until) > new Date()) {
      const mins = Math.ceil((new Date(r.blocked_until) - new Date()) / 60000);
      return `IP bloquée. Réessayez dans ${mins} min.`;
    }
    if (r.attempts >= MAX_ATT) {
      const until = new Date(Date.now() + BLOCK_MIN * 60000);
      await db.query('UPDATE login_attempts SET blocked_until=?, last_attempt=NOW() WHERE ip_address=?', [until, ip]);
      return `Trop de tentatives. IP bloquée ${BLOCK_MIN} minutes.`;
    }
    return null;
  } catch { return null; }
}
async function failAttempt(ip) {
  try {
    const [r] = await db.query('SELECT id FROM login_attempts WHERE ip_address=?', [ip]);
    if (r.length) await db.query('UPDATE login_attempts SET attempts=attempts+1, last_attempt=NOW() WHERE ip_address=?', [ip]);
    else await db.query('INSERT INTO login_attempts (ip_address) VALUES (?)', [ip]);
  } catch {}
}
async function clearAttempts(ip) {
  try { await db.query('DELETE FROM login_attempts WHERE ip_address=?', [ip]); } catch {}
}

// ============================================================
// JWT MIDDLEWARE
// ============================================================
function auth(roles = []) {
  return async (req, res, next) => {
    try {
      const header = req.headers.authorization || '';
      const token  = header.startsWith('Bearer ') ? header.slice(7) : null;
      if (!token) return res.status(401).json({ error: 'Token manquant' });
      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      if (roles.length && !roles.includes(decoded.role))
        return res.status(403).json({ error: 'Accès refusé' });
      if (decoded.role === 'reseller') {
        const [[r]] = await db.query('SELECT is_active, expires_at FROM resellers WHERE id=?', [decoded.id]);
        if (!r || !r.is_active) return res.status(401).json({ error: 'Compte désactivé' });
        if (new Date(r.expires_at) < new Date()) {
          await db.query('UPDATE resellers SET is_active=0 WHERE id=?', [decoded.id]);
          return res.status(401).json({ error: 'Compte expiré' });
        }
      }
      req.user = decoded;
      next();
    } catch (e) {
      return res.status(401).json({ error: 'Token invalide ou expiré' });
    }
  };
}

// ============================================================
// LOGGER
// ============================================================
async function log(actorType, actorId, action, targetType, targetId, details, ip) {
  try {
    await db.query(
      'INSERT INTO activity_logs (actor_type,actor_id,action,target_type,target_id,details,ip_address) VALUES (?,?,?,?,?,?,?)',
      [actorType, actorId, action, targetType||null, targetId||null, details ? JSON.stringify(details) : null, ip||null]
    );
  } catch {}
}

// ============================================================
// TUNNEL MANAGER
// ============================================================
const execAsync = (cmd) => new Promise((res, rej) =>
  exec(cmd, { timeout: 10000 }, (e, out, err) => e ? rej(new Error(err || e.message)) : res(out))
);
const readJson  = (p) => { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; } };
const writeJson = (p, d) => { try { fs.writeFileSync(p, JSON.stringify(d, null, 2)); } catch(e) { console.error(`[TUNNEL] writeJson(${p}):`, e.message); } };

async function restartService(svc) {
  try { await execAsync(`systemctl restart ${svc}`); return true; }
  catch (e) { console.error(`[TUNNEL] restart ${svc}:`, e.message); return false; }
}

function xrayAdd(username, protocol, uuid) {
  const cfgPath = process.env.XRAY_CONFIG || '/etc/xray/config.json';
  const cfg = readJson(cfgPath);
  if (!cfg) return { ok: false, msg: `config xray introuvable : ${cfgPath}` };
  const inb = cfg.inbounds?.find(i => i.protocol === protocol.toLowerCase());
  if (!inb) return { ok: false, msg: `inbound ${protocol} introuvable dans xray config` };
  if (!inb.settings) inb.settings = {};
  if (!inb.settings.clients) inb.settings.clients = [];
  const client = protocol === 'trojan'
    ? { password: username, level: 0, email: username }
    : { id: uuid, level: 0, email: username };
  inb.settings.clients.push(client);
  writeJson(cfgPath, cfg);
  return { ok: true };
}

function xrayRemove(username, protocol, uuid) {
  const cfgPath = process.env.XRAY_CONFIG || '/etc/xray/config.json';
  const cfg = readJson(cfgPath);
  if (!cfg) return;
  const inb = cfg.inbounds?.find(i => i.protocol === protocol.toLowerCase());
  if (!inb?.settings?.clients) return;
  inb.settings.clients = inb.settings.clients.filter(
    c => c.id !== uuid && c.email !== username && c.password !== username
  );
  writeJson(cfgPath, cfg);
}

async function sshAdd(username, password, expiryDate) {
  try {
    const exp = new Date(expiryDate).toISOString().split('T')[0];
    await execAsync(`useradd -M -s /bin/false -e ${exp} ${username} 2>/dev/null || true`);
    await execAsync(`echo "${username}:${password}" | chpasswd`);
    return { ok: true };
  } catch (e) { return { ok: false, msg: e.message }; }
}
async function sshRemove(username) {
  try { await execAsync(`userdel -r ${username} 2>/dev/null || true`); } catch {}
}

function zivpnAdd(username, password, expiresAt) {
  try {
    const userFile = '/etc/zivpn/users.list';
    const cfgFile  = '/etc/zivpn/config.json';
    if (!fs.existsSync('/etc/zivpn')) return { ok: false, msg: 'ZIVPN non installé (/etc/zivpn manquant)' };

    const expire = expiresAt ? new Date(expiresAt).toISOString().split('T')[0] : '2099-12-31';

    // Lire fichier existant, supprimer doublon username, ajouter nouvelle ligne
    let lines = [];
    if (fs.existsSync(userFile)) {
      lines = fs.readFileSync(userFile, 'utf8').split('\n').filter(l => l.trim() && !l.startsWith(`${username}|`));
    }
    lines.push(`${username}|${password}|${expire}`);
    fs.writeFileSync(userFile, lines.join('\n') + '\n');
    fs.chmodSync(userFile, 0o600);

    // Mettre à jour config.json : auth.config = tableau des passwords actifs
    _zivpnSyncConfig(userFile, cfgFile);
    return { ok: true };
  } catch (e) { return { ok: false, msg: e.message }; }
}

function zivpnRemove(username) {
  try {
    const userFile = '/etc/zivpn/users.list';
    const cfgFile  = '/etc/zivpn/config.json';
    if (!fs.existsSync(userFile)) return;
    const lines = fs.readFileSync(userFile, 'utf8').split('\n').filter(l => l.trim() && !l.startsWith(`${username}|`));
    fs.writeFileSync(userFile, lines.join('\n') + '\n');
    _zivpnSyncConfig(userFile, cfgFile);
  } catch {}
}

function _zivpnSyncConfig(userFile, cfgFile) {
  try {
    if (!fs.existsSync(cfgFile)) return;
    const today = new Date().toISOString().split('T')[0];
    const passwords = fs.readFileSync(userFile, 'utf8').split('\n')
      .filter(l => l.trim())
      .map(l => l.split('|'))
      .filter(p => p.length >= 3 && p[2] >= today)
      .map(p => p[1])
      .filter((v, i, a) => a.indexOf(v) === i); // unique

    const cfg = JSON.parse(fs.readFileSync(cfgFile, 'utf8'));
    if (!cfg.auth) cfg.auth = { mode: 'passwords', config: [] };
    cfg.auth.config = passwords.length > 0 ? passwords : ['zi'];
    fs.writeFileSync(cfgFile, JSON.stringify(cfg, null, 2));
  } catch (e) { console.error('[ZIVPN] sync config error:', e.message); }
}

function hysteriaAdd(username, password, expiresAt) {
  try {
    const userFile = '/etc/hysteria/users.txt';
    const cfgFile  = '/etc/hysteria/config.json';
    if (!fs.existsSync('/etc/hysteria')) return { ok: false, msg: 'Hysteria non installé (/etc/hysteria manquant)' };

    const expire = expiresAt ? new Date(expiresAt).toISOString().split('T')[0] : '2099-12-31';

    // Lire fichier existant, supprimer doublon username, ajouter nouvelle ligne
    let lines = [];
    if (fs.existsSync(userFile)) {
      lines = fs.readFileSync(userFile, 'utf8').split('\n').filter(l => l.trim() && !l.startsWith(`${username}|`));
    }
    lines.push(`${username}|${password}|${expire}`);
    fs.writeFileSync(userFile, lines.join('\n') + '\n');
    fs.chmodSync(userFile, 0o600);

    // Mettre à jour config.json : auth.config = tableau des passwords actifs
    _hysteriaSyncConfig(userFile, cfgFile);
    return { ok: true };
  } catch (e) { return { ok: false, msg: e.message }; }
}

function hysteriaRemove(username) {
  try {
    const userFile = '/etc/hysteria/users.txt';
    const cfgFile  = '/etc/hysteria/config.json';
    if (!fs.existsSync(userFile)) return;
    const lines = fs.readFileSync(userFile, 'utf8').split('\n').filter(l => l.trim() && !l.startsWith(`${username}|`));
    fs.writeFileSync(userFile, lines.join('\n') + '\n');
    _hysteriaSyncConfig(userFile, cfgFile);
  } catch {}
}

function _hysteriaSyncConfig(userFile, cfgFile) {
  try {
    if (!fs.existsSync(cfgFile)) return;
    const today = new Date().toISOString().split('T')[0];
    const passwords = fs.readFileSync(userFile, 'utf8').split('\n')
      .filter(l => l.trim())
      .map(l => l.split('|'))
      .filter(p => p.length >= 3 && p[2] >= today)
      .map(p => p[1])
      .filter((v, i, a) => a.indexOf(v) === i); // unique

    const cfg = JSON.parse(fs.readFileSync(cfgFile, 'utf8'));
    if (!cfg.auth) cfg.auth = { mode: 'passwords', config: [] };
    cfg.auth.config = passwords.length > 0 ? passwords : ['zi'];
    fs.writeFileSync(cfgFile, JSON.stringify(cfg, null, 2));
  } catch (e) { console.error('[HYSTERIA] sync config error:', e.message); }
}

function v2rayAdd(username, uuid) {
  // V2Ray FastDNS utilise VLESS TCP sur port 5401 (pas vmess)
  const cfgPath = process.env.V2RAY_CONFIG || '/etc/v2ray/config.json';
  const cfg = readJson(cfgPath);
  if (!cfg) return { ok: false, msg: `config v2ray introuvable : ${cfgPath}` };

  // Chercher inbound vless en priorité, sinon premier inbound
  const inb = cfg.inbounds?.find(i => i.protocol === 'vless') || cfg.inbounds?.[0];
  if (!inb?.settings?.clients) return { ok: false, msg: 'inbound vless introuvable dans config v2ray' };

  // Vérifier doublon UUID
  if (inb.settings.clients.some(c => c.id === uuid)) {
    return { ok: true }; // déjà présent
  }

  // VLESS : pas de alterId
  const client = { id: uuid, email: username };
  if (inb.protocol === 'vmess') client.alterId = 0; // compatibilité vmess si besoin
  inb.settings.clients.push(client);
  writeJson(cfgPath, cfg);
  return { ok: true };
}
function v2rayRemove(username, uuid) {
  const cfgPath = process.env.V2RAY_CONFIG || '/etc/v2ray/config.json';
  const cfg = readJson(cfgPath);
  if (!cfg) return;
  const inb = cfg.inbounds?.[0];
  if (!inb?.settings?.clients) return;
  inb.settings.clients = inb.settings.clients.filter(c => c.id !== uuid && c.email !== username);
  writeJson(cfgPath, cfg);
}

async function addTunnel(client) {
  const { username, password, uuid, tunnel_type, expires_at } = client;
  let result = { ok: false, msg: 'tunnel_type inconnu' };
  try {
    switch (tunnel_type) {
      case 'vless':          result = xrayAdd(username, 'vless', uuid);  if (result.ok) await restartService('xray');     break;
      case 'vmess':          result = xrayAdd(username, 'vmess', uuid);  if (result.ok) await restartService('xray');     break;
      case 'trojan':         result = xrayAdd(username, 'trojan', uuid); if (result.ok) await restartService('xray');     break;
      case 'ssh-multi':   // SSH MULTIPLE : WS + SSL + SlowDNS + UDP = même user Linux
      case 'ssh-ws':
      case 'ssh-slowdns':
      case 'ssh-ssl':
      case 'ssh-udp':        result = await sshAdd(username, password, expires_at); break; // SSH ne nécessite pas de restart
      case 'udp-zivpn': {
        result = zivpnAdd(username, password, expires_at);
        if (result.ok) {
          await restartService('zivpn');
          const readF = p => { try { return fs.readFileSync(p,'utf8').trim(); } catch { return null; } };
          const zCfg  = (() => { try { return JSON.parse(readF('/etc/zivpn/config.json')||'{}'); } catch { return {}; } })();
          const zPort = (zCfg.listen||':5667').replace(':','');
          result.config_info = {
            domain: readF('/etc/zivpn/domain.txt') || readF('/etc/kighmu/domain.txt') || null,
            obfs:   zCfg.obfs || 'zivpn',
            port:   zPort || '5667'
          };
        }
        break;
      }
      case 'udp-hysteria': {
        result = hysteriaAdd(username, password, expires_at);
        if (result.ok) {
          await restartService('hysteria');
          const readF = p => { try { return fs.readFileSync(p,'utf8').trim(); } catch { return null; } };
          const hCfg  = (() => { try { return JSON.parse(readF('/etc/hysteria/config.json')||'{}'); } catch { return {}; } })();
          const hPort = (hCfg.listen||':20000').replace(':','');
          result.config_info = {
            domain: readF('/etc/hysteria/domain.txt') || readF('/etc/kighmu/domain.txt') || null,
            obfs:   hCfg.obfs || 'hysteria',
            port:   hPort || '20000',
            port_range: `${hPort || '20000'}-50000`
          };
        }
        break;
      }
      case 'v2ray-fastdns':  result = v2rayAdd(username, uuid);          if (result.ok) await restartService('v2ray');    break;
    }
  } catch (e) { result = { ok: false, msg: e.message }; }
  return result;
}

async function removeTunnel(client) {
  const { username, uuid, tunnel_type } = client;
  try {
    switch (tunnel_type) {
      case 'vless':         xrayRemove(username, 'vless', uuid);  await restartService('xray');    break;
      case 'vmess':         xrayRemove(username, 'vmess', uuid);  await restartService('xray');    break;
      case 'trojan':        xrayRemove(username, 'trojan', uuid); await restartService('xray');    break;
      case 'ssh-multi':
      case 'ssh-ws':
      case 'ssh-slowdns':
      case 'ssh-ssl':
      case 'ssh-udp':       await sshRemove(username); break;
      case 'udp-zivpn':     zivpnRemove(username); break;
      case 'udp-hysteria':  hysteriaRemove(username); await restartService('hysteria'); break;
      case 'v2ray-fastdns': v2rayRemove(username, uuid); await restartService('v2ray'); break;
    }
  } catch (e) { console.error(`[TUNNEL] removeTunnel error:`, e.message); }
}

// ============================================================
// AUTH ROUTES
// ============================================================
app.post('/api/auth/admin/login', async (req, res) => {
  try {
    const { username, password } = req.body;
    const ip = req.ip || req.connection.remoteAddress || '0.0.0.0';
    if (!username || !password) return res.status(400).json({ error: 'Identifiant et mot de passe requis' });

    const blocked = await checkBruteForce(ip);
    if (blocked) return res.status(429).json({ error: blocked });

    const [[admin]] = await db.query('SELECT * FROM admins WHERE username=?', [username]);
    if (!admin || !(await bcrypt.compare(password, admin.password))) {
      await failAttempt(ip);
      return res.status(401).json({ error: 'Identifiants invalides' });
    }
    await clearAttempts(ip);
    await db.query('UPDATE admins SET last_login=NOW() WHERE id=?', [admin.id]);
    const token = jwt.sign(
      { id: admin.id, username: admin.username, role: 'admin' },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN || '8h' }
    );
    await log('admin', admin.id, 'LOGIN', null, null, null, ip);
    res.json({ token, role: 'admin', username: admin.username });
  } catch (e) {
    console.error('[AUTH] admin login error:', e.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

app.post('/api/auth/reseller/login', async (req, res) => {
  try {
    const { username, password } = req.body;
    const ip = req.ip || req.connection.remoteAddress || '0.0.0.0';
    if (!username || !password) return res.status(400).json({ error: 'Identifiant et mot de passe requis' });

    const blocked = await checkBruteForce(ip);
    if (blocked) return res.status(429).json({ error: blocked });

    const [[r]] = await db.query('SELECT * FROM resellers WHERE username=?', [username]);
    if (!r || !(await bcrypt.compare(password, r.password))) {
      await failAttempt(ip);
      return res.status(401).json({ error: 'Identifiants invalides' });
    }
    if (!r.is_active)                    return res.status(403).json({ error: 'Compte désactivé' });
    if (new Date(r.expires_at) < new Date()) {
      await db.query('UPDATE resellers SET is_active=0 WHERE id=?', [r.id]);
      return res.status(403).json({ error: 'Compte expiré' });
    }
    await clearAttempts(ip);
    const token = jwt.sign(
      { id: r.id, username: r.username, role: 'reseller' },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN || '8h' }
    );
    await log('reseller', r.id, 'LOGIN', null, null, null, ip);
    res.json({ token, role: 'reseller', username: r.username });
  } catch (e) {
    console.error('[AUTH] reseller login error:', e.message);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

// ============================================================
// ADMIN ROUTES
// ============================================================
const A = auth(['admin']);

app.get('/api/admin/resellers', A, async (req, res) => {
  try {
    const [rows] = await db.query(`
      SELECT r.*, (SELECT COUNT(*) FROM clients WHERE reseller_id=r.id) as total_clients
      FROM resellers r ORDER BY r.created_at DESC`);
    res.json(rows);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/admin/resellers', A, async (req, res) => {
  try {
    const { username, password, email, max_users, expires_at } = req.body;
    if (!username || !password || !expires_at) return res.status(400).json({ error: 'Champs requis manquants' });
    const [ex] = await db.query('SELECT id FROM resellers WHERE username=?', [username]);
    if (ex.length) return res.status(409).json({ error: 'Username déjà pris' });
    const hash = await bcrypt.hash(password, parseInt(process.env.BCRYPT_ROUNDS) || 12);
    const [r] = await db.query(
      'INSERT INTO resellers (username,password,email,max_users,expires_at,created_by) VALUES (?,?,?,?,?,?)',
      [username, hash, email||null, max_users||10, expires_at, req.user.id]);
    await log('admin', req.user.id, 'CREATE_RESELLER', 'reseller', r.insertId, { username }, req.ip);
    res.json({ id: r.insertId, message: 'Revendeur créé' });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.put('/api/admin/resellers/:id', A, async (req, res) => {
  try {
    const { max_users, expires_at, is_active, password } = req.body;
    const upd = {};
    if (max_users  !== undefined) upd.max_users  = max_users;
    if (expires_at !== undefined) upd.expires_at = expires_at;
    if (is_active  !== undefined) upd.is_active  = is_active;
    if (password) upd.password = await bcrypt.hash(password, parseInt(process.env.BCRYPT_ROUNDS) || 12);
    if (!Object.keys(upd).length) return res.status(400).json({ error: 'Aucun champ à modifier' });
    const sets = Object.keys(upd).map(k => `${k}=?`).join(',');
    await db.query(`UPDATE resellers SET ${sets} WHERE id=?`, [...Object.values(upd), req.params.id]);
    await log('admin', req.user.id, 'UPDATE_RESELLER', 'reseller', req.params.id, upd, req.ip);
    res.json({ message: 'Revendeur mis à jour' });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.delete('/api/admin/resellers/:id', A, async (req, res) => {
  try {
    const [clients] = await db.query('SELECT * FROM clients WHERE reseller_id=?', [req.params.id]);
    for (const c of clients) await removeTunnel(c);
    await db.query('DELETE FROM resellers WHERE id=?', [req.params.id]);
    await log('admin', req.user.id, 'DELETE_RESELLER', 'reseller', req.params.id, null, req.ip);
    res.json({ message: 'Revendeur supprimé' });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/admin/resellers/:id/clean', A, async (req, res) => {
  try {
    const [clients] = await db.query('SELECT * FROM clients WHERE reseller_id=?', [req.params.id]);
    for (const c of clients) await removeTunnel(c);
    await db.query('DELETE FROM clients WHERE reseller_id=?', [req.params.id]);
    await db.query('DELETE FROM usage_stats WHERE reseller_id=?', [req.params.id]);
    await db.query('UPDATE resellers SET used_users=0 WHERE id=?', [req.params.id]);
    await log('admin', req.user.id, 'CLEAN_RESELLER', 'reseller', req.params.id, null, req.ip);
    res.json({ message: 'Données nettoyées' });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/admin/clients', A, async (req, res) => {
  try {
    const [rows] = await db.query(`
      SELECT c.*, r.username as reseller_name,
        COALESCE(SUM(u.upload_bytes),0) as total_upload,
        COALESCE(SUM(u.download_bytes),0) as total_download
      FROM clients c
      LEFT JOIN resellers r ON c.reseller_id=r.id
      LEFT JOIN usage_stats u ON u.client_id=c.id
      GROUP BY c.id ORDER BY c.created_at DESC`);
    res.json(rows);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/admin/clients', A, async (req, res) => {
  try {
    const { username, password, tunnel_type, expires_at, note, reseller_id } = req.body;
    if (!username || !tunnel_type || !expires_at)
      return res.status(400).json({ error: 'username, tunnel_type et expires_at sont requis' });
    const [ex] = await db.query('SELECT id FROM clients WHERE username=?', [username]);
    if (ex.length) return res.status(409).json({ error: 'Username déjà utilisé' });
    if (reseller_id) {
      const [[r]] = await db.query('SELECT max_users, used_users FROM resellers WHERE id=?', [reseller_id]);
      if (!r) return res.status(404).json({ error: 'Revendeur introuvable' });
      if (r.used_users >= r.max_users) return res.status(403).json({ error: `Limite revendeur atteinte (${r.max_users})` });
    }
    const uuid = uuidv4();
    const pass = password || (Math.random().toString(36).slice(-8) + Math.random().toString(36).slice(-4).toUpperCase() + '!');
    const [ins] = await db.query(
      'INSERT INTO clients (username,password,uuid,reseller_id,tunnel_type,expires_at,note) VALUES (?,?,?,?,?,?,?)',
      [username, pass, uuid, reseller_id||null, tunnel_type, expires_at, note||null]);
    if (reseller_id) await db.query('UPDATE resellers SET used_users=used_users+1 WHERE id=?', [reseller_id]);
    const tunnelResult = await addTunnel({ username, password: pass, uuid, tunnel_type, expires_at });
    await log('admin', req.user.id, 'CREATE_CLIENT', 'client', ins.insertId, { username, tunnel_type }, req.ip);

    // Récupérer les infos VPS pour l'affichage du message post-création
    const readF = p => { try { return fs.readFileSync(p,'utf8').trim(); } catch { return null; } };
    const vpsInfo = {
      domain:      readF('/etc/kighmu/domain.txt') || readF('/etc/xray/domain') || readF('/tmp/.xray_domain') || readF('/etc/hysteria/domain.txt') || readF('/etc/zivpn/domain.txt') || null,
      xray_domain: readF('/etc/xray/domain') || readF('/tmp/.xray_domain') || null,
      v2ray_domain:readF('/.v2ray_domain') || null,
      slowdns_key: readF('/etc/slowdns/server.pub') || readF('/etc/slowdns_v2ray/server.pub') || null,
      slowdns_ns:  readF('/etc/slowdns/ns.conf')   || readF('/etc/slowdns_v2ray/ns.conf')    || null,
    };
    let hostIp = null;
    try { const nets = await si.networkInterfaces(); const eth=nets.find(n=>!n.internal&&n.ip4); hostIp=eth?.ip4||null; } catch {}
    vpsInfo.host_ip = hostIp;

    res.json({ id: ins.insertId, username, password: pass, uuid, tunnel_type, expires_at, tunnelResult, vpsInfo });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.put('/api/admin/clients/:id', A, async (req, res) => {
  try {
    const { expires_at, note, is_active } = req.body;
    const upd = {};
    if (expires_at !== undefined) upd.expires_at = expires_at;
    if (note       !== undefined) upd.note       = note;
    if (is_active  !== undefined) upd.is_active  = is_active;
    if (!Object.keys(upd).length) return res.status(400).json({ error: 'Aucun champ à modifier' });
    const sets = Object.keys(upd).map(k => `${k}=?`).join(',');
    await db.query(`UPDATE clients SET ${sets} WHERE id=?`, [...Object.values(upd), req.params.id]);
    await log('admin', req.user.id, 'UPDATE_CLIENT', 'client', req.params.id, upd, req.ip);
    res.json({ message: 'Client mis à jour' });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.delete('/api/admin/clients/:id', A, async (req, res) => {
  try {
    const [[c]] = await db.query('SELECT * FROM clients WHERE id=?', [req.params.id]);
    if (!c) return res.status(404).json({ error: 'Client introuvable' });
    await removeTunnel(c);
    if (c.reseller_id) await db.query('UPDATE resellers SET used_users=used_users-1 WHERE id=? AND used_users>0', [c.reseller_id]);
    await db.query('DELETE FROM clients WHERE id=?', [req.params.id]);
    await log('admin', req.user.id, 'DELETE_CLIENT', 'client', req.params.id, null, req.ip);
    res.json({ message: 'Client supprimé' });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/admin/stats', A, async (req, res) => {
  try {
    const [[usage]]  = await db.query('SELECT COALESCE(SUM(upload_bytes),0) as total_upload, COALESCE(SUM(download_bytes),0) as total_download FROM usage_stats');
    const [[counts]] = await db.query(`SELECT
      (SELECT COUNT(*) FROM resellers)              as total_resellers,
      (SELECT COUNT(*) FROM clients)                as total_clients,
      (SELECT COUNT(*) FROM clients WHERE is_active=1) as active_clients`);
    const [resellerStats] = await db.query(`
      SELECT r.id, r.username, r.max_users, r.used_users, r.expires_at, r.is_active,
        COALESCE(SUM(u.upload_bytes),0) as upload,
        COALESCE(SUM(u.download_bytes),0) as download
      FROM resellers r LEFT JOIN usage_stats u ON u.reseller_id=r.id GROUP BY r.id`);
    const [cpu, mem, disk] = await Promise.all([si.currentLoad(), si.mem(), si.fsSize()]);
    res.json({
      global: { ...usage, ...counts },
      resellers: resellerStats,
      system: {
        cpu_usage:  cpu.currentLoad.toFixed(1),
        ram_total:  mem.total,
        ram_used:   mem.used,
        ram_free:   mem.free,
        disk: disk[0] ? { total: disk[0].size, used: disk[0].used, free: disk[0].available } : null
      }
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/admin/logs', A, async (req, res) => {
  try {
    const [rows] = await db.query('SELECT * FROM activity_logs ORDER BY created_at DESC LIMIT 200');
    res.json(rows);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// ============================================================
// RESELLER ROUTES
// ============================================================
const R = auth(['reseller']);

app.get('/api/reseller/me', R, async (req, res) => {
  try {
    const [[r]] = await db.query(`
      SELECT r.id, r.username, r.max_users, r.used_users, r.expires_at, r.is_active,
        COALESCE(SUM(u.upload_bytes),0) as total_upload,
        COALESCE(SUM(u.download_bytes),0) as total_download
      FROM resellers r LEFT JOIN usage_stats u ON u.reseller_id=r.id
      WHERE r.id=? GROUP BY r.id`, [req.user.id]);
    res.json(r);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/reseller/clients', R, async (req, res) => {
  try {
    const [rows] = await db.query(`
      SELECT c.*,
        COALESCE(SUM(u.upload_bytes),0) as total_upload,
        COALESCE(SUM(u.download_bytes),0) as total_download
      FROM clients c LEFT JOIN usage_stats u ON u.client_id=c.id
      WHERE c.reseller_id=? GROUP BY c.id ORDER BY c.created_at DESC`, [req.user.id]);
    res.json(rows);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/reseller/clients', R, async (req, res) => {
  try {
    const { username, password, tunnel_type, expires_at, note } = req.body;
    if (!username || !tunnel_type || !expires_at) return res.status(400).json({ error: 'Champs requis manquants' });
    const [[r]] = await db.query('SELECT * FROM resellers WHERE id=?', [req.user.id]);
    if (r.used_users >= r.max_users) return res.status(403).json({ error: `Limite atteinte (${r.max_users} max)` });
    const [ex] = await db.query('SELECT id FROM clients WHERE username=?', [username]);
    if (ex.length) return res.status(409).json({ error: 'Username déjà utilisé' });
    const uuid = uuidv4();
    const pass = password || (Math.random().toString(36).slice(-8) + Math.random().toString(36).slice(-4).toUpperCase() + '!');
    const [ins] = await db.query(
      'INSERT INTO clients (username,password,uuid,reseller_id,tunnel_type,expires_at,note) VALUES (?,?,?,?,?,?,?)',
      [username, pass, uuid, req.user.id, tunnel_type, expires_at, note||null]);
    await db.query('UPDATE resellers SET used_users=used_users+1 WHERE id=?', [req.user.id]);
    const tunnelResult = await addTunnel({ username, password: pass, uuid, tunnel_type, expires_at });
    await log('reseller', req.user.id, 'CREATE_CLIENT', 'client', ins.insertId, { username, tunnel_type }, req.ip);
    res.json({ id: ins.insertId, username, password: pass, uuid, tunnel_type, tunnelResult });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.put('/api/reseller/clients/:id', R, async (req, res) => {
  try {
    const [[c]] = await db.query('SELECT id FROM clients WHERE id=? AND reseller_id=?', [req.params.id, req.user.id]);
    if (!c) return res.status(404).json({ error: 'Client introuvable' });
    const { expires_at, note, is_active } = req.body;
    const upd = {};
    if (expires_at !== undefined) upd.expires_at = expires_at;
    if (note       !== undefined) upd.note       = note;
    if (is_active  !== undefined) upd.is_active  = is_active;
    const sets = Object.keys(upd).map(k => `${k}=?`).join(',');
    await db.query(`UPDATE clients SET ${sets} WHERE id=?`, [...Object.values(upd), req.params.id]);
    await log('reseller', req.user.id, 'UPDATE_CLIENT', 'client', req.params.id, upd, req.ip);
    res.json({ message: 'Client mis à jour' });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.delete('/api/reseller/clients/:id', R, async (req, res) => {
  try {
    const [[c]] = await db.query('SELECT * FROM clients WHERE id=? AND reseller_id=?', [req.params.id, req.user.id]);
    if (!c) return res.status(404).json({ error: 'Client introuvable' });
    await removeTunnel(c);
    await db.query('DELETE FROM clients WHERE id=?', [req.params.id]);
    await db.query('UPDATE resellers SET used_users=used_users-1 WHERE id=? AND used_users>0', [req.user.id]);
    await log('reseller', req.user.id, 'DELETE_CLIENT', 'client', req.params.id, null, req.ip);
    res.json({ message: 'Client supprimé' });
  } catch (e) { res.status(500).json({ error: e.message }); }
});


// ============================================================
// ROUTE VPS INFO — infos système récupérées depuis les fichiers VPS
// ============================================================
app.get('/api/admin/vps-info', A, async (req, res) => {
  try {
    const readFile = (p) => { try { return fs.readFileSync(p,'utf8').trim(); } catch { return null; } };

    // Domaine (cherche dans plusieurs emplacements possibles)
    const domain =
      readFile('/etc/kighmu/domain.txt') ||
      readFile('~/.kighmu_info')?.match(/DOMAIN=([^\n]+)/)?.[1] ||
      readFile('/etc/xray/domain') ||
      readFile('/tmp/.xray_domain') ||
      readFile('/etc/hysteria/domain.txt') ||
      readFile('/etc/zivpn/domain.txt') ||
      null;

    // IP publique du VPS
    let hostIp = null;
    try {
      const nets = await si.networkInterfaces();
      const eth  = nets.find(n => !n.internal && n.ip4);
      hostIp = eth?.ip4 || null;
    } catch {}

    // Clé publique SlowDNS/FastDNS
    const slowdnsKey =
      readFile('/etc/slowdns/server.pub') ||
      readFile('/etc/slowdns_v2ray/server.pub') ||
      null;

    // NameServer SlowDNS
    const slowdnsNs =
      readFile('/etc/slowdns/ns.conf') ||
      readFile('/etc/slowdns_v2ray/ns.conf') ||
      null;

    // Domain xray (peut être différent)
    const xrayDomain =
      readFile('/etc/xray/domain') ||
      readFile('/tmp/.xray_domain') ||
      domain;

    // Domain V2Ray
    const v2rayDomain =
      readFile('/.v2ray_domain') ||
      domain;

    // Port Hysteria
    let hysteriaPort = '20000';
    try {
      const hCfg = JSON.parse(readFile('/etc/hysteria/config.json') || '{}');
      hysteriaPort = (hCfg.listen || ':20000').replace(':','') || '20000';
    } catch {}

    // Port ZIVPN
    let zivpnPort = '5667';
    try {
      const zCfg = JSON.parse(readFile('/etc/zivpn/config.json') || '{}');
      zivpnPort = (zCfg.listen || ':5667').replace(':','') || '5667';
    } catch {}

    res.json({
      domain,
      xray_domain:    xrayDomain,
      v2ray_domain:   v2rayDomain,
      host_ip:        hostIp,
      slowdns_key:    slowdnsKey,
      slowdns_ns:     slowdnsNs,
      hysteria_port:  hysteriaPort,
      hysteria_port_range: `${hysteriaPort}-50000`,
      zivpn_port:     zivpnPort,
      ssh_ports: {
        ws:       '80',
        ssl:      '444',
        proxy_ws: '9090',
        udp:      '1-65535',
        slowdns:  '5300',
        dropbear: '2222',
        badvpn:   '7200,7300'
      }
    });
  } catch (e) {
    console.error('[VPS-INFO]', e.message);
    res.status(500).json({ error: e.message });
  }
});

// Route vps-info pour resellers aussi
app.get('/api/reseller/vps-info', R, async (req, res) => {
  // Même logique, même réponse (les revendeurs ont besoin des mêmes infos)
  const readFile = (p) => { try { return fs.readFileSync(p,'utf8').trim(); } catch { return null; } };
  const domain =
    readFile('/etc/kighmu/domain.txt') ||
    readFile('/etc/xray/domain') ||
    readFile('/tmp/.xray_domain') ||
    readFile('/etc/hysteria/domain.txt') ||
    readFile('/etc/zivpn/domain.txt') ||
    null;
  let hostIp = null;
  try { const nets = await si.networkInterfaces(); const eth = nets.find(n=>!n.internal&&n.ip4); hostIp=eth?.ip4||null; } catch {}
  const slowdnsKey = readFile('/etc/slowdns/server.pub') || readFile('/etc/slowdns_v2ray/server.pub') || null;
  const slowdnsNs  = readFile('/etc/slowdns/ns.conf')   || readFile('/etc/slowdns_v2ray/ns.conf')    || null;
  let hysteriaPort='20000'; try { const h=JSON.parse(readFile('/etc/hysteria/config.json')||'{}'); hysteriaPort=(h.listen||':20000').replace(':','')||'20000'; } catch {}
  let zivpnPort='5667';    try { const z=JSON.parse(readFile('/etc/zivpn/config.json')||'{}'); zivpnPort=(z.listen||':5667').replace(':','')||'5667'; } catch {}
  res.json({
    domain, host_ip: hostIp, slowdns_key: slowdnsKey, slowdns_ns: slowdnsNs,
    hysteria_port: hysteriaPort, hysteria_port_range: `${hysteriaPort}-50000`,
    zivpn_port: zivpnPort,
    xray_domain: readFile('/etc/xray/domain')||readFile('/tmp/.xray_domain')||domain,
    v2ray_domain: readFile('/.v2ray_domain')||domain,
    ssh_ports: { ws:'80', ssl:'444', proxy_ws:'9090', udp:'1-65535', slowdns:'5300' }
  });
});

// ============================================================
// FRONTEND SPA ROUTING
// ============================================================
app.get('/admin*',    (_, res) => {
  const f = path.join(FRONTEND, 'admin/index.html');
  fs.existsSync(f) ? res.sendFile(f) : res.status(404).send('admin/index.html introuvable');
});
app.get('/reseller*', (_, res) => {
  const f = path.join(FRONTEND, 'reseller/index.html');
  fs.existsSync(f) ? res.sendFile(f) : res.status(404).send('reseller/index.html introuvable');
});
app.get('*',          (_, res) => {
  const f = path.join(FRONTEND, 'index.html');
  fs.existsSync(f) ? res.sendFile(f) : res.status(404).send('index.html introuvable');
});

// ============================================================
// GESTION GLOBALE DES ERREURS
// ============================================================
app.use((err, req, res, next) => {
  console.error('[ERROR]', err.message);
  res.status(500).json({ error: 'Erreur interne du serveur' });
});

process.on('uncaughtException',  e => console.error('[UNCAUGHT]', e.message));
process.on('unhandledRejection', e => console.error('[UNHANDLED]', e));

// ============================================================
// CRON
// ============================================================
function startCron() {
  cron.schedule('0 * * * *', async () => {
    if (!db) return;
    try {
      await db.query('UPDATE resellers SET is_active=0 WHERE expires_at < NOW() AND is_active=1');
      const [exp] = await db.query('SELECT * FROM clients WHERE expires_at < NOW() AND is_active=1');
      for (const c of exp) {
        await removeTunnel(c);
        await db.query('UPDATE clients SET is_active=0 WHERE id=?', [c.id]);
      }
      if (exp.length) console.log(`[CRON] ${exp.length} clients expirés désactivés`);
    } catch (e) { console.error('[CRON] erreur:', e.message); }
  });

  cron.schedule('0 0 * * *', async () => {
    if (!db) return;
    try { await db.query("DELETE FROM login_attempts WHERE last_attempt < DATE_SUB(NOW(), INTERVAL 1 DAY)"); }
    catch {}
  });
}

// ============================================================
// DÉMARRAGE
// ============================================================
async function start() {
  const PORT = parseInt(process.env.PORT || '3000');

  // Connexion DB (réessaie 3 fois)
  let connected = false;
  for (let i = 1; i <= 3; i++) {
    console.log(`[DB] Tentative de connexion ${i}/3...`);
    connected = await initDB();
    if (connected) break;
    if (i < 3) await new Promise(r => setTimeout(r, 3000));
  }

  if (!connected) {
    console.error('[FATAL] Impossible de se connecter à MySQL après 3 tentatives.');
    console.error('[FATAL] Vérifiez : systemctl status mysql');
    console.error('[FATAL] Le serveur démarre quand même — les routes /api renverront 503');
  }

  // Démarrer le serveur HTTP
  app.listen(PORT, '0.0.0.0', () => {
    console.log('');
    console.log('╔══════════════════════════════════════╗');
    console.log(`║   KIGHMU PANEL v2 — port ${PORT}       ║`);
    console.log('╚══════════════════════════════════════╝');
    console.log(`  → http://0.0.0.0:${PORT}/`);
    console.log(`  → http://0.0.0.0:${PORT}/admin`);
    console.log(`  → http://0.0.0.0:${PORT}/reseller`);
    console.log(`  → http://0.0.0.0:${PORT}/health  (diagnostic)`);
    console.log(`  DB: ${connected ? 'connectée ✓' : 'ERREUR ✗'}`);
    console.log('');
  });

  if (connected) startCron();
}

start().catch(e => {
  console.error('[FATAL] Erreur démarrage:', e.message);
  process.exit(1);
});
