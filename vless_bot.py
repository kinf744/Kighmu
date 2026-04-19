#!/usr/bin/env python3
"""
Bot Telegram VLESS Generator
UUID fixe : 29580a0a-088f-4e5e-8e67-008174c2e451
Path fixe  : /KIGHMU
Auth       : skills.google SSO token → GCP access_token (flux reel)
"""

import re
import json
import asyncio
import sqlite3
import logging
import urllib.parse
from datetime import datetime, timedelta
from typing import Optional

import aiohttp
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application, CommandHandler, MessageHandler,
    filters, ContextTypes, CallbackQueryHandler
)

BOT_TOKEN             = "TON_BOT_TOKEN_ICI"
ADMIN_IDS             = []
VLESS_UUID            = "29580a0a-088f-4e5e-8e67-008174c2e451"
VLESS_PATH            = "/KIGHMU"
VLESS_PORT            = 443
CLOUDRUN_IMAGE        = "ghcr.io/teddysun/xray:latest"
CLOUDRUN_REGION       = "us-central1"
CLOUDRUN_SERVICE_NAME = "vless-server"
DB_PATH               = "/var/lib/vless-bot/vless_bot.db"

logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    level=logging.INFO,
    handlers=[
        logging.FileHandler("/var/log/vless-bot/bot.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# ═══════════════════════════════════════════════════════════
#  BASE DE DONNEES
# ═══════════════════════════════════════════════════════════

def init_db():
    import os
    os.makedirs("/var/lib/vless-bot", exist_ok=True)
    os.makedirs("/var/log/vless-bot", exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""CREATE TABLE IF NOT EXISTS active_links (
        id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER,
        vless_link TEXT, project_id TEXT, expiry TEXT,
        created_at TEXT DEFAULT (datetime('now')))""")
    conn.execute("""CREATE TABLE IF NOT EXISTS projects (
        project_id TEXT PRIMARY KEY, service_url TEXT,
        region TEXT, created_at TEXT DEFAULT (datetime('now')))""")
    conn.commit(); conn.close()

def db_save_link(user_id, vless_link, project_id, expiry):
    conn = sqlite3.connect(DB_PATH)
    conn.execute("INSERT INTO active_links (user_id,vless_link,project_id,expiry) VALUES (?,?,?,?)",
                 (user_id, vless_link, project_id, expiry))
    conn.commit(); conn.close()

def db_active_count():
    conn = sqlite3.connect(DB_PATH)
    c = conn.execute("SELECT COUNT(*) FROM active_links WHERE expiry > datetime('now')").fetchone()[0]
    conn.close(); return c

def db_save_project(project_id, service_url, region):
    conn = sqlite3.connect(DB_PATH)
    conn.execute("INSERT OR REPLACE INTO projects (project_id,service_url,region) VALUES (?,?,?)",
                 (project_id, service_url, region))
    conn.commit(); conn.close()

# ═══════════════════════════════════════════════════════════
#  PARSER LE LIEN SKILLS.GOOGLE
#  Le lien contient :
#    - token=XXXX          → SSO token Qwiklabs (clé principale)
#    - display_token=XXXX  → token alternatif
#    - project=XXX         → project_id GCP
#    - Email=student-...   → email du compte temporaire
# ═══════════════════════════════════════════════════════════

def parse_lab_input(text: str) -> Optional[dict]:
    text = text.strip()
    result = {
        "type":          None,
        "project_id":    None,
        "student_email": None,
        "sso_token":     None,
        "display_token": None,
        "raw_url":       None,
        "sa_key":        None,
        "access_token":  None,
    }

    # ── Service Account JSON ──────────────────────────────
    if text.startswith("{") and '"type"' in text:
        try:
            key = json.loads(text)
            if key.get("type") == "service_account":
                result.update(type="service_account",
                              project_id=key.get("project_id"), sa_key=key)
                logger.info("Input: SA JSON project=%s", result["project_id"])
                return result
        except json.JSONDecodeError:
            pass

    # ── ya29 access_token direct ──────────────────────────
    m = re.search(r'ya29\.[A-Za-z0-9_\-\.]{20,}', text)
    if m:
        result["access_token"] = m.group(0)
        result["type"]         = "access_token"
        pm = re.search(r'(?:project[_ ]?id|project)\s*[:\s]+\s*(qwiklabs-gcp-[a-z0-9\-]+)',
                       text, re.I)
        if pm:
            result["project_id"] = pm.group(1)
        logger.info("Input: ya29 token project=%s", result["project_id"])
        return result

    # ── Lien skills.google / qwiklabs (format principal) ──
    if "skills.google" in text or "qwiklabs.com" in text or "accounts.google.com" in text:
        full = urllib.parse.unquote(text)
        # Decoder plusieurs fois car le lien est double/triple encodé
        for _ in range(3):
            decoded = urllib.parse.unquote(full)
            if decoded == full:
                break
            full = decoded

        result["raw_url"] = text

        # project_id
        for pat in [
            r'project[=:](qwiklabs-gcp-[a-z0-9\-]+)',
            r'project%3D(qwiklabs-gcp-[a-z0-9\-]+)',
            r'(qwiklabs-gcp-[a-z0-9\-]+)',
        ]:
            m = re.search(pat, full)
            if m:
                result["project_id"] = m.group(1)
                break

        # Email
        m = re.search(r'(student-[\w\-]+@qwiklabs\.net)', full, re.I)
        if m:
            result["student_email"] = urllib.parse.unquote(m.group(1))

        # SSO token principal (?token=XXXX dans l'URL de base, pas dans le fallback)
        # On cherche dans l'URL ORIGINALE (pas decodee) pour eviter la confusion
        # avec les tokens dans les parametres imbriques
        orig = text
        # Le token= de premier niveau (dans skills.google/google_sso?token=)
        m = re.search(r'[?&]token=([A-Za-z0-9_\-\.~]{20,})', orig)
        if m:
            result["sso_token"] = urllib.parse.unquote(m.group(1))
            logger.info("SSO token trouve: ...%s", result["sso_token"][-8:])

        # display_token (encode dans le fallback)
        m = re.search(r'display_token[=%]+([A-Za-z0-9_\-\.~]{20,})', full)
        if m:
            result["display_token"] = urllib.parse.unquote(m.group(1))
            logger.info("display_token trouve: ...%s", result["display_token"][-8:])

        if result["project_id"]:
            result["type"] = "sso_url"
            logger.info("Input: SSO URL project=%s email=%s sso_token=%s",
                        result["project_id"], result["student_email"],
                        "oui" if result["sso_token"] else "non")
            return result

    logger.error("Format non reconnu")
    return None

# ═══════════════════════════════════════════════════════════
#  AUTHENTIFICATION GCP
# ═══════════════════════════════════════════════════════════

HEADERS = {
    "User-Agent": ("Mozilla/5.0 (X11; Linux x86_64) "
                   "AppleWebKit/537.36 (KHTML, like Gecko) "
                   "Chrome/124.0.0.0 Safari/537.36"),
    "Accept":          "text/html,application/xhtml+xml,application/json,*/*",
    "Accept-Language": "en-US,en;q=0.9",
    "Accept-Encoding": "gzip, deflate, br",
}


async def _validate_token(token: str) -> bool:
    try:
        async with aiohttp.ClientSession() as s:
            async with s.get("https://oauth2.googleapis.com/tokeninfo",
                             params={"access_token": token},
                             timeout=aiohttp.ClientTimeout(total=10)) as r:
                if r.status == 200:
                    d = await r.json()
                    logger.info("Token GCP valide, email=%s scope=%s",
                                d.get("email","?"), d.get("scope","?")[:50])
                    return True
                logger.warning("tokeninfo status=%s", r.status)
                return False
    except Exception as e:
        logger.warning("_validate_token: %s", e)
        return False


async def _token_from_sso_url(lab_info: dict) -> Optional[str]:
    """
    Flux principal : suivre le lien skills.google/google_sso
    Ce lien, quand suivi avec les bons cookies/headers, redirige vers
    accounts.google.com puis vers console.cloud.google.com.
    Les cookies de session contiennent ensuite le token GCP.

    Strategie :
    1. Suivre le lien SSO avec redirections (obtenir les cookies Google)
    2. Utiliser les cookies pour appeler l'API metadata / token endpoint
    3. Si le token SSO est present, l'echanger via oauth2.googleapis.com
    """
    raw_url      = lab_info.get("raw_url", "")
    sso_token    = lab_info.get("sso_token", "")
    display_token= lab_info.get("display_token", "")
    project_id   = lab_info.get("project_id", "")
    email        = lab_info.get("student_email", "")

    timeout = aiohttp.ClientTimeout(total=45)

    connector = aiohttp.TCPConnector(ssl=True)
    async with aiohttp.ClientSession(
        headers=HEADERS,
        cookie_jar=aiohttp.CookieJar(),
        connector=connector
    ) as session:

        # ── Etape 1 : Suivre le lien SSO complet ─────────────────
        logger.info("Suivi du lien SSO...")
        try:
            async with session.get(
                raw_url,
                allow_redirects=True,
                timeout=timeout
            ) as resp:
                final_url = str(resp.url)
                body      = await resp.text()
                logger.info("SSO final URL: %s", final_url[:120])
                logger.info("SSO status: %s", resp.status)

                # Chercher un access_token dans la reponse finale
                for pat in [
                    r'"access_token"\s*[=:]\s*["\']([^"\']+)["\']',
                    r'access_token[=:]([A-Za-z0-9_\-\.]{30,})',
                    r'(ya29\.[A-Za-z0-9_\-\.]{20,})',
                ]:
                    m = re.search(pat, body)
                    if m:
                        token = m.group(1)
                        logger.info("access_token trouve dans le body SSO")
                        if await _validate_token(token):
                            return token

                # Chercher dans les cookies apres la redirection
                for cookie in session.cookie_jar:
                    val = str(cookie.value) if cookie.value else ""
                    if val.startswith("ya29."):
                        logger.info("ya29 cookie trouve: key=%s", cookie.key)
                        if await _validate_token(val):
                            return val

        except Exception as e:
            logger.warning("Suivi SSO: %s", e)

        # ── Etape 2 : Echanger le SSO token via skills.google ────
        if sso_token:
            logger.info("Tentative echange SSO token via skills.google...")
            for exchange_url in [
                "https://www.skills.google/api/lab/v1/token",
                "https://www.skills.google/google_sso/exchange",
                "https://www.cloudskillsboost.google/api/v1/auth/gcp_token",
                "https://www.qwiklabs.com/api/v1/auth/gcp_token",
            ]:
                try:
                    # Essai GET avec le token en header
                    async with session.get(
                        exchange_url,
                        params={"token": sso_token, "project": project_id},
                        headers={**HEADERS,
                                 "X-Qwiklabs-Token": sso_token,
                                 "X-Lab-Token": sso_token,
                                 "Authorization": "Bearer " + sso_token},
                        timeout=aiohttp.ClientTimeout(total=20)
                    ) as r:
                        logger.info("Exchange GET %s → %s", exchange_url, r.status)
                        if r.status == 200:
                            try:
                                d = await r.json(content_type=None)
                                t = (d.get("access_token") or d.get("gcp_access_token")
                                     or d.get("token") or d.get("google_token"))
                                if t and await _validate_token(t):
                                    return t
                            except Exception:
                                body = await r.text()
                                m = re.search(r'(ya29\.[A-Za-z0-9_\-\.]{20,})', body)
                                if m and await _validate_token(m.group(1)):
                                    return m.group(1)

                    # Essai POST
                    async with session.post(
                        exchange_url,
                        json={"token": sso_token, "project_id": project_id,
                              "email": email},
                        headers={**HEADERS, "Content-Type": "application/json"},
                        timeout=aiohttp.ClientTimeout(total=20)
                    ) as r:
                        logger.info("Exchange POST %s → %s", exchange_url, r.status)
                        if r.status == 200:
                            try:
                                d = await r.json(content_type=None)
                                t = (d.get("access_token") or d.get("gcp_access_token")
                                     or d.get("token"))
                                if t and await _validate_token(t):
                                    return t
                            except Exception:
                                pass
                except Exception as e:
                    logger.warning("Exchange %s: %s", exchange_url, e)

        # ── Etape 3 : Utiliser le display_token ──────────────────
        if display_token:
            logger.info("Test du display_token comme access_token GCP...")
            if await _validate_token(display_token):
                return display_token

            # Essayer de l'echanger
            try:
                async with session.get(
                    "https://www.skills.google/display_in_context",
                    params={"display_token": display_token},
                    allow_redirects=True,
                    timeout=timeout
                ) as r:
                    body = await r.text()
                    m = re.search(r'(ya29\.[A-Za-z0-9_\-\.]{20,})', body)
                    if m and await _validate_token(m.group(1)):
                        return m.group(1)
                    # Chercher dans les cookies
                    for cookie in session.cookie_jar:
                        val = str(cookie.value) if cookie.value else ""
                        if val.startswith("ya29."):
                            if await _validate_token(val):
                                return val
            except Exception as e:
                logger.warning("display_token exchange: %s", e)

        # ── Etape 4 : Appel direct API GCP avec le SSO token ─────
        # Certains labs permettent d'utiliser directement le token Qwiklabs
        # comme Bearer sur l'API GCP (token de courte duree)
        if sso_token:
            logger.info("Test sso_token direct comme Bearer GCP...")
            if await _validate_token(sso_token):
                return sso_token

        logger.error("Toutes les strategies SSO ont echoue")
        return None


async def _token_from_service_account(sa_key: dict) -> Optional[str]:
    import time, base64
    try:
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import padding
        from cryptography.hazmat.backends import default_backend
    except ImportError:
        logger.error("Module 'cryptography' manquant")
        return None
    try:
        now     = int(time.time())
        header  = {"alg": "RS256", "typ": "JWT"}
        payload = {"iss": sa_key["client_email"],
                   "scope": "https://www.googleapis.com/auth/cloud-platform",
                   "aud": "https://oauth2.googleapis.com/token",
                   "iat": now, "exp": now + 3600}
        b64u = lambda d: base64.urlsafe_b64encode(json.dumps(d).encode()).rstrip(b"=").decode()
        msg  = b64u(header) + "." + b64u(payload)
        pk   = serialization.load_pem_private_key(sa_key["private_key"].encode(),
                                                   password=None, backend=default_backend())
        sig  = pk.sign(msg.encode(), padding.PKCS1v15(), hashes.SHA256())
        jwt  = msg + "." + base64.urlsafe_b64encode(sig).rstrip(b"=").decode()
        async with aiohttp.ClientSession() as s:
            async with s.post("https://oauth2.googleapis.com/token",
                              data={"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                                    "assertion": jwt},
                              timeout=aiohttp.ClientTimeout(total=20)) as r:
                d = await r.json()
                if r.status == 200:
                    logger.info("Token SA JWT OK")
                    return d["access_token"]
                logger.error("SA JWT: %s", d)
    except Exception as e:
        logger.error("SA JWT: %s", e, exc_info=True)
    return None


async def _get_access_token(lab_info: dict) -> Optional[str]:
    itype = lab_info.get("type")
    if itype == "access_token":
        t = lab_info.get("access_token", "")
        return t if await _validate_token(t) else None
    if itype == "service_account":
        return await _token_from_service_account(lab_info["sa_key"])
    if itype == "sso_url":
        return await _token_from_sso_url(lab_info)
    return None


async def _gcp_get(session, url, token):
    async with session.get(url, headers={"Authorization": "Bearer " + token},
                           timeout=aiohttp.ClientTimeout(total=30)) as r:
        try: data = await r.json(content_type=None)
        except: data = {"raw": await r.text()}
        return {"status": r.status, "data": data, "ok": r.status < 300}

async def _gcp_post(session, url, token, body):
    async with session.post(url,
                            headers={"Authorization": "Bearer " + token,
                                     "Content-Type": "application/json"},
                            json=body, timeout=aiohttp.ClientTimeout(total=120)) as r:
        try: data = await r.json(content_type=None)
        except: data = {"raw": await r.text()}
        return {"status": r.status, "data": data, "ok": r.status < 300}


ERR_TOKEN = (
    "Impossible d'obtenir un token GCP depuis ce lien.\n\n"
    "Le lien a peut-etre expire ou le lab est ferme.\n\n"
    "*Alternative rapide :*\n"
    "Dans la console GCP du lab → Cloud Shell `>_` → tape :\n"
    "`gcloud auth print-access-token`\n\n"
    "Envoie ensuite :\n"
    "```\nProject ID: qwiklabs-gcp-...\nToken: ya29.xxxxx\n```"
)


async def authenticate_gcp(lab_info: dict) -> dict:
    project_id = lab_info.get("project_id")
    if not project_id:
        return {"success": False, "error": "project_id introuvable dans le lien."}

    access_token = await _get_access_token(lab_info)
    if not access_token:
        return {"success": False, "error": ERR_TOKEN}

    lab_info["_access_token"] = access_token

    async with aiohttp.ClientSession() as session:
        result = await _gcp_get(session,
            "https://cloudresourcemanager.googleapis.com/v1/projects/" + project_id,
            access_token)
        if not result["ok"]:
            err = result["data"].get("error", {}).get("message", str(result["data"])[:200])
            return {"success": False, "error": "Acces refuse au projet GCP:\n" + err}
        logger.info("Projet GCP confirme: %s", result["data"].get("name", project_id))
        await _gcp_post(session,
            "https://serviceusage.googleapis.com/v1/projects/"
            + project_id + "/services/run.googleapis.com:enable",
            access_token, {})
    return {"success": True}


# ═══════════════════════════════════════════════════════════
#  DEPLOIEMENT CLOUD RUN
# ═══════════════════════════════════════════════════════════

async def deploy_vless_service(lab_info: dict) -> dict:
    project_id   = lab_info["project_id"]
    access_token = lab_info.get("_access_token", "")
    region, svc  = CLOUDRUN_REGION, CLOUDRUN_SERVICE_NAME
    if not access_token:
        return {"success": False, "error": "Token manquant"}

    base = ("https://" + region + "-run.googleapis.com"
            "/apis/serving.knative.dev/v1/namespaces/" + project_id + "/services")

    async with aiohttp.ClientSession() as session:
        check = await _gcp_get(session, base + "/" + svc, access_token)
        if check["ok"]:
            url = check["data"].get("status", {}).get("url", "")
            if url:
                db_save_project(project_id, url, region)
                return {"success": True, "service_url": url, "project_id": project_id}

        service_body = {
            "apiVersion": "serving.knative.dev/v1", "kind": "Service",
            "metadata": {"name": svc, "namespace": project_id,
                         "annotations": {"run.googleapis.com/ingress": "all"}},
            "spec": {"template": {
                "metadata": {"annotations": {
                    "autoscaling.knative.dev/maxScale": "10",
                    "run.googleapis.com/execution-environment": "gen1"}},
                "spec": {"containerConcurrency": 80, "containers": [{
                    "image": CLOUDRUN_IMAGE,
                    "ports": [{"containerPort": 8080}],
                    "env": [{"name": "UUID",    "value": VLESS_UUID},
                            {"name": "WS_PATH", "value": VLESS_PATH}],
                    "resources": {"limits": {"cpu": "1000m", "memory": "256Mi"}}}]}},
                "traffic": [{"percent": 100, "latestRevision": True}]}}

        create = await _gcp_post(session, base, access_token, service_body)
        if not create["ok"]:
            err = create["data"].get("error", {}).get("message", str(create["data"])[:300])
            return {"success": False, "error": "Echec Cloud Run:\n" + err}

        iam = ("https://" + region + "-run.googleapis.com/v1/projects/"
               + project_id + "/locations/" + region + "/services/" + svc + ":setIamPolicy")
        await _gcp_post(session, iam, access_token,
                        {"policy": {"bindings": [{"role": "roles/run.invoker",
                                                  "members": ["allUsers"]}]}})

        for i in range(18):
            await asyncio.sleep(5)
            poll = await _gcp_get(session, base + "/" + svc, access_token)
            if poll["ok"]:
                conds = poll["data"].get("status", {}).get("conditions", [])
                ready = next((c for c in conds if c.get("type") == "Ready"), None)
                if ready and ready.get("status") == "True":
                    url = poll["data"].get("status", {}).get("url", "")
                    db_save_project(project_id, url, region)
                    return {"success": True, "service_url": url, "project_id": project_id}
            logger.info("Attente %d/18...", i + 1)

        return {"success": False, "error": "Timeout: service non demarre en 90s"}


# ═══════════════════════════════════════════════════════════
#  VLESS
# ═══════════════════════════════════════════════════════════

def generate_vless_link(service_url: str) -> str:
    host = service_url.replace("https://", "").replace("http://", "").rstrip("/")
    path = urllib.parse.quote(VLESS_PATH, safe="")
    return ("vless://" + VLESS_UUID + "@" + host + ":" + str(VLESS_PORT)
            + "?path=" + path + "&security=tls&encryption=none"
            + "&host=" + host + "&type=ws&sni=" + host + "#KIGHMU")

def get_expiry_time():
    return (datetime.utcnow() + timedelta(hours=3)).strftime("%Y-%m-%d %H:%M UTC")


# ═══════════════════════════════════════════════════════════
#  HANDLERS TELEGRAM
# ═══════════════════════════════════════════════════════════

HELP_TEXT = (
    "*Comment utiliser le bot*\n\n"
    "*Methode principale :*\n"
    "Colle simplement le lien du lab depuis Skills Boost.\n"
    "Il ressemble a :\n"
    "`https://www.skills.google/google_sso?...token=...`\n\n"
    "*Methode alternative (si le lien ne marche pas) :*\n"
    "1. Console GCP → Cloud Shell `>_`\n"
    "2. Tape : `gcloud auth print-access-token`\n"
    "3. Envoie :\n"
    "```\nProject ID: qwiklabs-gcp-...\nToken: ya29.xxxxx\n```\n\n"
    "*Methode SA JSON :*\n"
    "Colle le contenu du fichier `.json` de service account.\n\n"
    "*Temps :* 5–10s si service existant · 60–90s si nouveau deploiement"
)


async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "*Bonjour " + update.effective_user.first_name + " !*\n\n"
        "Envoie-moi le lien de ton lab *Google Cloud Skills Boost* "
        "et je genere ton lien VLESS automatiquement.\n\n"
        "Tape /help pour plus de details.",
        parse_mode="Markdown")

async def cmd_help(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(HELP_TEXT, parse_mode="Markdown")

async def cmd_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "*Etat*\nBot : En ligne\nLiens actifs : " + str(db_active_count()) + "\n"
        "UUID : `" + VLESS_UUID + "`\nPath : `" + VLESS_PATH + "`",
        parse_mode="Markdown")


def _looks_like_input(text: str) -> bool:
    return any(x in text.lower() for x in [
        "skills.google", "qwiklabs", "console.cloud.google",
        "accounts.google.com", '"private_key"', "ya29.",
        "project id", "project_id", "token:"])


async def handle_link(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = update.message.text.strip()
    if not _looks_like_input(text):
        await update.message.reply_text(
            "Lien non reconnu. Tape /help pour voir les formats acceptes.",
            parse_mode="Markdown")
        return

    msg = await update.message.reply_text(
        "*Traitement en cours...*\n\nAnalyse du lien...",
        parse_mode="Markdown")

    try:
        lab_info = parse_lab_input(text)
        if not lab_info:
            await msg.edit_text("Format non reconnu.\n\n" + HELP_TEXT, parse_mode="Markdown")
            return

        if not lab_info.get("project_id"):
            await msg.edit_text(
                "*Project ID introuvable*\n\nLe lien semble incomplet. Verifie qu'il est complet.",
                parse_mode="Markdown")
            return

        await msg.edit_text(
            "*Traitement en cours...*\n\n"
            "Lien analyse ✅\n"
            "Projet : `" + lab_info["project_id"] + "`\n"
            "Connexion GCP en cours...",
            parse_mode="Markdown")

        auth = await authenticate_gcp(lab_info)
        if not auth["success"]:
            await msg.edit_text(
                "*Echec d'authentification GCP*\n\n" + auth["error"],
                parse_mode="Markdown")
            return

        await msg.edit_text(
            "*Traitement en cours...*\n\n"
            "Lien analyse ✅\n"
            "GCP connecte ✅\n"
            "Deploiement VLESS en cours...\n"
            "_(60–90s si premier deploiement)_",
            parse_mode="Markdown")

        service = await deploy_vless_service(lab_info)
        if not service["success"]:
            await msg.edit_text(
                "*Echec Cloud Run*\n\n`" + service["error"] + "`",
                parse_mode="Markdown")
            return

        vless  = generate_vless_link(service["service_url"])
        expiry = get_expiry_time()
        db_save_link(update.message.from_user.id, vless, lab_info["project_id"], expiry)

        await msg.edit_text(
            "*Lien VLESS genere !* ✅\n\n"
            "`" + vless + "`\n\n"
            "Projet : `" + lab_info["project_id"] + "`\n"
            "Region : `" + CLOUDRUN_REGION + "`\n"
            "Expire : `" + expiry + "`\n\n"
            "_Copie et sauvegarde ce lien !_",
            parse_mode="Markdown",
            reply_markup=InlineKeyboardMarkup([[
                InlineKeyboardButton("Nouveau lien", callback_data="new"),
                InlineKeyboardButton("Statut", callback_data="status")
            ]]))

    except Exception as e:
        logger.error("handle_link: %s", e, exc_info=True)
        await msg.edit_text("*Erreur inattendue*\n\n`" + str(e) + "`", parse_mode="Markdown")


async def button_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query; await q.answer()
    if q.data == "new":
        await q.edit_message_text(
            "Envoie ton nouveau lien Skills Boost.\n/help pour la procedure.")
    elif q.data == "status":
        await q.edit_message_text(
            "*Statut*\n\nLiens actifs : " + str(db_active_count()),
            parse_mode="Markdown")


def main():
    init_db()
    app = Application.builder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start",  cmd_start))
    app.add_handler(CommandHandler("help",   cmd_help))
    app.add_handler(CommandHandler("status", cmd_status))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_link))
    app.add_handler(CallbackQueryHandler(button_callback))
    logger.info("Bot VLESS demarre")
    app.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == "__main__":
    main()
