#!/usr/bin/env python3
"""
Bot Telegram VLESS Generator — Fichier unique
UUID fixe : 29580a0a-088f-4e5e-8e67-008174c2e451
Path fixe : /KIGHMU
"""

import re
import json
import asyncio
import sqlite3
import logging
import urllib.parse
from datetime import datetime, timedelta
from typing import Optional

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application, CommandHandler, MessageHandler,
    filters, ContextTypes, CallbackQueryHandler
)

# ═══════════════════════════════════════════════════════════
#  ⚙️  CONFIGURATION — Modifie uniquement cette section
# ═══════════════════════════════════════════════════════════

BOT_TOKEN          = "TON_BOT_TOKEN_ICI"        # Token @BotFather
ADMIN_IDS          = []                          # Ex: [123456789]

VLESS_UUID         = "29580a0a-088f-4e5e-8e67-008174c2e451"
VLESS_PATH         = "/KIGHMU"
VLESS_PORT         = 443

CLOUDRUN_IMAGE        = "ghcr.io/teddysun/xray:latest"
CLOUDRUN_REGION       = "us-central1"
CLOUDRUN_SERVICE_NAME = "vless-server"

DB_PATH            = "/var/lib/vless-bot/vless_bot.db"

# ═══════════════════════════════════════════════════════════
#  📋  LOGGING
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
#  🗄️  BASE DE DONNÉES SQLite
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

def db_get_project(project_id: str) -> dict:
    conn = sqlite3.connect(DB_PATH)
    row = conn.execute(
        "SELECT service_url, region, created_at FROM projects WHERE project_id=?",
        (project_id,)
    ).fetchone()
    conn.close()
    return {"service_url": row[0], "region": row[1], "created_at": row[2]} if row else {}

def db_save_project(project_id, service_url, region):
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "INSERT OR REPLACE INTO projects (project_id, service_url, region) VALUES (?,?,?)",
        (project_id, service_url, region)
    )
    conn.commit()
    conn.close()

# ═══════════════════════════════════════════════════════════
#  🔍  PARSER LE LIEN GOOGLE / QWIKLABS
# ═══════════════════════════════════════════════════════════

def parse_google_link(url: str) -> Optional[dict]:
    """
    Extrait depuis le lien Qwiklabs / skills.google :
    - project_id  (ex: qwiklabs-gcp-03-36d80b4db88d)
    - student_email
    - auth_token
    """
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

        # Email étudiant
        m = re.search(r'(student-\d+-[a-f0-9]+@qwiklabs\.net)', full)
        if m:
            result["student_email"] = m.group(1)

        # Token d'auth
        m = re.search(r'[?&]token=([A-Za-z0-9_\-]+)', url)
        if m:
            result["auth_token"] = m.group(1)

        if not result["project_id"]:
            logger.error("project_id introuvable dans le lien")
            return None

        logger.info(f"Lien parsé → project={result['project_id']} | email={result['student_email']}")
        return result

    except Exception as e:
        logger.error(f"parse_google_link: {e}", exc_info=True)
        return None

# ═══════════════════════════════════════════════════════════
#  ☁️  AUTHENTIFICATION & DÉPLOIEMENT GCP
# ═══════════════════════════════════════════════════════════

async def _run(cmd: list) -> tuple:
    """Exécute une commande shell et retourne (returncode, stdout, stderr)."""
    p = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE
    )
    out, err = await p.communicate()
    return p.returncode, out.decode().strip(), err.decode().strip()


async def _exchange_qwiklabs_token(raw_url: str) -> Optional[str]:
    """
    Le lien Qwiklabs contient un token OAuth dans le paramètre &token=
    On l'échange contre un vrai access_token Google via tokeninfo,
    ou on l'utilise directement s'il est déjà un Bearer token valide.
    On retourne l'access_token utilisable par gcloud.
    """
    import aiohttp

    # Extraire le token brut du lien
    m = re.search(r'[?&]token=([A-Za-z0-9_\-\.]+)', raw_url)
    if not m:
        logger.warning("Aucun token trouvé dans le lien")
        return None

    raw_token = m.group(1)
    logger.info(f"Token extrait ({len(raw_token)} chars)")

    # Vérifier si c'est un access_token valide via tokeninfo
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(
                "https://oauth2.googleapis.com/tokeninfo",
                params={"access_token": raw_token},
                timeout=aiohttp.ClientTimeout(total=10)
            ) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    logger.info(f"Token valide : scope={data.get('scope','?')[:60]}")
                    return raw_token
                else:
                    body = await resp.text()
                    logger.warning(f"tokeninfo refusé ({resp.status}): {body[:200]}")
    except Exception as e:
        logger.warning(f"tokeninfo error: {e}")

    return None


async def authenticate_gcp(project_info: dict) -> dict:
    """
    Authentifie gcloud sur le projet GCP Qwiklabs en utilisant
    le token OAuth extrait directement du lien temporaire.
    """
    project_id  = project_info["project_id"]
    raw_url     = project_info.get("raw_url", "")
    student_email = project_info.get("student_email")

    try:
        # ── Étape 1 : Obtenir l'access_token depuis le lien ──────────
        access_token = await _exchange_qwiklabs_token(raw_url)

        if access_token:
            logger.info("Injection du token OAuth dans gcloud…")

            # Créer un compte gcloud avec le token directement
            if student_email:
                rc, _, err = await _run([
                    "gcloud", "config", "set", "account", student_email
                ])

            # Injecter l'access_token via variable d'env CLOUDSDK_AUTH_TOKEN
            # gcloud l'utilise automatiquement si présent
            import os
            os.environ["CLOUDSDK_AUTH_ACCESS_TOKEN"] = access_token
            logger.info("CLOUDSDK_AUTH_ACCESS_TOKEN défini")

        else:
            logger.warning("Aucun token récupéré — tentative avec session gcloud existante")

        # ── Étape 2 : Définir le projet ───────────────────────────────
        rc, _, err = await _run(["gcloud", "config", "set", "project", project_id])
        if rc != 0:
            return {"success": False, "error": f"Impossible de définir le projet : {err}"}

        # ── Étape 3 : Activer l'API Cloud Run (ignore l'erreur si déjà actif) ──
        await _run([
            "gcloud", "services", "enable", "run.googleapis.com",
            "--project", project_id
        ])

        # ── Étape 4 : Vérifier l'accès au projet ──────────────────────
        rc, out, err = await _run([
            "gcloud", "projects", "describe", project_id, "--format=json"
        ])
        if rc != 0:
            # Dernier recours : essayer via l'API REST directement avec le token
            if access_token:
                import aiohttp
                async with aiohttp.ClientSession() as session:
                    async with session.get(
                        f"https://cloudresourcemanager.googleapis.com/v1/projects/{project_id}",
                        headers={"Authorization": f"Bearer {access_token}"},
                        timeout=aiohttp.ClientTimeout(total=10)
                    ) as resp:
                        if resp.status == 200:
                            logger.info(f"Accès projet confirmé via API REST")
                            return {"success": True, "via": "rest_api"}
                        else:
                            body = await resp.text()
                            return {"success": False, "error": f"Accès refusé au projet (REST) : {body[:300]}"}
            return {"success": False, "error": f"Accès refusé : {err}"}

        logger.info(f"GCP auth OK → {project_id}")
        return {"success": True}

    except Exception as e:
        logger.error(f"authenticate_gcp: {e}", exc_info=True)
        return {"success": False, "error": str(e)}


async def deploy_vless_service(project_info: dict) -> dict:
    """Deploie ou retrouve le service VLESS sur Cloud Run."""
    project_id = project_info["project_id"]
    try:
        # Le service existe-t-il deja ?
        rc, out, _ = await _run([
            "gcloud", "run", "services", "describe", CLOUDRUN_SERVICE_NAME,
            "--region", CLOUDRUN_REGION, "--project", project_id, "--format=json"
        ])

        if rc == 0:
            service_url = json.loads(out)["status"]["url"]
            logger.info(f"Service existant -> {service_url}")
        else:
            # Deployer
            logger.info(f"Deploiement de {CLOUDRUN_SERVICE_NAME}...")
            rc, out, err = await _run([
                "gcloud", "run", "deploy", CLOUDRUN_SERVICE_NAME,
                "--image", CLOUDRUN_IMAGE,
                "--platform", "managed",
                "--region", CLOUDRUN_REGION,
                "--project", project_id,
                "--allow-unauthenticated",
                "--port", "8080",
                "--set-env-vars", f"UUID={VLESS_UUID},WS_PATH={VLESS_PATH}",
                "--memory", "256Mi",
                "--cpu", "1",
                "--max-instances", "10",
                "--quiet"
            ])
            if rc != 0:
                return {"success": False, "error": err}

            # Recuperer l'URL
            rc, service_url, _ = await _run([
                "gcloud", "run", "services", "describe", CLOUDRUN_SERVICE_NAME,
                "--region", CLOUDRUN_REGION, "--project", project_id,
                "--format=value(status.url)"
            ])
            if not service_url:
                return {"success": False, "error": "URL du service introuvable apres deploiement"}

        db_save_project(project_id, service_url, CLOUDRUN_REGION)
        return {"success": True, "service_url": service_url, "project_id": project_id}

    except Exception as e:
        return {"success": False, "error": str(e)}

# ═══════════════════════════════════════════════════════════
#  🔗  GÉNÉRATION DU LIEN VLESS
# ═══════════════════════════════════════════════════════════

def generate_vless_link(service_url: str) -> str:
    """
    Génère le lien VLESS avec UUID et path fixes.
    Format : vless://UUID@host:443?security=tls&type=ws&path=/KIGHMU...#KIGHMU
    """
    host = service_url.replace("https://", "").replace("http://", "").rstrip("/")
    encoded_path = urllib.parse.quote(VLESS_PATH, safe="")

    return (
        f"vless://{VLESS_UUID}@{host}:{VLESS_PORT}"
        f"?path={encoded_path}"
        f"&security=tls"
        f"&encryption=none"
        f"&host={host}"
        f"&type=ws"
        f"&sni={host}"
        f"#KIGHMU"
    )

def get_expiry_time() -> str:
    """Labs Qwiklabs : durée standard de 3h."""
    return (datetime.utcnow() + timedelta(hours=3)).strftime("%Y-%m-%d %H:%M UTC")

# ═══════════════════════════════════════════════════════════
#  🤖  HANDLERS TELEGRAM
# ═══════════════════════════════════════════════════════════

async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    name = update.effective_user.first_name
    await update.message.reply_text(
        f"👋 Bonjour *{name}* !\n\n"
        "🔗 *Bot VLESS Generator*\n\n"
        "Envoie-moi un lien *Google Cloud / Qwiklabs* et je génère ton lien VLESS instantanément.\n\n"
        "📋 *Commandes :*\n"
        "• /start — Ce message\n"
        "• /help  — Guide d'utilisation\n"
        "• /status — État du bot\n\n"
        "⚡ Colle ton lien pour commencer !",
        parse_mode="Markdown"
    )

async def cmd_help(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "📖 *Guide d'utilisation*\n\n"
        "1️⃣ Va sur *skills.google* ou *Qwiklabs*\n"
        "2️⃣ Lance un lab Google Cloud\n"
        "3️⃣ Copie le lien de connexion temporaire\n"
        "4️⃣ Colle-le ici\n\n"
        "✅ Le bot fait automatiquement :\n"
        "• Extraction du projet GCP\n"
        "• Connexion via gcloud\n"
        "• Déploiement Cloud Run\n"
        "• Génération du lien VLESS\n\n"
        "⏱ *Temps de génération :*\n"
        "• Service existant  → ~5–10 secondes\n"
        "• Nouveau déploiement → ~60–90 secondes\n\n"
        "⏰ *Durée du lien :* ~3h (expire avec le lab)",
        parse_mode="Markdown"
    )

async def cmd_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "📊 *État du bot*\n\n"
        f"✅ Bot : En ligne\n"
        f"🔗 Liens actifs : {db_active_count()}\n"
        f"🔑 UUID : `{VLESS_UUID}`\n"
        f"📂 Path : `{VLESS_PATH}`\n",
        parse_mode="Markdown"
    )

async def handle_link(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = update.message.text.strip()

    # Vérification basique du lien
    if not any(d in text for d in ["skills.google", "qwiklabs", "console.cloud.google"]):
        await update.message.reply_text(
            "❌ Lien non reconnu.\n\n"
            "Envoie un lien *skills.google* ou *console.cloud.google.com* complet.",
            parse_mode="Markdown"
        )
        return

    # Message d'attente initial
    msg = await update.message.reply_text(
        "⏳ *Traitement en cours…*\n\n🔍 Analyse du lien…",
        parse_mode="Markdown"
    )

    try:
        # ── Étape 1 : Parser ──────────────────────────────
        project_info = parse_google_link(text)
        if not project_info:
            await msg.edit_text(
                "❌ *Impossible d'extraire le projet GCP.*\n\nVérifie que le lien est complet.",
                parse_mode="Markdown"
            )
            return

        await msg.edit_text(
            "⏳ *Traitement en cours…*\n\n"
            "✅ Lien analysé\n"
            f"📁 Projet : `{project_info['project_id']}`\n"
            "🔐 Connexion au projet GCP…",
            parse_mode="Markdown"
        )

        # ── Étape 2 : Auth GCP ────────────────────────────
        auth = await authenticate_gcp(project_info)
        if not auth["success"]:
            await msg.edit_text(
                f"❌ *Échec d'authentification GCP*\n\n`{auth['error']}`",
                parse_mode="Markdown"
            )
            return

        await msg.edit_text(
            "⏳ *Traitement en cours…*\n\n"
            "✅ Lien analysé\n"
            "✅ Projet GCP connecté\n"
            "🚀 Déploiement du service VLESS…\n"
            "_(peut prendre ~60s si premier déploiement)_",
            parse_mode="Markdown"
        )

        # ── Étape 3 : Déploiement Cloud Run ───────────────
        service = await deploy_vless_service(project_info)
        if not service["success"]:
            await msg.edit_text(
                f"❌ *Échec du déploiement Cloud Run*\n\n`{service['error']}`",
                parse_mode="Markdown"
            )
            return

        # ── Étape 4 : Génération VLESS ────────────────────
        vless = generate_vless_link(service["service_url"])
        expiry = get_expiry_time()

        db_save_link(update.message.from_user.id, vless, project_info["project_id"], expiry)

        keyboard = [[
            InlineKeyboardButton("🔄 Nouveau lien", callback_data="new"),
            InlineKeyboardButton("📊 Statut", callback_data="status")
        ]]

        await msg.edit_text(
            "✅ *Lien VLESS généré !*\n\n"
            f"`{vless}`\n\n"
            f"📁 Projet : `{project_info['project_id']}`\n"
            f"🌍 Région : `{CLOUDRUN_REGION}`\n"
            f"⏰ Expire : `{expiry}`\n\n"
            "⚠️ Copie et sauvegarde ce lien !",
            parse_mode="Markdown",
            reply_markup=InlineKeyboardMarkup(keyboard)
        )

    except Exception as e:
        logger.error(f"handle_link error: {e}", exc_info=True)
        await msg.edit_text(
            f"❌ *Erreur inattendue*\n\n`{str(e)}`",
            parse_mode="Markdown"
        )

async def button_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    if q.data == "new":
        await q.edit_message_text("📤 Envoie ton nouveau lien Google Cloud / Qwiklabs :")
    elif q.data == "status":
        await q.edit_message_text(
            f"📊 *Statut*\n\n🔗 Liens actifs : {db_active_count()}",
            parse_mode="Markdown"
        )

# ═══════════════════════════════════════════════════════════
#  🚀  MAIN
# ═══════════════════════════════════════════════════════════

def main():
    init_db()
    app = Application.builder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("help", cmd_help))
    app.add_handler(CommandHandler("status", cmd_status))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_link))
    app.add_handler(CallbackQueryHandler(button_callback))
    logger.info("🤖 Bot VLESS démarré")
    app.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == "__main__":
    main()
