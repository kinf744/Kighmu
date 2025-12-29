// ================================================================
// bot2.go — Telegram VPS Control Bot
// Boutons : Créer utilisateur / Créer utilisateur test
// ================================================================

package main

import (
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"strconv"
	"strings"
	"time"

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api"
)

var (
	botToken = os.Getenv("BOT_TOKEN")
	adminID  int64
	DOMAIN   = os.Getenv("DOMAIN")
)

// ===============================
// Fonctions utilitaires
// ===============================

// Créer utilisateur normal (jours)
func creerUtilisateurNormal(username, password string, limite, days int) string {
	if _, err := user.Lookup(username); err == nil {
		return fmt.Sprintf("❌ L'utilisateur %s existe déjà", username)
	}

	// Création utilisateur
	if err := exec.Command("useradd", "-m", "-s", "/bin/bash", username).Run(); err != nil {
		return fmt.Sprintf("❌ Erreur création utilisateur: %v", err)
	}

	// Définir mot de passe
	if err := exec.Command("bash", "-c", fmt.Sprintf("echo '%s:%s' | chpasswd", username, password)).Run(); err != nil {
		return fmt.Sprintf("❌ Erreur mot de passe: %v", err)
	}

	// Expiration
	expireDate := time.Now().AddDate(0, 0, days).Format("2006-01-02")
	exec.Command("chage", "-E", expireDate, username).Run()

	// Host IP
	hostIPBytes, _ := exec.Command("hostname", "-I").Output()
	hostIP := strings.Fields(string(hostIPBytes))[0]

	// SlowDNS
	slowdnsKey, _ := os.ReadFile("/etc/slowdns/server.pub")
	slowdnsNS, _ := os.ReadFile("/etc/slowdns/ns.conf")

	// Sauvegarde
	userFile := "/etc/kighmu/users.list"
	os.MkdirAll("/etc/kighmu", 0755)
	entry := fmt.Sprintf("%s|%s|%d|%s|%s|%s|%s\n", username, password, limite, expireDate, hostIP, DOMAIN, strings.TrimSpace(string(slowdnsNS)))
	f, _ := os.OpenFile(userFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	defer f.Close()
	f.WriteString(entry)

	// Résumé
	res := []string{
		fmt.Sprintf("✅ Utilisateur %s créé avec succès", username),
		fmt.Sprintf("Utilisateur: %s", username),
		fmt.Sprintf("Mot de passe: %s", password),
		fmt.Sprintf("Limite appareils: %d", limite),
		fmt.Sprintf("Date expiration: %s", expireDate),
		fmt.Sprintf("DOMAIN: %s", DOMAIN),
		fmt.Sprintf("Host/IP: %s", hostIP),
		"Pub KEY SlowDNS:\n" + string(slowdnsKey),
		"NameServer NS:\n" + string(slowdnsNS),
	}
	return strings.Join(res, "\n")
}

// Créer utilisateur test (minutes)
func creerUtilisateurTest(username, password string, limite, minutes int) string {
	if _, err := user.Lookup(username); err == nil {
		return fmt.Sprintf("❌ L'utilisateur %s existe déjà", username)
	}

	if err := exec.Command("useradd", "-M", "-s", "/bin/bash", username).Run(); err != nil {
		return fmt.Sprintf("❌ Erreur création utilisateur: %v", err)
	}
	if err := exec.Command("bash", "-c", fmt.Sprintf("echo '%s:%s' | chpasswd", username, password)).Run(); err != nil {
		return fmt.Sprintf("❌ Erreur mot de passe: %v", err)
	}

	expireTime := time.Now().Add(time.Duration(minutes) * time.Minute).Format("2006-01-02 15:04:05")
	hostIPBytes, _ := exec.Command("hostname", "-I").Output()
	hostIP := strings.Fields(string(hostIPBytes))[0]

	slowdnsKey, _ := os.ReadFile("/etc/slowdns/server.pub")
	slowdnsNS, _ := os.ReadFile("/etc/slowdns/ns.conf")

	userFile := "/etc/kighmu/users.list"
	os.MkdirAll("/etc/kighmu", 0755)
	entry := fmt.Sprintf("%s|%s|%d|%s|%s|%s|%s\n", username, password, limite, expireTime, hostIP, DOMAIN, strings.TrimSpace(string(slowdnsNS)))
	f, _ := os.OpenFile(userFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	defer f.Close()
	f.WriteString(entry)

	res := []string{
		fmt.Sprintf("✅ Utilisateur test %s créé avec succès", username),
		fmt.Sprintf("Utilisateur: %s", username),
		fmt.Sprintf("Mot de passe: %s", password),
		fmt.Sprintf("Limite appareils: %d", limite),
		fmt.Sprintf("Date expiration: %s", expireTime),
		fmt.Sprintf("DOMAIN: %s", DOMAIN),
		fmt.Sprintf("Host/IP: %s", hostIP),
		"Pub KEY SlowDNS:\n" + string(slowdnsKey),
		"NameServer NS:\n" + string(slowdnsNS),
	}
	return strings.Join(res, "\n")
}

// ===============================
// Bot Telegram
// ===============================
func lancerBot() {
	bot, err := tgbotapi.NewBotAPI(botToken)
	if err != nil {
		fmt.Println("❌ Impossible de créer le bot:", err)
		return
	}
	fmt.Println("🤖 Bot Telegram démarré")

	u := tgbotapi.NewUpdate(0)
	u.Timeout = 60
	updates, _ := bot.GetUpdatesChan(u)

	for update := range updates {
		// Boutons
		if update.CallbackQuery != nil {
			if int64(update.CallbackQuery.From.ID) != adminID {
				bot.AnswerCallbackQuery(tgbotapi.NewCallback(update.CallbackQuery.ID, "⛔ Accès refusé"))
				continue
			}

			bot.AnswerCallbackQuery(tgbotapi.NewCallback(update.CallbackQuery.ID, "✅ Exécution..."))

			var msg tgbotapi.MessageConfig
			switch update.CallbackQuery.Data {
			case "menu1":
				msg = tgbotapi.NewMessage(update.CallbackQuery.Message.Chat.ID,
					"Envoyez les infos pour création utilisateur (jours) au format : `username,password,limite,days`")
				msg.ParseMode = "Markdown"
			case "menu2":
				msg = tgbotapi.NewMessage(update.CallbackQuery.Message.Chat.ID,
					"Envoyez les infos pour création utilisateur test (minutes) au format : `username,password,limite,minutes`")
				msg.ParseMode = "Markdown"
			}
			bot.Send(msg)
		}

		// Messages texte
		if update.Message != nil && int64(update.Message.From.ID) == adminID {
			text := strings.TrimSpace(update.Message.Text)
			if strings.Count(text, ",") == 3 {
				parts := strings.Split(text, ",")
				username := strings.TrimSpace(parts[0])
				password := strings.TrimSpace(parts[1])
				limite, _ := strconv.Atoi(strings.TrimSpace(parts[2]))

				// Déterminer menu1 ou menu2 selon valeur
				if strings.Contains(text, "days") {
					days, _ := strconv.Atoi(strings.TrimSpace(parts[3]))
					output := creerUtilisateurNormal(username, password, limite, days)
					bot.Send(tgbotapi.NewMessage(update.Message.Chat.ID, output))
				} else {
					minutes, _ := strconv.Atoi(strings.TrimSpace(parts[3]))
					output := creerUtilisateurTest(username, password, limite, minutes)
					bot.Send(tgbotapi.NewMessage(update.Message.Chat.ID, output))
				}
			} else if text == "/kighmu" {
				keyboard := tgbotapi.NewInlineKeyboardMarkup(
					tgbotapi.NewInlineKeyboardRow(
						tgbotapi.NewInlineKeyboardButtonData("Créer utilisateur (jours)", "menu1"),
						tgbotapi.NewInlineKeyboardButtonData("Créer utilisateur test (minutes)", "menu2"),
					),
				)
				msg := tgbotapi.NewMessage(update.Message.Chat.ID, "⚡ KIGHMU MANAGER ⚡")
				msg.ReplyMarkup = keyboard
				bot.Send(msg)
			} else {
				bot.Send(tgbotapi.NewMessage(update.Message.Chat.ID, "❌ Commande inconnue"))
			}
		}
	}
}

func main() {
	fmt.Println("✅ Bot prêt à être lancé")
	lancerBot()
}
