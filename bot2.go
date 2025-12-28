// ================================================================
// bot2.go — Telegram VPS Control Bot (sans panneau interne)
// Auteur : Kighmu
// Compatible : Go 1.13+ / Ubuntu 20.04
// ================================================================

package main

import (
	"log"
	"os"
	"os/exec"
	"strconv"
	"strings"

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api"
)

// =====================
// Configuration
// =====================
var (
	botToken = os.Getenv("BOT_TOKEN")
	adminID  int64
)

// =====================
// Commandes autorisées
// =====================
func runCommand(cmd string) string {
	allowed := []string{
		"uptime",
		"df -h",
		"free -m",
		"systemctl status sshws",
		"systemctl status dnstt",
		"systemctl restart sshws",
		"systemctl restart dnstt",
	}

	for _, a := range allowed {
		if cmd == a {
			out, err := exec.Command("bash", "-c", cmd).CombinedOutput()
			if err != nil {
				return "❌ Erreur:\n" + err.Error()
			}
			return "✅ Résultat:\n" + string(out)
		}
	}

	return "⛔ Commande non autorisée"
}

// =====================
// MAIN
// =====================
func main() {

	if botToken == "" {
		log.Fatal("❌ BOT_TOKEN manquant dans l'environnement")
	}

	idStr := os.Getenv("ADMIN_ID")
	if idStr == "" {
		log.Fatal("❌ ADMIN_ID manquant dans l'environnement")
	}

	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		log.Fatal("❌ ADMIN_ID invalide")
	}
	adminID = id

	bot, err := tgbotapi.NewBotAPI(botToken)
	if err != nil {
		log.Fatal("❌ Impossible de créer le bot :", err)
	}

	log.Printf("🤖 Bot démarré : %s", bot.Self.UserName)

	u := tgbotapi.NewUpdate(0)
	u.Timeout = 60
	updates := bot.GetUpdatesChan(u)

	for update := range updates {
		if update.Message == nil {
			continue
		}

		// ✅ CORRECTION ICI (int → int64)
		if int64(update.Message.From.ID) != adminID {
			msg := tgbotapi.NewMessage(update.Message.Chat.ID, "⛔ Accès refusé")
			bot.Send(msg)
			continue
		}

		text := strings.TrimSpace(update.Message.Text)
		var response string

		switch text {

		case "/start":
			response = "👋 *VPS Control Bot*\n\n" +
				"/status\n" +
				"/uptime\n" +
				"/disk\n" +
				"/ram\n" +
				"/sshws\n" +
				"/slowdns\n" +
				"/restart_sshws\n" +
				"/restart_slowdns"

		case "/status":
			response = runCommand("uptime")

		case "/uptime":
			response = runCommand("uptime")

		case "/disk":
			response = runCommand("df -h")

		case "/ram":
			response = runCommand("free -m")

		case "/sshws":
			response = runCommand("systemctl status sshws")

		case "/slowdns":
			response = runCommand("systemctl status dnstt")

		case "/restart_sshws":
			response = runCommand("systemctl restart sshws")

		case "/restart_slowdns":
			response = runCommand("systemctl restart dnstt")

		default:
			response = "❓ Commande inconnue"
		}

		msg := tgbotapi.NewMessage(update.Message.Chat.ID, response)
		msg.ParseMode = "Markdown"
		bot.Send(msg)
	}
}
