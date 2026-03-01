// ============================================================
// KIGHMU PANEL v2 - Backend complet (1 fichier)
// Node.js + Express + MySQL + JWT + bcrypt + CRON
// ============================================================
require('dotenv').config();
const express    = require('express');
const mysql      = require('mysql2/promise');
const bcrypt     = require('bcryptjs');
const jwt        = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const helmet     = require('helmet');
const cors       = require('cors');
const rateLimit  = require('express-rate-limit');
const cron       = require('node-cron');
const si         = require('systeminformation');
const fs         = require('fs');
const { exec }   = require('child_process');
const path       = require('path');

const app = express();

// ============================================================
// DATABASE
// ============================================================
const db = mysql.createPool({
  host:            process.env.DB_HOST || 'localhost',
  port:            process.env.DB_PORT || 3306,
  database:        process.env.DB_NAME || 'kighmu_panel',
  user:            process.env.DB_USER,
  password:        process.env.DB_PASSWORD,
  waitForConnections: true,
  connectionLimit: 20,
  enableKeepAlive: true,
});

// ============================================================
// MIDDLEWARE GLOBAL
// ============================================================
app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors({ credentials: true }));
app.use(express.json({ limit: '10kb' }));
app.set('trust proxy', 1);
app.use(rateLimit({ windowMs: 15 * 60 * 1000, max: 300 }));

// Fichiers statiques frontend
app.use(express.static(path.join(__dirname, 'frontend')));

// ============================================================
// BRUTE FORCE PROTECTION
// ============================================================
const MAX_ATT   = parseInt(process.env.MAX_LOGIN_ATTEMPTS) || 5;
const BLOCK_MIN = parseInt(process.env.BLOCK_DURATION_MINUTES) || 30;

async function checkBruteForce(ip) {
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
}
async function failAttempt(ip) {
  const [r] = await db.query('SELECT id FROM login_attempts WHERE ip_address=?', [ip]);
  if (r.length) await db.query('UPDATE login_attempts SET attempts=attempts+1,last_attempt=NOW() WHERE ip_address=?', [ip]);
  else await db.query('INSERT INTO login_attempts (ip_address) VALUES (?)', [ip]);
}
async function clearAttempts(ip) {
  await db.query('DELETE FROM login_attempts WHERE ip_address=?', [ip]);
}

// ============================================================
// JWT AUTH MIDDLEWARE
// ============================================================
function auth(roles = []) {
  return async (req, res, next) => {
    try {
      const token = req.headers.authorization?.split(' ')[1];
      if (!token) return res.status(401).json({ error: 'Token manquant' });
      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      if (roles.length && !roles.includes(decoded.role))
        return res.status(403).json({ error: 'Accès refusé' });
      if (decoded.role === 'reseller') {
        const [[r]] = await db.query('SELECT is_active,expires_at FROM resellers WHERE id=?', [decoded.id]);
        if (!r || !r.is_active) return res.status(401).json({ error: 'Compte désactivé' });
        if (new Date(r.expires_at) < new Date()) {
          await db.query('UPDATE resellers SET is_active=0 WHERE id=?', [decoded.id]);
          return res.status(401).json({ error: 'Compte expiré' });
        }
      }
      req.user = decoded;
      next();
    } catch { return res.status(401).json({ error: 'Token invalide' }); }
  };
}

// ============================================================
// LOGGER
// ============================================================
async function log(actorType, actorId, action, targetType, targetId, details, ip) {
  try {
    await db.query(
      'INSERT INTO activity_logs (actor_type,actor_id,action,target_type,target_id,details,ip_address) VALUES (?,?,?,?,?,?,?)',
      [actorType, actorId, action, targetType||null, targetId||null, details?JSON.stringify(details):null, ip||null]
    );
  } catch(e) { console.error('Log error:', e.message); }
}

// ============================================================
// TUNNEL MANAGER
// ============================================================
const execAsync = (cmd) => new Promise((res, rej) =>
  exec(cmd, (e, out, err) => e ? rej(new Error(err||e.message)) : res(out))
);
const readJson  = (p) => { try { return JSON.parse(fs.readFileSync(p,'utf8')); } catch { return null; } };
const writeJson = (p, d) => fs.writeFileSync(p, JSON.stringify(d, null, 2));

async function restartService(svc) {
  try { await execAsync(`systemctl restart ${svc}`); return true; }
  catch(e) { console.error(`restart ${svc}:`, e.message); return false; }
}

function xrayAdd(username, protocol, uuid) {
  const cfg = readJson(process.env.XRAY_CONFIG || '/etc/xray/config.json');
  if (!cfg) return { ok: false, msg: 'config xray introuvable' };
  const inb = cfg.inbounds?.find(i => i.protocol === protocol.toLowerCase());
  if (!inb) return { ok: false, msg: `inbound ${protocol} introuvable` };
  if (!inb.settings) inb.settings = {};
  if (!inb.settings.clients) inb.settings.clients = [];
  const client = protocol === 'trojan'
    ? { password: username, level: 0, email: username }
    : { id: uuid, level: 0, email: username };
  inb.settings.clients.push(client);
  writeJson(process.env.XRAY_CONFIG || '/etc/xray/config.json', cfg);
  return { ok: true };
}

function xrayRemove(username, protocol, uuid) {
  const cfg = readJson(process.env.XRAY_CONFIG || '/etc/xray/config.json');
  if (!cfg) return;
  const inb = cfg.inbounds?.find(i => i.protocol === protocol.toLowerCase());
  if (!inb?.settings?.clients) return;
  inb.settings.clients = inb.settings.clients.filter(
    c => c.id !== uuid && c.email !== username && c.password !== username
  );
  writeJson(process.env.XRAY_CONFIG || '/etc/xray/config.json', cfg);
}

async function sshAdd(username, password, expiryDate) {
  try {
    const exp = new Date(expiryDate).toISOString().split('T')[0];
    await execAsync(`useradd -M -s /bin/false -e ${exp} ${username}`);
    await execAsync(`echo "${username}:${password}" | chpasswd`);
    return { ok: true };
  } catch(e) { return { ok: false, msg: e.message }; }
}
async function sshRemove(username) {
  try { await execAsync(`userdel -r ${username} 2>/dev/null || true`); } catch {}
}

function zivpnAdd(username, password) {
  try {
    const f = process.env.ZIVPN_USERS || '/etc/udp/users.txt';
    if (!fs.existsSync(path.dirname(f))) return { ok: false, msg: 'ZIVPN non installé' };
    fs.appendFileSync(f, `${username}:${password}\n`);
    return { ok: true };
  } catch(e) { return { ok: false, msg: e.message }; }
}
function zivpnRemove(username) {
  try {
    const f = process.env.ZIVPN_USERS || '/etc/udp/users.txt';
    if (!fs.existsSync(f)) return;
    const lines = fs.readFileSync(f,'utf8').split('\n').filter(l => !l.startsWith(`${username}:`));
    fs.writeFileSync(f, lines.join('\n'));
  } catch {}
}

function hysteriaAdd(username, password) {
  try {
    const f = process.env.HYSTERIA_USERS || '/etc/hysteria/users.json';
    if (!fs.existsSync(path.dirname(f))) return { ok: false, msg: 'Hysteria non installé' };
    let users = {};
    if (fs.existsSync(f)) try { users = JSON.parse(fs.readFileSync(f,'utf8')); } catch {}
    users[username] = password;
    fs.writeFileSync(f, JSON.stringify(users, null, 2));
    return { ok: true };
  } catch(e) { return { ok: false, msg: e.message }; }
}
function hysteriaRemove(username) {
  try {
    const f = process.env.HYSTERIA_USERS || '/etc/hysteria/users.json';
    if (!fs.existsSync(f)) return;
    const u = JSON.parse(fs.readFileSync(f,'utf8'));
    delete u[username];
    fs.writeFileSync(f, JSON.stringify(u, null, 2));
  } catch {}
}

function v2rayAdd(username, uuid) {
  const cfg = readJson(process.env.V2RAY_CONFIG || '/etc/v2ray/config.json');
  if (!cfg) return { ok: false, msg: 'config v2ray introuvable' };
  const inb = cfg.inbounds?.[0];
  if (!inb?.settings?.clients) return { ok: false, msg: 'inbound vmess introuvable' };
  inb.settings.clients.push({ id: uuid, alterId: 0, email: username });
  writeJson(process.env.V2RAY_CONFIG || '/etc/v2ray/config.json', cfg);
  return { ok: true };
}
function v2rayRemove(username, uuid) {
  const cfg = readJson(process.env.V2RAY_CONFIG || '/etc/v2ray/config.json');
  if (!cfg) return;
  const inb = cfg.inbounds?.[0];
  if (!inb?.settings?.clients) return;
  inb.settings.clients = inb.settings.clients.filter(c => c.id !== uuid && c.email !== username);
  writeJson(process.env.V2RAY_CONFIG || '/etc/v2ray/config.json', cfg);
}

async function addTunnel(client) {
  const { username, password, uuid, tunnel_type, expires_at } = client;
  let result = {};
  switch(tunnel_type) {
    case 'vless':  result = xrayAdd(username,'vless',uuid);  if(result.ok) await restartService('xray');  break;
    case 'vmess':  result = xrayAdd(username,'vmess',uuid);  if(result.ok) await restartService('xray');  break;
    case 'trojan': result = xrayAdd(username,'trojan',uuid); if(result.ok) await restartService('xray');  break;
    case 'ssh-ws': case 'ssh-slowdns': case 'ssh-ssl':
      result = await sshAdd(username, password, expires_at);
      if(result.ok) await restartService('ssh'); break;
    case 'udp-zivpn': result = zivpnAdd(username, password); break;
    case 'udp-hysteria': result = hysteriaAdd(username, password); if(result.ok) await restartService('hysteria'); break;
    case 'v2ray-fastdns': result = v2rayAdd(username, uuid); if(result.ok) await restartService('v2ray'); break;
  }
  return result;
}

async function removeTunnel(client) {
  const { username, uuid, tunnel_type } = client;
  switch(tunnel_type) {
    case 'vless':  xrayRemove(username,'vless',uuid);  await restartService('xray');  break;
    case 'vmess':  xrayRemove(username,'vmess',uuid);  await restartService('xray');  break;
    case 'trojan': xrayRemove(username,'trojan',uuid); await restartService('xray');  break;
    case 'ssh-ws': case 'ssh-slowdns': case 'ssh-ssl': await sshRemove(username); break;
    case 'udp-zivpn': zivpnRemove(username); break;
    case 'udp-hysteria': hysteriaRemove(username); await restartService('hysteria'); break;
    case 'v2ray-fastdns': v2rayRemove(username, uuid); await restartService('v2ray'); break;
  }
}

// ============================================================
// ROUTES — AUTH
// ============================================================
app.post('/api/auth/admin/login', async (req, res) => {
  const { username, password } = req.body;
  const ip = req.ip;
  if (!username || !password) return res.status(400).json({ error: 'Champs requis' });
  const blocked = await checkBruteForce(ip);
  if (blocked) return res.status(429).json({ error: blocked });
  const [[admin]] = await db.query('SELECT * FROM admins WHERE username=?', [username]);
  if (!admin || !(await bcrypt.compare(password, admin.password))) {
    await failAttempt(ip);
    return res.status(401).json({ error: 'Identifiants invalides' });
  }
  await clearAttempts(ip);
  await db.query('UPDATE admins SET last_login=NOW() WHERE id=?', [admin.id]);
  const token = jwt.sign({ id: admin.id, username: admin.username, role: 'admin' },
    process.env.JWT_SECRET, { expiresIn: process.env.JWT_EXPIRES_IN || '8h' });
  await log('admin', admin.id, 'LOGIN', null, null, null, ip);
  res.json({ token, role: 'admin', username: admin.username });
});

app.post('/api/auth/reseller/login', async (req, res) => {
  const { username, password } = req.body;
  const ip = req.ip;
  if (!username || !password) return res.status(400).json({ error: 'Champs requis' });
  const blocked = await checkBruteForce(ip);
  if (blocked) return res.status(429).json({ error: blocked });
  const [[r]] = await db.query('SELECT * FROM resellers WHERE username=?', [username]);
  if (!r || !(await bcrypt.compare(password, r.password))) {
    await failAttempt(ip); return res.status(401).json({ error: 'Identifiants invalides' });
  }
  if (!r.is_active) return res.status(403).json({ error: 'Compte désactivé' });
  if (new Date(r.expires_at) < new Date()) {
    await db.query('UPDATE resellers SET is_active=0 WHERE id=?', [r.id]);
    return res.status(403).json({ error: 'Compte expiré' });
  }
  await clearAttempts(ip);
  const token = jwt.sign({ id: r.id, username: r.username, role: 'reseller' },
    process.env.JWT_SECRET, { expiresIn: process.env.JWT_EXPIRES_IN || '8h' });
  await log('reseller', r.id, 'LOGIN', null, null, null, ip);
  res.json({ token, role: 'reseller', username: r.username });
});

// ============================================================
// ROUTES — ADMIN
// ============================================================
const A = auth(['admin']);

// Revendeurs
app.get('/api/admin/resellers', A, async (req, res) => {
  const [rows] = await db.query(`
    SELECT r.*, (SELECT COUNT(*) FROM clients WHERE reseller_id=r.id) as total_clients
    FROM resellers r ORDER BY r.created_at DESC`);
  res.json(rows);
});

app.post('/api/admin/resellers', A, async (req, res) => {
  const { username, password, email, max_users, expires_at } = req.body;
  if (!username || !password || !expires_at) return res.status(400).json({ error: 'Champs requis' });
  const [ex] = await db.query('SELECT id FROM resellers WHERE username=?', [username]);
  if (ex.length) return res.status(409).json({ error: 'Username déjà pris' });
  const hash = await bcrypt.hash(password, parseInt(process.env.BCRYPT_ROUNDS)||12);
  const [r] = await db.query(
    'INSERT INTO resellers (username,password,email,max_users,expires_at,created_by) VALUES (?,?,?,?,?,?)',
    [username, hash, email||null, max_users||10, expires_at, req.user.id]);
  await log('admin', req.user.id, 'CREATE_RESELLER', 'reseller', r.insertId, { username });
  res.json({ id: r.insertId, message: 'Revendeur créé' });
});

app.put('/api/admin/resellers/:id', A, async (req, res) => {
  const { max_users, expires_at, is_active, password } = req.body;
  const upd = {};
  if (max_users  !== undefined) upd.max_users  = max_users;
  if (expires_at !== undefined) upd.expires_at = expires_at;
  if (is_active  !== undefined) upd.is_active  = is_active;
  if (password) upd.password = await bcrypt.hash(password, parseInt(process.env.BCRYPT_ROUNDS)||12);
  const sets = Object.keys(upd).map(k=>`${k}=?`).join(',');
  await db.query(`UPDATE resellers SET ${sets} WHERE id=?`, [...Object.values(upd), req.params.id]);
  await log('admin', req.user.id, 'UPDATE_RESELLER', 'reseller', req.params.id, upd);
  res.json({ message: 'Revendeur mis à jour' });
});

app.delete('/api/admin/resellers/:id', A, async (req, res) => {
  const [clients] = await db.query('SELECT * FROM clients WHERE reseller_id=?', [req.params.id]);
  for (const c of clients) await removeTunnel(c);
  await db.query('DELETE FROM resellers WHERE id=?', [req.params.id]);
  await log('admin', req.user.id, 'DELETE_RESELLER', 'reseller', req.params.id);
  res.json({ message: 'Revendeur supprimé' });
});

app.post('/api/admin/resellers/:id/clean', A, async (req, res) => {
  const [clients] = await db.query('SELECT * FROM clients WHERE reseller_id=?', [req.params.id]);
  for (const c of clients) await removeTunnel(c);
  await db.query('DELETE FROM clients WHERE reseller_id=?', [req.params.id]);
  await db.query('DELETE FROM usage_stats WHERE reseller_id=?', [req.params.id]);
  await db.query('UPDATE resellers SET used_users=0 WHERE id=?', [req.params.id]);
  await log('admin', req.user.id, 'CLEAN_RESELLER', 'reseller', req.params.id);
  res.json({ message: 'Données nettoyées' });
});

// Clients (admin)
app.get('/api/admin/clients', A, async (req, res) => {
  const [rows] = await db.query(`
    SELECT c.*, r.username as reseller_name,
      COALESCE(SUM(u.upload_bytes),0) as total_upload,
      COALESCE(SUM(u.download_bytes),0) as total_download
    FROM clients c
    LEFT JOIN resellers r ON c.reseller_id=r.id
    LEFT JOIN usage_stats u ON u.client_id=c.id
    GROUP BY c.id ORDER BY c.created_at DESC`);
  res.json(rows);
});

app.post('/api/admin/clients', A, async (req, res) => {
  const { username, password, tunnel_type, expires_at, note, reseller_id } = req.body;
  if (!username || !tunnel_type || !expires_at)
    return res.status(400).json({ error: 'username, tunnel_type, expires_at requis' });
  const [ex] = await db.query('SELECT id FROM clients WHERE username=?', [username]);
  if (ex.length) return res.status(409).json({ error: 'Username déjà utilisé' });
  if (reseller_id) {
    const [[r]] = await db.query('SELECT max_users,used_users FROM resellers WHERE id=?', [reseller_id]);
    if (!r) return res.status(404).json({ error: 'Revendeur introuvable' });
    if (r.used_users >= r.max_users) return res.status(403).json({ error: `Limite revendeur atteinte (${r.max_users})` });
  }
  const uuid = uuidv4();
  const pass = password || (Math.random().toString(36).slice(-8) + Math.random().toString(36).slice(-4).toUpperCase());
  const [ins] = await db.query(
    'INSERT INTO clients (username,password,uuid,reseller_id,tunnel_type,expires_at,note) VALUES (?,?,?,?,?,?,?)',
    [username, pass, uuid, reseller_id||null, tunnel_type, expires_at, note||null]);
  if (reseller_id) await db.query('UPDATE resellers SET used_users=used_users+1 WHERE id=?', [reseller_id]);
  const tunnelResult = await addTunnel({ username, password: pass, uuid, tunnel_type, expires_at });
  await log('admin', req.user.id, 'CREATE_CLIENT', 'client', ins.insertId, { username, tunnel_type });
  res.json({ id: ins.insertId, username, password: pass, uuid, tunnel_type, expires_at, tunnelResult });
});

app.put('/api/admin/clients/:id', A, async (req, res) => {
  const { expires_at, note, is_active } = req.body;
  const upd = {};
  if (expires_at !== undefined) upd.expires_at = expires_at;
  if (note       !== undefined) upd.note       = note;
  if (is_active  !== undefined) upd.is_active  = is_active;
  const sets = Object.keys(upd).map(k=>`${k}=?`).join(',');
  await db.query(`UPDATE clients SET ${sets} WHERE id=?`, [...Object.values(upd), req.params.id]);
  await log('admin', req.user.id, 'UPDATE_CLIENT', 'client', req.params.id, upd);
  res.json({ message: 'Client mis à jour' });
});

app.delete('/api/admin/clients/:id', A, async (req, res) => {
  const [[c]] = await db.query('SELECT * FROM clients WHERE id=?', [req.params.id]);
  if (!c) return res.status(404).json({ error: 'Client introuvable' });
  await removeTunnel(c);
  if (c.reseller_id) await db.query('UPDATE resellers SET used_users=used_users-1 WHERE id=? AND used_users>0', [c.reseller_id]);
  await db.query('DELETE FROM clients WHERE id=?', [req.params.id]);
  await log('admin', req.user.id, 'DELETE_CLIENT', 'client', req.params.id);
  res.json({ message: 'Client supprimé' });
});

// Stats & système
app.get('/api/admin/stats', A, async (req, res) => {
  const [[usage]] = await db.query('SELECT COALESCE(SUM(upload_bytes),0) as total_upload, COALESCE(SUM(download_bytes),0) as total_download FROM usage_stats');
  const [[counts]] = await db.query(`SELECT (SELECT COUNT(*) FROM resellers) as total_resellers,(SELECT COUNT(*) FROM clients) as total_clients,(SELECT COUNT(*) FROM clients WHERE is_active=1) as active_clients`);
  const [resellerStats] = await db.query(`SELECT r.id,r.username,r.max_users,r.used_users,r.expires_at,r.is_active, COALESCE(SUM(u.upload_bytes),0) as upload,COALESCE(SUM(u.download_bytes),0) as download FROM resellers r LEFT JOIN usage_stats u ON u.reseller_id=r.id GROUP BY r.id`);
  const [cpu, mem, disk] = await Promise.all([si.currentLoad(), si.mem(), si.fsSize()]);
  res.json({
    global: { ...usage, ...counts },
    resellers: resellerStats,
    system: {
      cpu_usage: cpu.currentLoad.toFixed(1),
      ram_total: mem.total, ram_used: mem.used, ram_free: mem.free,
      disk: disk[0] ? { total: disk[0].size, used: disk[0].used, free: disk[0].available } : null
    }
  });
});

app.get('/api/admin/logs', A, async (req, res) => {
  const [rows] = await db.query('SELECT * FROM activity_logs ORDER BY created_at DESC LIMIT 200');
  res.json(rows);
});

// ============================================================
// ROUTES — RESELLER
// ============================================================
const R = auth(['reseller']);

app.get('/api/reseller/me', R, async (req, res) => {
  const [[r]] = await db.query(`
    SELECT r.id,r.username,r.max_users,r.used_users,r.expires_at,r.is_active,
      COALESCE(SUM(u.upload_bytes),0) as total_upload,
      COALESCE(SUM(u.download_bytes),0) as total_download
    FROM resellers r LEFT JOIN usage_stats u ON u.reseller_id=r.id
    WHERE r.id=? GROUP BY r.id`, [req.user.id]);
  res.json(r);
});

app.get('/api/reseller/clients', R, async (req, res) => {
  const [rows] = await db.query(`
    SELECT c.*, COALESCE(SUM(u.upload_bytes),0) as total_upload, COALESCE(SUM(u.download_bytes),0) as total_download
    FROM clients c LEFT JOIN usage_stats u ON u.client_id=c.id
    WHERE c.reseller_id=? GROUP BY c.id ORDER BY c.created_at DESC`, [req.user.id]);
  res.json(rows);
});

app.post('/api/reseller/clients', R, async (req, res) => {
  const { username, password, tunnel_type, expires_at, note } = req.body;
  if (!username || !tunnel_type || !expires_at) return res.status(400).json({ error: 'Champs requis' });
  const [[r]] = await db.query('SELECT * FROM resellers WHERE id=?', [req.user.id]);
  if (r.used_users >= r.max_users) return res.status(403).json({ error: `Limite atteinte (${r.max_users} max)` });
  const [ex] = await db.query('SELECT id FROM clients WHERE username=?', [username]);
  if (ex.length) return res.status(409).json({ error: 'Username déjà utilisé' });
  const uuid = uuidv4();
  const pass = password || (Math.random().toString(36).slice(-8) + Math.random().toString(36).slice(-4).toUpperCase());
  const [ins] = await db.query(
    'INSERT INTO clients (username,password,uuid,reseller_id,tunnel_type,expires_at,note) VALUES (?,?,?,?,?,?,?)',
    [username, pass, uuid, req.user.id, tunnel_type, expires_at, note||null]);
  await db.query('UPDATE resellers SET used_users=used_users+1 WHERE id=?', [req.user.id]);
  const tunnelResult = await addTunnel({ username, password: pass, uuid, tunnel_type, expires_at });
  await log('reseller', req.user.id, 'CREATE_CLIENT', 'client', ins.insertId, { username, tunnel_type });
  res.json({ id: ins.insertId, username, password: pass, uuid, tunnel_type, tunnelResult });
});

app.put('/api/reseller/clients/:id', R, async (req, res) => {
  const [[c]] = await db.query('SELECT id FROM clients WHERE id=? AND reseller_id=?', [req.params.id, req.user.id]);
  if (!c) return res.status(404).json({ error: 'Client introuvable' });
  const { expires_at, note, is_active } = req.body;
  const upd = {};
  if (expires_at !== undefined) upd.expires_at = expires_at;
  if (note       !== undefined) upd.note       = note;
  if (is_active  !== undefined) upd.is_active  = is_active;
  const sets = Object.keys(upd).map(k=>`${k}=?`).join(',');
  await db.query(`UPDATE clients SET ${sets} WHERE id=?`, [...Object.values(upd), req.params.id]);
  await log('reseller', req.user.id, 'UPDATE_CLIENT', 'client', req.params.id, upd);
  res.json({ message: 'Client mis à jour' });
});

app.delete('/api/reseller/clients/:id', R, async (req, res) => {
  const [[c]] = await db.query('SELECT * FROM clients WHERE id=? AND reseller_id=?', [req.params.id, req.user.id]);
  if (!c) return res.status(404).json({ error: 'Client introuvable' });
  await removeTunnel(c);
  await db.query('DELETE FROM clients WHERE id=?', [req.params.id]);
  await db.query('UPDATE resellers SET used_users=used_users-1 WHERE id=? AND used_users>0', [req.user.id]);
  await log('reseller', req.user.id, 'DELETE_CLIENT', 'client', req.params.id);
  res.json({ message: 'Client supprimé' });
});

// ============================================================
// FRONTEND ROUTING
// ============================================================
app.get('/admin*',    (_, res) => res.sendFile(path.join(__dirname, 'frontend/admin/index.html')));
app.get('/reseller*', (_, res) => res.sendFile(path.join(__dirname, 'frontend/reseller/index.html')));
app.get('*',          (_, res) => res.sendFile(path.join(__dirname, 'frontend/index.html')));

// ============================================================
// CRON — EXPIRATION AUTO
// ============================================================
cron.schedule('0 * * * *', async () => {
  await db.query('UPDATE resellers SET is_active=0 WHERE expires_at < NOW() AND is_active=1');
  const [exp] = await db.query('SELECT * FROM clients WHERE expires_at < NOW() AND is_active=1');
  for (const c of exp) {
    await removeTunnel(c);
    await db.query('UPDATE clients SET is_active=0 WHERE id=?', [c.id]);
  }
  if (exp.length) console.log(`[CRON] ${exp.length} clients expirés désactivés`);
});

cron.schedule('0 0 * * *', async () => {
  await db.query("DELETE FROM login_attempts WHERE last_attempt < DATE_SUB(NOW(), INTERVAL 1 DAY)");
});

// ============================================================
// START
// ============================================================
const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n🚀 Kighmu Panel v2 — port ${PORT}`);
  console.log(`   → http://0.0.0.0:${PORT}/admin`);
  console.log(`   → http://0.0.0.0:${PORT}/reseller\n`);
});
