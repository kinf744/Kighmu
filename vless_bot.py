#!/usr/bin/env python3
"""
Bot Telegram VLESS Generator — Fichier unique
UUID fixe : 29580a0a-088f-4e5e-8e67-008174c2e451
Path fixe  : /KIGHMU
Auth       : 100% API REST Google (aucun appel gcloud)
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
#  PARSER LE LIEN GOOGLE / QWIKLABS
# ═══════════════════════════════════════════════════════════

def parse_google_link(url: str) -> Optional[dict]:
    try:
        full = urllib.parse.unquote(url)
        result = {
            "project_id":    None,
            "student_email": None,
            "auth_token":    None,
            "raw_url":       url
        }

        # project_id
        for pattern in [
            r'project[=:](qwiklabs-gcp-[a-z0-9-]+)',
            r'project%3D(qwiklabs-gcp-[a-z0-9-]+)',
        ]:
            m = re.search(pattern, full)
            if m:
                result["project_id"] = m.group(1)
                break

        # Email etudiant
        m = re.search(r'(student-\d+-[a-f0-9]+@qwiklabs\.net)', full)
        if m:
            result["student_email"] = m.group(1)

        # Token brut dans l'URL
        m = re.search(r'[?&]token=([A-Za-z0-9_\-\.]+)', url)
        if m:
            result["auth_token"] = m.group(1)

        if not result["project_id"]:
            logger.error("project_id introuvable dans le lien")
            return None

        logger.info(
            "Lien parse : project=%s | email=%s | token=%s chars",
            result["project_id"],
            result["student_email"],
            len(result["auth_token"]) if result["auth_token"] else 0
        )
        return result

    except Exception as e:
        logger.error("parse_google_link: %s", e, exc_info=True)
        return None

# ═══════════════════════════════════════════════════════════
#  AUTHENTIFICATION GCP — 100% API REST (sans gcloud)
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


async def _get_access_token(project_info: dict) -> Optional[str]:
    """
    Obtient un access_token Google valide depuis le lien Qwiklabs.
    Strategie :
      1. Verifier si le token brut est deja un access_token Google valide
      2. Suivre le flux SSO du lien pour recuperer les cookies / tokens
      3. Echanger via l'API Qwiklabs
    """
    raw_url    = project_info.get("raw_url", "")
    raw_token  = project_info.get("auth_token", "")

    if not raw_token:
        logger.error("Aucun token dans le lien")
        return None

    timeout = aiohttp.ClientTimeout(total=20)

    async with aiohttp.ClientSession(headers=BROWSER_HEADERS) as session:

        # ── Strategie 1 : token brut = access_token Google ? ─────────
        try:
            async with session.get(
                "https://oauth2.googleapis.com/tokeninfo",
                params={"access_token": raw_token},
                timeout=timeout
            ) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    logger.info(
                        "Token brut valide comme access_token Google (email=%s)",
                        data.get("email", "?")
                    )
                    return raw_token
                else:
                    body = await resp.text()
                    logger.info("Token brut non valide comme access_token: %s", body[:120])
        except Exception as e:
            logger.warning("tokeninfo check: %s", e)

        # ── Strategie 2 : suivre le lien SSO et extraire les tokens ──
        try:
            async with session.get(
                raw_url,
                allow_redirects=True,
                timeout=aiohttp.ClientTimeout(total=30)
            ) as resp:
                final_url  = str(resp.url)
                body_text  = await resp.text()
                logger.info("SSO final URL: %s", final_url[:100])

                # Chercher un access_token dans le body ou les cookies
                token_match = re.search(r'"access_token"\s*:\s*"([^"]+)"', body_text)
                if token_match:
                    token = token_match.group(1)
                    logger.info("access_token trouve dans la reponse SSO")
                    return token

                # Chercher dans les cookies
                for cookie in session.cookie_jar:
                    if "token" in cookie.key.lower() or "auth" in cookie.key.lower():
                        logger.info("Cookie auth trouve: %s", cookie.key)

        except Exception as e:
            logger.warning("Erreur SSO: %s", e)

        # ── Strategie 3 : API Qwiklabs exchange ───────────────────────
        for api_url in [
            "https://www.qwiklabs.com/api/v1/auth/token",
            "https://skills.google/api/v1/token",
        ]:
            try:
                async with session.post(
                    api_url,
                    json={"token": raw_token},
                    timeout=timeout
                ) as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        token = data.get("access_token") or data.get("google_token")
                        if token:
                            logger.info("access_token obtenu via %s", api_url)
                            return token
            except Exception as e:
                logger.warning("API exchange %s: %s", api_url, e)

    logger.error("Toutes les strategies d'obtention du token ont echoue")
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


async def authenticate_gcp(project_info: dict) -> dict:
    """
    Authentification via API REST Google uniquement.
    Aucun appel gcloud.
    """
    project_id = project_info["project_id"]

    # Recuperer l'access_token
    access_token = await _get_access_token(project_info)
    if not access_token:
        return {
            "success": False,
            "error": (
                "Impossible d'obtenir un token Google valide depuis ce lien.\n"
                "Verifie que le lien est complet et que le lab est encore actif."
            )
        }

    # Stocker le token pour les etapes suivantes
    project_info["_access_token"] = access_token

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

async def deploy_vless_service(project_info: dict) -> dict:
    """
    Deploie ou retrouve le service VLESS sur Cloud Run via API REST.
    Aucune dependance a gcloud.
    """
    project_id   = project_info["project_id"]
    access_token = project_info.get("_access_token", "")
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

        return {"success": False, "error": "Timeout: service Cloud Run non demarree en 90s"}

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

async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    name = update.effective_user.first_name
    await update.message.reply_text(
        "*Bonjour " + name + " !*\n\n"
        "Envoie-moi un lien *Google Cloud / Qwiklabs* "
        "et je genere ton lien VLESS automatiquement.\n\n"
        "*Commandes :*\n"
        "/start — Ce message\n"
        "/help  — Guide\n"
        "/status — Etat du bot",
        parse_mode="Markdown"
    )

async def cmd_help(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "*Guide d'utilisation*\n\n"
        "1. Va sur skills.google ou Qwiklabs\n"
        "2. Lance un lab Google Cloud\n"
        "3. Copie le lien de connexion complet\n"
        "4. Colle-le ici\n\n"
        "*Temps de generation :*\n"
        "Service existant  : 5 a 10 secondes\n"
        "Nouveau deploiement : 60 a 90 secondes\n\n"
        "*Duree du lien :* 3h (expire avec le lab)",
        parse_mode="Markdown"
    )

async def cmd_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "*Etat du bot*\n\n"
        "Bot : En ligne\n"
        "Liens actifs : " + str(db_active_count()) + "\n"
        "UUID : `" + VLESS_UUID + "`\n"
        "Path : `" + VLESS_PATH + "`",
        parse_mode="Markdown"
    )

async def handle_link(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = update.message.text.strip()

    if not any(d in text for d in ["skills.google", "qwiklabs", "console.cloud.google"]):
        await update.message.reply_text(
            "Lien non reconnu.\n\n"
            "Envoie un lien *skills.google* ou *console.cloud.google.com* complet.",
            parse_mode="Markdown"
        )
        return

    msg = await update.message.reply_text(
        "*Traitement en cours...*\n\nAnalyse du lien...",
        parse_mode="Markdown"
    )

    try:
        # Etape 1 : Parser
        project_info = parse_google_link(text)
        if not project_info:
            await msg.edit_text(
                "Impossible d'extraire le projet GCP.\n"
                "Verifie que le lien est complet.",
                parse_mode="Markdown"
            )
            return

        await msg.edit_text(
            "*Traitement en cours...*\n\n"
            "Lien analyse\n"
            "Projet : `" + project_info["project_id"] + "`\n"
            "Connexion au projet GCP...",
            parse_mode="Markdown"
        )

        # Etape 2 : Auth
        auth = await authenticate_gcp(project_info)
        if not auth["success"]:
            await msg.edit_text(
                "*Echec d'authentification GCP*\n\n`" + auth["error"] + "`",
                parse_mode="Markdown"
            )
            return

        await msg.edit_text(
            "*Traitement en cours...*\n\n"
            "Lien analyse\n"
            "Projet GCP connecte\n"
            "Deploiement du service VLESS...\n"
            "_(peut prendre 60s si premier deploiement)_",
            parse_mode="Markdown"
        )

        # Etape 3 : Deploiement
        service = await deploy_vless_service(project_info)
        if not service["success"]:
            await msg.edit_text(
                "*Echec du deploiement Cloud Run*\n\n`" + service["error"] + "`",
                parse_mode="Markdown"
            )
            return

        # Etape 4 : Generer le lien VLESS
        vless  = generate_vless_link(service["service_url"])
        expiry = get_expiry_time()
        db_save_link(update.message.from_user.id, vless, project_info["project_id"], expiry)

        keyboard = [[
            InlineKeyboardButton("Nouveau lien", callback_data="new"),
            InlineKeyboardButton("Statut", callback_data="status")
        ]]

        await msg.edit_text(
            "*Lien VLESS genere !*\n\n"
            "`" + vless + "`\n\n"
            "Projet : `" + project_info["project_id"] + "`\n"
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
        await q.edit_message_text("Envoie ton nouveau lien Google Cloud / Qwiklabs :")
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
