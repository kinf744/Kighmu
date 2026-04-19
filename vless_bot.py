#!/usr/bin/env python3
"""
Bot Telegram VLESS Generator — Fichier unique
UUID fixe : 29580a0a-088f-4e5e-8e67-008174c2e451
Path fixe  : /KIGHMU
Auth       : Service Account Key JSON OU credentials lab (email + password)
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

# ═══════════════════════════════════════════════════════════
#  CONFIGURATION
# ═══════════════════════════════════════════════════════════

BOT_TOKEN             = "TON_BOT_TOKEN_ICI"
ADMIN_IDS             = []

VLESS_UUID            = "29580a0a-088f-4e5e-8e67-008174c2e451"
VLESS_PATH            = "/KIGHMU"
VLESS_PORT            = 443

CLOUDRUN_IMAGE        = "ghcr.io/teddysun/xray:latest"
CLOUDRUN_REGION       = "us-central1"
CLOUDRUN_SERVICE_NAME = "vless-server"

DB_PATH               = "/var/lib/vless-bot/vless_bot.db"

# ═══════════════════════════════════════════════════════════
#  LOGGING
# ═══════════════════════════════════════════════════════════

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
#  BASE DE DONNEES SQLite
# ═══════════════════════════════════════════════════════════

def init_db():
    import os
    os.makedirs("/var/lib/vless-bot", exist_ok=True)
    os.makedirs("/var/log/vless-bot", exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS active_links (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id    INTEGER,
            vless_link TEXT,
            project_id TEXT,
            expiry     TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS projects (
            project_id  TEXT PRIMARY KEY,
            service_url TEXT,
            region      TEXT,
            created_at  TEXT DEFAULT (datetime('now'))
        )
    """)
    conn.commit()
    conn.close()

def db_save_link(user_id, vless_link, project_id, expiry):
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "INSERT INTO active_links (user_id, vless_link, project_id, expiry) VALUES (?,?,?,?)",
        (user_id, vless_link, project_id, expiry)
    )
    conn.commit()
    conn.close()

def db_active_count() -> int:
    conn = sqlite3.connect(DB_PATH)
    count = conn.execute(
        "SELECT COUNT(*) FROM active_links WHERE expiry > datetime('now')"
    ).fetchone()[0]
    conn.close()
    return count

def db_save_project(project_id, service_url, region):
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "INSERT OR REPLACE INTO projects (project_id, service_url, region) VALUES (?,?,?)",
        (project_id, service_url, region)
    )
    conn.commit()
    conn.close()

# ═══════════════════════════════════════════════════════════
#  PARSER LE MESSAGE DE L'UTILISATEUR
#
#  FORMAT ATTENDU (copier-coller depuis le panneau lab) :
#
#  Option A — Credentials bruts :
#    Project ID: qwiklabs-gcp-04-xxxx
#    Username: student-01-xxxx@qwiklabs.net
#    Password: AbCdEfGhIjKl
#
#  Option B — Service Account Key JSON (contenu brut du fichier)
#
#  Option C — access_token brut (ya.xxx... ou eyJ...)
# ═══════════════════════════════════════════════════════════

def parse_lab_input(text: str) -> Optional[dict]:
    """
    Detecte et parse les 3 formats d'entree acceptes.
    Retourne un dict avec les cles disponibles.
    """
    result = {
        "type":          None,   # "credentials" | "service_account" | "access_token"
        "project_id":    None,
        "student_email": None,
        "password":      None,
        "sa_key":        None,
        "access_token":  None,
    }

    text_stripped = text.strip()

    # ── Option B : Service Account Key JSON ──────────────────
    if text_stripped.startswith("{") and '"type"' in text_stripped:
        try:
            key = json.loads(text_stripped)
            if key.get("type") == "service_account":
                result["type"]       = "service_account"
                result["project_id"] = key.get("project_id")
                result["sa_key"]     = key
                logger.info("Input detecte : Service Account JSON (project=%s)", result["project_id"])
                return result
        except json.JSONDecodeError:
            pass

    # ── Option C : access_token brut (ya29.xxx ou eyJ...) ────
    if re.match(r'^(ya29\.[A-Za-z0-9_\-]{20,}|eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+)$',
                text_stripped):
        result["type"]         = "access_token"
        result["access_token"] = text_stripped
        # Pas de project_id ici — l'utilisateur doit aussi l'envoyer
        logger.info("Input detecte : access_token brut")
        return result

    # ── Option A : Credentials texte du panneau lab ──────────
    # Project ID
    m = re.search(
        r'(?:project[_ ]?id|project)\s*[:\s]+\s*(qwiklabs-gcp-[a-z0-9\-]+)',
        text_stripped, re.IGNORECASE
    )
    if m:
        result["project_id"] = m.group(1)

    # Email
    m = re.search(r'(student-[\w\-]+@qwiklabs\.net)', text_stripped, re.IGNORECASE)
    if m:
        result["student_email"] = m.group(1)

    # Password / mot de passe (ligne apres "Password:")
    m = re.search(r'(?:password|mot de passe)\s*[:\s]+\s*(\S+)', text_stripped, re.IGNORECASE)
    if m:
        result["password"] = m.group(1)

    if result["project_id"] and result["student_email"] and result["password"]:
        result["type"] = "credentials"
        logger.info(
            "Input detecte : credentials lab (project=%s, email=%s)",
            result["project_id"], result["student_email"]
        )
        return result

    # ── Fallback : URL ancienne (project dans l'URL) ─────────
    m = re.search(r'project[=:](qwiklabs-gcp-[a-z0-9\-]+)', urllib.parse.unquote(text))
    if m:
        result["project_id"] = m.group(1)
        # Chercher un token dans l'URL
        tm = re.search(r'[?&]token=([A-Za-z0-9_\-\.]+)', text)
        if tm:
            result["access_token"] = tm.group(1)
            result["type"]         = "url_token"
            logger.info("Input detecte : URL avec token (project=%s)", result["project_id"])
            return result

    logger.error("Format non reconnu dans l'input")
    return None

# ═══════════════════════════════════════════════════════════
#  AUTHENTIFICATION GCP
# ═══════════════════════════════════════════════════════════

BROWSER_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (X11; Linux x86_64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
    "Accept": "application/json, text/html, */*",
    "Accept-Language": "fr-FR,fr;q=0.9,en;q=0.8",
}


async def _token_from_service_account(sa_key: dict) -> Optional[str]:
    """
    Genere un access_token Google via JWT signé depuis une Service Account Key JSON.
    Utilise l'endpoint oauth2.googleapis.com/token avec assertion JWT.
    """
    import time
    import base64
    import hashlib
    import hmac

    try:
        # Construire le JWT
        header  = {"alg": "RS256", "typ": "JWT"}
        now     = int(time.time())
        payload = {
            "iss":   sa_key["client_email"],
            "scope": "https://www.googleapis.com/auth/cloud-platform",
            "aud":   "https://oauth2.googleapis.com/token",
            "iat":   now,
            "exp":   now + 3600,
        }

        def b64url(data):
            return base64.urlsafe_b64encode(
                json.dumps(data).encode()
            ).rstrip(b"=").decode()

        msg = b64url(header) + "." + b64url(payload)

        # Signer avec la cle privee RSA
        try:
            from cryptography.hazmat.primitives import hashes, serialization
            from cryptography.hazmat.primitives.asymmetric import padding
            from cryptography.hazmat.backends import default_backend

            private_key = serialization.load_pem_private_key(
                sa_key["private_key"].encode(),
                password=None,
                backend=default_backend()
            )
            signature = private_key.sign(msg.encode(), padding.PKCS1v15(), hashes.SHA256())
            sig_b64   = base64.urlsafe_b64encode(signature).rstrip(b"=").decode()
            jwt_token = msg + "." + sig_b64
        except ImportError:
            logger.error("Module 'cryptography' manquant — pip install cryptography")
            return None

        # Echanger le JWT contre un access_token
        async with aiohttp.ClientSession() as session:
            async with session.post(
                "https://oauth2.googleapis.com/token",
                data={
                    "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                    "assertion":  jwt_token,
                },
                timeout=aiohttp.ClientTimeout(total=20)
            ) as resp:
                data = await resp.json()
                if resp.status == 200 and "access_token" in data:
                    logger.info("access_token obtenu via Service Account JWT")
                    return data["access_token"]
                else:
                    logger.error("Erreur SA JWT: %s", data)
                    return None

    except Exception as e:
        logger.error("_token_from_service_account: %s", e, exc_info=True)
        return None


async def _token_from_credentials(email: str, password: str) -> Optional[str]:
    """
    Obtient un access_token via le flux OAuth2 Google Identity
    en utilisant l'email et le mot de passe du compte temporaire Qwiklabs.
    Utilise l'API Google Sign-In (identitytoolkit).
    """
    GOOGLE_API_KEY = "AIzaSyC_FQ5oDNBCWHaBL3BV_e11MlqGJWRJH3g"  # cle publique Firebase/GCP labs

    try:
        async with aiohttp.ClientSession(headers=BROWSER_HEADERS) as session:

            # Etape 1 : signin avec email/password via identitytoolkit
            async with session.post(
                "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword",
                params={"key": GOOGLE_API_KEY},
                json={
                    "email":             email,
                    "password":          password,
                    "returnSecureToken": True,
                },
                timeout=aiohttp.ClientTimeout(total=20)
            ) as resp:
                data = await resp.json()
                if resp.status != 200:
                    logger.error("identitytoolkit signIn error: %s", data)
                    return None

                id_token = data.get("idToken")
                if not id_token:
                    logger.error("idToken absent dans la reponse identitytoolkit")
                    return None
                logger.info("idToken Firebase obtenu pour %s", email)

            # Etape 2 : echanger le Firebase idToken contre un access_token Google
            async with session.post(
                "https://oauth2.googleapis.com/token",
                data={
                    "grant_type":        "urn:ietf:params:oauth:grant-type:token-exchange",
                    "subject_token":     id_token,
                    "subject_token_type": "urn:ietf:params:oauth:token-type:id_token",
                    "audience":          "//iam.googleapis.com/projects/-/serviceAccounts",
                    "requested_token_type": "urn:ietf:params:oauth:token-type:access_token",
                    "scope":             "https://www.googleapis.com/auth/cloud-platform",
                },
                timeout=aiohttp.ClientTimeout(total=20)
            ) as resp2:
                data2 = await resp2.json()
                if resp2.status == 200 and "access_token" in data2:
                    logger.info("access_token obtenu via token exchange Firebase→GCP")
                    return data2["access_token"]
                else:
                    # Fallback : essayer d'utiliser directement idToken comme Bearer
                    logger.warning(
                        "Token exchange echoue (%s) — test du idToken directement: %s",
                        resp2.status, str(data2)[:200]
                    )
                    # Certains labs GCP acceptent le Firebase idToken comme Bearer GCP
                    async with session.get(
                        "https://cloudresourcemanager.googleapis.com/v1/projects",
                        headers={"Authorization": "Bearer " + id_token},
                        timeout=aiohttp.ClientTimeout(total=15)
                    ) as resp3:
                        if resp3.status == 200:
                            logger.info("idToken Firebase accepte directement comme Bearer GCP")
                            return id_token
                        else:
                            logger.error(
                                "idToken refuse par GCP aussi: %s", await resp3.text()
                            )
                            return None

    except Exception as e:
        logger.error("_token_from_credentials: %s", e, exc_info=True)
        return None


async def _validate_access_token(token: str) -> bool:
    """Verifie qu'un token est valide via tokeninfo."""
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(
                "https://oauth2.googleapis.com/tokeninfo",
                params={"access_token": token},
                timeout=aiohttp.ClientTimeout(total=10)
            ) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    logger.info("Token valide, email=%s", data.get("email", "?"))
                    return True
                return False
    except Exception:
        return False


async def _get_access_token(lab_info: dict) -> Optional[str]:
    """
    Dispatcher : obtient un access_token selon le type de credentials fourni.
    """
    input_type = lab_info.get("type")

    # Access token direct (deja valide ?)
    if input_type in ("access_token", "url_token"):
        token = lab_info.get("access_token")
        if token and await _validate_access_token(token):
            return token
        logger.warning("Token direct invalide ou expire")
        return None

    # Service Account JSON
    if input_type == "service_account":
        return await _token_from_service_account(lab_info["sa_key"])

    # Credentials email + password
    if input_type == "credentials":
        return await _token_from_credentials(
            lab_info["student_email"],
            lab_info["password"]
        )

    logger.error("Type d'input inconnu: %s", input_type)
    return None


async def _gcp_get(session: aiohttp.ClientSession, url: str, token: str) -> dict:
    """GET vers l'API GCP REST."""
    async with session.get(
        url,
        headers={"Authorization": "Bearer " + token},
        timeout=aiohttp.ClientTimeout(total=30)
    ) as resp:
        try:
            data = await resp.json(content_type=None)
        except Exception:
            data = {"raw": await resp.text()}
        return {"status": resp.status, "data": data, "ok": resp.status < 300}


async def _gcp_post(session: aiohttp.ClientSession, url: str, token: str, body: dict) -> dict:
    """POST vers l'API GCP REST."""
    async with session.post(
        url,
        headers={
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json"
        },
        json=body,
        timeout=aiohttp.ClientTimeout(total=120)
    ) as resp:
        try:
            data = await resp.json(content_type=None)
        except Exception:
            data = {"raw": await resp.text()}
        return {"status": resp.status, "data": data, "ok": resp.status < 300}


async def authenticate_gcp(lab_info: dict) -> dict:
    """
    Authentification via API REST Google uniquement.
    """
    project_id = lab_info.get("project_id")

    if not project_id:
        return {
            "success": False,
            "error": (
                "project_id introuvable.\n"
                "Assure-toi d'inclure la ligne 'Project ID: qwiklabs-gcp-...' dans ton message."
            )
        }

    access_token = await _get_access_token(lab_info)
    if not access_token:
        return {
            "success": False,
            "error": (
                "Impossible d'obtenir un token Google valide.\n\n"
                "*Comment corriger ?*\n"
                "Dans le panneau du lab Skills Boost, clique sur "
                "*'Ouvrir la console Google'* puis copie-colle les 3 lignes :\n\n"
                "```\n"
                "Project ID: qwiklabs-gcp-...\n"
                "Username: student-xx-...@qwiklabs.net\n"
                "Password: xxxxxxxxxxxx\n"
                "```\n\n"
                "OU colle directement le contenu du fichier *Service Account Key JSON*."
            )
        }

    lab_info["_access_token"] = access_token

    # Verifier l'acces au projet via Cloud Resource Manager
    async with aiohttp.ClientSession() as session:
        result = await _gcp_get(
            session,
            "https://cloudresourcemanager.googleapis.com/v1/projects/" + project_id,
            access_token
        )
        if not result["ok"]:
            err = result["data"].get("error", {}).get("message", str(result["data"])[:200])
            return {"success": False, "error": "Acces refuse au projet GCP:\n" + err}

        logger.info("Projet GCP confirme: %s", result["data"].get("name", project_id))

        # Activer l'API Cloud Run
        enable = await _gcp_post(
            session,
            "https://serviceusage.googleapis.com/v1/projects/"
            + project_id + "/services/run.googleapis.com:enable",
            access_token,
            {}
        )
        logger.info("Activation Cloud Run API: status=%s", enable["status"])

    return {"success": True}


# ═══════════════════════════════════════════════════════════
#  DEPLOIEMENT CLOUD RUN — 100% API REST
# ═══════════════════════════════════════════════════════════

async def deploy_vless_service(lab_info: dict) -> dict:
    """
    Deploie ou retrouve le service VLESS sur Cloud Run via API REST.
    """
    project_id   = lab_info["project_id"]
    access_token = lab_info.get("_access_token", "")
    region       = CLOUDRUN_REGION
    svc_name     = CLOUDRUN_SERVICE_NAME

    if not access_token:
        return {"success": False, "error": "Token d'acces manquant"}

    knative_base = (
        "https://" + region + "-run.googleapis.com"
        "/apis/serving.knative.dev/v1"
        "/namespaces/" + project_id + "/services"
    )

    async with aiohttp.ClientSession() as session:

        # 1. Verifier si le service existe deja
        check = await _gcp_get(session, knative_base + "/" + svc_name, access_token)

        if check["ok"]:
            svc_url = check["data"].get("status", {}).get("url", "")
            if svc_url:
                logger.info("Service existant trouve: %s", svc_url)
                db_save_project(project_id, svc_url, region)
                return {"success": True, "service_url": svc_url, "project_id": project_id}

        # 2. Creer le service
        logger.info("Creation du service Cloud Run: %s", svc_name)
        service_body = {
            "apiVersion": "serving.knative.dev/v1",
            "kind": "Service",
            "metadata": {
                "name": svc_name,
                "namespace": project_id,
                "annotations": {"run.googleapis.com/ingress": "all"}
            },
            "spec": {
                "template": {
                    "metadata": {
                        "annotations": {
                            "autoscaling.knative.dev/maxScale": "10",
                            "run.googleapis.com/execution-environment": "gen1"
                        }
                    },
                    "spec": {
                        "containerConcurrency": 80,
                        "containers": [{
                            "image": CLOUDRUN_IMAGE,
                            "ports": [{"containerPort": 8080}],
                            "env": [
                                {"name": "UUID",    "value": VLESS_UUID},
                                {"name": "WS_PATH", "value": VLESS_PATH}
                            ],
                            "resources": {
                                "limits": {"cpu": "1000m", "memory": "256Mi"}
                            }
                        }]
                    }
                },
                "traffic": [{"percent": 100, "latestRevision": True}]
            }
        }

        create = await _gcp_post(session, knative_base, access_token, service_body)
        if not create["ok"]:
            err = create["data"].get("error", {}).get("message", str(create["data"])[:300])
            return {"success": False, "error": "Echec creation service Cloud Run:\n" + err}

        # 3. Autoriser l'acces public (allUsers)
        iam_url = (
            "https://" + region + "-run.googleapis.com/v1"
            "/projects/" + project_id
            + "/locations/" + region
            + "/services/" + svc_name + ":setIamPolicy"
        )
        await _gcp_post(
            session, iam_url, access_token,
            {"policy": {"bindings": [{
                "role": "roles/run.invoker",
                "members": ["allUsers"]
            }]}}
        )

        # 4. Attendre que le service soit pret (max 90 secondes)
        logger.info("Attente demarrage du service (max 90s)...")
        for attempt in range(18):
            await asyncio.sleep(5)
            poll = await _gcp_get(session, knative_base + "/" + svc_name, access_token)
            if poll["ok"]:
                conditions = poll["data"].get("status", {}).get("conditions", [])
                ready_cond = next(
                    (c for c in conditions if c.get("type") == "Ready"), None
                )
                if ready_cond and ready_cond.get("status") == "True":
                    svc_url = poll["data"].get("status", {}).get("url", "")
                    logger.info("Service pret: %s", svc_url)
                    db_save_project(project_id, svc_url, region)
                    return {"success": True, "service_url": svc_url, "project_id": project_id}
                logger.info("Tentative %d/18 — service pas encore pret...", attempt + 1)

        return {"success": False, "error": "Timeout: service Cloud Run non demarre en 90s"}


# ═══════════════════════════════════════════════════════════
#  GENERATION DU LIEN VLESS
# ═══════════════════════════════════════════════════════════

def generate_vless_link(service_url: str) -> str:
    host         = service_url.replace("https://", "").replace("http://", "").rstrip("/")
    encoded_path = urllib.parse.quote(VLESS_PATH, safe="")
    return (
        "vless://" + VLESS_UUID + "@" + host + ":" + str(VLESS_PORT)
        + "?path=" + encoded_path
        + "&security=tls"
        + "&encryption=none"
        + "&host=" + host
        + "&type=ws"
        + "&sni=" + host
        + "#KIGHMU"
    )

def get_expiry_time() -> str:
    return (datetime.utcnow() + timedelta(hours=3)).strftime("%Y-%m-%d %H:%M UTC")


# ═══════════════════════════════════════════════════════════
#  HANDLERS TELEGRAM
# ═══════════════════════════════════════════════════════════

HELP_FORMAT = (
    "*Comment utiliser le bot*\n\n"
    "*Option 1 (recommandee) — Credentials du lab :*\n"
    "Dans le panneau du lab Skills Boost, copie les 3 lignes et envoie-les ici :\n\n"
    "```\n"
    "Project ID: qwiklabs-gcp-04-xxxxxxxxxxxxxxxx\n"
    "Username: student-01-xxxxxx@qwiklabs.net\n"
    "Password: AbCdEfGhIjKl\n"
    "```\n\n"
    "*Option 2 — Service Account Key JSON :*\n"
    "Colle le contenu du fichier JSON de la cle de compte de service.\n\n"
    "*Option 3 — access\\_token brut :*\n"
    "Si tu as recupere manuellement un token ya29.xxx depuis la console GCP,\n"
    "envoie-le accompagne du Project ID :\n\n"
    "```\n"
    "Project ID: qwiklabs-gcp-...\n"
    "Token: ya29.xxxx...\n"
    "```\n\n"
    "*Temps de generation :*\n"
    "Service existant : 5 a 10 secondes\n"
    "Nouveau deploiement : 60 a 90 secondes\n\n"
    "*Duree du lien :* 3h (expire avec le lab)"
)


async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    name = update.effective_user.first_name
    await update.message.reply_text(
        "*Bonjour " + name + " !*\n\n"
        "Envoie-moi les *credentials de ton lab Google Cloud Skills Boost* "
        "et je genere ton lien VLESS automatiquement.\n\n"
        "Tape /help pour voir les formats acceptes.\n\n"
        "*Commandes :*\n"
        "/start — Ce message\n"
        "/help  — Guide\n"
        "/status — Etat du bot",
        parse_mode="Markdown"
    )

async def cmd_help(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(HELP_FORMAT, parse_mode="Markdown")

async def cmd_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "*Etat du bot*\n\n"
        "Bot : En ligne\n"
        "Liens actifs : " + str(db_active_count()) + "\n"
        "UUID : `" + VLESS_UUID + "`\n"
        "Path : `" + VLESS_PATH + "`",
        parse_mode="Markdown"
    )


def _looks_like_lab_input(text: str) -> bool:
    """Verifie si le message ressemble a des credentials de lab."""
    indicators = [
        "qwiklabs-gcp-",
        "qwiklabs.net",
        "student-",
        "service_account",
        '"private_key"',
        "ya29.",
        "Project ID",
        "project_id",
        "Password",
        "Username",
    ]
    return any(ind.lower() in text.lower() for ind in indicators)


async def handle_link(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = update.message.text.strip()

    if not _looks_like_lab_input(text):
        await update.message.reply_text(
            "Message non reconnu.\n\n"
            "Envoie les *credentials de ton lab Skills Boost* (Project ID + Username + Password).\n"
            "Tape /help pour voir les formats acceptes.",
            parse_mode="Markdown"
        )
        return

    msg = await update.message.reply_text(
        "*Traitement en cours...*\n\nAnalyse des credentials...",
        parse_mode="Markdown"
    )

    try:
        # Etape 1 : Parser
        lab_info = parse_lab_input(text)
        if not lab_info:
            await msg.edit_text(
                "Impossible de lire les credentials.\n\n"
                + HELP_FORMAT,
                parse_mode="Markdown"
            )
            return

        if not lab_info.get("project_id"):
            await msg.edit_text(
                "*Project ID manquant*\n\n"
                "Ajoute la ligne `Project ID: qwiklabs-gcp-...` dans ton message.",
                parse_mode="Markdown"
            )
            return

        await msg.edit_text(
            "*Traitement en cours...*\n\n"
            "Credentials lus\n"
            "Projet : `" + lab_info["project_id"] + "`\n"
            "Connexion au projet GCP...",
            parse_mode="Markdown"
        )

        # Etape 2 : Auth
        auth = await authenticate_gcp(lab_info)
        if not auth["success"]:
            await msg.edit_text(
                "*Echec d'authentification GCP*\n\n" + auth["error"],
                parse_mode="Markdown"
            )
            return

        await msg.edit_text(
            "*Traitement en cours...*\n\n"
            "Credentials lus\n"
            "Projet GCP connecte\n"
            "Deploiement du service VLESS...\n"
            "_(peut prendre 60s si premier deploiement)_",
            parse_mode="Markdown"
        )

        # Etape 3 : Deploiement
        service = await deploy_vless_service(lab_info)
        if not service["success"]:
            await msg.edit_text(
                "*Echec du deploiement Cloud Run*\n\n`" + service["error"] + "`",
                parse_mode="Markdown"
            )
            return

        # Etape 4 : Generer le lien VLESS
        vless  = generate_vless_link(service["service_url"])
        expiry = get_expiry_time()
        db_save_link(update.message.from_user.id, vless, lab_info["project_id"], expiry)

        keyboard = [[
            InlineKeyboardButton("Nouveau lien", callback_data="new"),
            InlineKeyboardButton("Statut", callback_data="status")
        ]]

        await msg.edit_text(
            "*Lien VLESS genere !*\n\n"
            "`" + vless + "`\n\n"
            "Projet : `" + lab_info["project_id"] + "`\n"
            "Region : `" + CLOUDRUN_REGION + "`\n"
            "Expire : `" + expiry + "`\n\n"
            "Copie et sauvegarde ce lien !",
            parse_mode="Markdown",
            reply_markup=InlineKeyboardMarkup(keyboard)
        )

    except Exception as e:
        logger.error("handle_link error: %s", e, exc_info=True)
        await msg.edit_text(
            "*Erreur inattendue*\n\n`" + str(e) + "`",
            parse_mode="Markdown"
        )

async def button_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    if q.data == "new":
        await q.edit_message_text(
            "Envoie tes nouveaux credentials Google Cloud Skills Boost :\n\n"
            "```\nProject ID: qwiklabs-gcp-...\nUsername: student-...@qwiklabs.net\nPassword: ...\n```",
            parse_mode="Markdown"
        )
    elif q.data == "status":
        await q.edit_message_text(
            "*Statut*\n\nLiens actifs : " + str(db_active_count()),
            parse_mode="Markdown"
        )

# ═══════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════

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
