// ================================================================
// bot2.go — Telegram VPS Control Bot (BOT UNIQUEMENT)
// Auteur : Kighmu
// Compatible : Go 1.13+ / Ubuntu 20.04
// ================================================================

package main

import (
	"os"
	"os/exec"
	"strconv"
	"strings"

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api"
)

var adminID int64

// =====================
// Commandes autorisées
// =====================
func runCommand(cmd string) string {
	allowed := map[string]bool{
		"uptime":                     true,
		"df -h":                      true,
		"free -m":                    true,
		"systemctl status sshws":     true,
		"systemctl status dnstt":     true,
		"systemctl restart sshws":    true,
		"systemctl restart dnstt":    true,
	}

	if !allowed[cmd] {
		return "⛔ Commande non autorisée"
	}

	out, err := exec.Command("bash", "-c", cmd).CombinedOutput()
	if err != nil {
		return "❌ Erreur:\n" + err.Error()
	}

	return "✅ Résultat:\n" + string(out)
}

// =====================
// MAIN
// =====================
func main() {
	botToken := os.Getenv("BOT_TOKEN")
	if botToken == "" {
		panic("BOT_TOKEN manquant")
	}

	idStr := os.Getenv("ADMIN_ID")
	if idStr == "" {
		panic("ADMIN_ID manquant")
	}

	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		panic("ADMIN_ID invalide")
	}
	adminID = id

	bot, err := tgbotapi.NewBotAPI(botToken)
	if err != nil {
		panic(err)
	}

	u := tgbotapi.NewUpdate(0)
	u.Timeout = 60
	updates, _ := bot.GetUpdatesChan(u)

	for update := range updates {
		if update.Message == nil {
			continue
		}

		if update.Message.From.ID != adminID {
			bot.Send(tgbotapi.NewMessage(update.Message.Chat.ID, "⛔ Accès refusé"))
			continue
		}

		text := strings.TrimSpace(update.Message.Text)
		response := "❓ Commande inconnue"

		switch text {
		case "/start":
			response = "🤖 VPS Control Bot\n\n" +
				"/status\n" +
				"/uptime\n" +
				"/disk\n" +
				"/ram\n" +
				"/sshws\n" +
				"/slowdns"

		case "/status", "/uptime":
			response = runCommand("uptime")
		case "/disk":
			response = runCommand("df -h")
		case "/ram":
			response = runCommand("free -m")
		case "/sshws":
			response = runCommand("systemctl status sshws")
		case "/slowdns":
			response = runCommand("systemctl status dnstt")
		}

		bot.Send(tgbotapi.NewMessage(update.Message.Chat.ID, response))
	}
}
