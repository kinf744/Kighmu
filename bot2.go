// ================================================================
// bot2.go — Telegram VPS Control Bot (compatible toutes versions Go)
// ================================================================

package main

import (
	"fmt"
	"io/ioutil" // ← Pour ReadFile compatible Go <1.16
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
func creerUtilisateurNormal(username, password string, limite int, days int) string {
	if _, err := user.Lookup(username); err == nil {
		return fmt.Sprintf("❌ L'utilisateur %s existe déjà", username)
	}

	// Création utilisateur
	cmdAdd := exec.Command("useradd", "-m", "-s", "/bin/bash", username)
	if err := cmdAdd.Run(); err != nil {
		return fmt.Sprintf("❌ Erreur création utilisateur: %v", err)
	}

	// Définir mot de passe
	cmdPass := exec.Command("bash", "-c", fmt.Sprintf("echo '%s:%s' | chpasswd", username, password))
	if err := cmdPass.Run(); err != nil {
		return fmt.Sprintf("❌ Erreur mot de passe: %v", err)
	}

	// Expiration
	expireDate := time.Now().AddDate(0, 0, days).Format("2006-01-02")
	exec.Command("chage", "-E", expireDate, username).Run()

	// Host IP
	hostIPBytes, _ := exec.Command("hostname", "-I").Output()
	hostIP := strings.Fields(string(hostIPBytes))[0]

	// SlowDNS
	slowdnsKeyBytes, _ := ioutil.ReadFile("/etc/slowdns/server.pub")
	slowdnsKey := strings.TrimSpace(string(slowdnsKeyBytes))
	slowdnsNSBytes, _ := ioutil.ReadFile("/etc/slowdns/ns.conf")
	slowdnsNS := strings.TrimSpace(string(slowdnsNSBytes))

	// Sauvegarder
	userFile := "/etc/kighmu/users.list"
	os.MkdirAll("/etc/kighmu", 0755)
	entry := fmt.Sprintf("%s|%s|%d|%s|%s|%s|%s\n", username, password, limite, expireDate, hostIP, DOMAIN, slowdnsNS)
	f, _ := os.OpenFile(userFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	defer f.Close()
	f.WriteString(entry)

	// Résumé
	res := []string{
		fmt.Sprintf("✅ Utilisateur %s créé avec succès", username),
		"∘ SSH: 22  ∘ System-DNS: 53",
		"∘ SSH WS: 80  ∘ WEB-NGINX: 81",
		"∘ DROPBEAR: 2222  ∘ SSL: 444",
		"∘ BadVPN: 7200  ∘ BadVPN: 7300",
		"∘ FASTDNS: 5300  ∘ UDP-Custom: 1-65535",
		"∘ Hysteria: 22000  ∘ Proxy WS: 9090",
		fmt.Sprintf("DOMAIN: %s", DOMAIN),
		fmt.Sprintf("Host/IP: %s", hostIP),
		fmt.Sprintf("Utilisateur: %s", username),
		fmt.Sprintf("Mot de passe: %s", password),
		fmt.Sprintf("Limite appareils: %d", limite),
		fmt.Sprintf("Date expiration: %s", expireDate),
		"Pub KEY SlowDNS:\n" + slowdnsKey,
		"NameServer NS:\n" + slowdnsNS,
	}
	return strings.Join(res, "\n")
}

// Créer utilisateur test (minutes)
func creerUtilisateurTest(username, password string, limite, minutes int) string {
	if _, err := user.Lookup(username); err == nil {
		return fmt.Sprintf("❌ L'utilisateur %s existe déjà", username)
	}

	// Création utilisateur
	cmdAdd := exec.Command("useradd", "-M", "-s", "/bin/bash", username)
	if err := cmdAdd.Run(); err != nil {
		return fmt.Sprintf("❌ Erreur création utilisateur: %v", err)
	}

	// Définir mot de passe
	cmdPass := exec.Command("bash", "-c", fmt.Sprintf("echo '%s:%s' | chpasswd", username, password))
	if err := cmdPass.Run(); err != nil {
		return fmt.Sprintf("❌ Erreur mot de passe: %v", err)
	}

	// Expiration
	expireTime := time.Now().Add(time.Duration(minutes) * time.Minute).Format("2006-01-02 15:04:05")

	// Host IP
	hostIPBytes, _ := exec.Command("hostname", "-I").Output()
	hostIP := strings.Fields(string(hostIPBytes))[0]

	// SlowDNS
	slowdnsKeyBytes, _ := ioutil.ReadFile("/etc/slowdns/server.pub")
	slowdnsKey := strings.TrimSpace(string(slowdnsKeyBytes))
	slowdnsNSBytes, _ := ioutil.ReadFile("/etc/slowdns/ns.conf")
	slowdnsNS := strings.TrimSpace(string(slowdnsNSBytes))

	// Sauvegarder
	userFile := "/etc/kighmu/users.list"
	os.MkdirAll("/etc/kighmu", 0755)
	entry := fmt.Sprintf("%s|%s|%d|%s|%s|%s|%s\n", username, password, limite, expireTime, hostIP, DOMAIN, slowdnsNS)
	f, _ := os.OpenFile(userFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	defer f.Close()
	f.WriteString(entry)

	// Résumé
	res := []string{
		fmt.Sprintf("✅ Utilisateur test %s créé avec succès", username),
		"∘ SSH: 22  ∘ System-DNS: 53",
		"∘ SSH WS: 80  ∘ WEB-NGINX: 81",
		"∘ DROPBEAR: 2222  ∘ SSL: 444",
		"∘ BadVPN: 7200  ∘ BadVPN: 7300",
		"∘ FASTDNS: 5300  ∘ UDP-Custom: 1-65535",
		"∘ Hysteria: 22000  ∘ Proxy WS: 9090",
		fmt.Sprintf("DOMAIN: %s", DOMAIN),
		fmt.Sprintf("Host/IP: %s", hostIP),
		fmt.Sprintf("Utilisateur: %s", username),
		fmt.Sprintf("Mot de passe: %s", password),
		fmt.Sprintf("Limite appareils: %d", limite),
		fmt.Sprintf("Date expiration: %s", expireTime),
		"Pub KEY SlowDNS:\n" + slowdnsKey,
		"NameServer NS:\n" + slowdnsNS,
	}
	return strings.Join(res, "\n")
}

// ===============================
// Lancement Bot Telegram
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
		if update.CallbackQuery != nil {
			if int64(update.CallbackQuery.From.ID) != adminID {
				bot.AnswerCallbackQuery(tgbotapi.NewCallback(update.CallbackQuery.ID, "⛔ Accès refusé"))
				continue
			}

			bot.AnswerCallbackQuery(tgbotapi.NewCallback(update.CallbackQuery.ID, "✅ Exécution..."))

			switch update.CallbackQuery.Data {
			case "menu1":
				msg := tgbotapi.NewMessage(update.CallbackQuery.Message.Chat.ID,
					"Envoyez les infos pour création utilisateur (jours) sous ce format :\n`username,password,limite,days`")
				msg.ParseMode = "Markdown"
				bot.Send(msg)
			case "menu2":
				msg := tgbotapi.NewMessage(update.CallbackQuery.Message.Chat.ID,
					"Envoyez les infos pour création utilisateur test (minutes) sous ce format :\n`username,password,limite,minutes`")
				msg.ParseMode = "Markdown"
				bot.Send(msg)
			default:
				bot.AnswerCallbackQuery(tgbotapi.NewCallback(update.CallbackQuery.ID, "❌ Option inconnue"))
			}
		}

		// --- Gestion messages texte ---
		if update.Message != nil && int64(update.Message.From.ID) == adminID {
			text := strings.TrimSpace(update.Message.Text)
			if strings.Count(text, ",") == 3 {
				parts := strings.Split(text, ",")
				username := strings.TrimSpace(parts[0])
				password := strings.TrimSpace(parts[1])
				limite, _ := strconv.Atoi(strings.TrimSpace(parts[2]))
				if strings.Contains(text, "days") {
					days, _ := strconv.Atoi(strings.TrimSpace(parts[3]))
					output := creerUtilisateurNormal(username, password, limite, days)
					msg := tgbotapi.NewMessage(update.Message.Chat.ID, output)
					bot.Send(msg)
				} else {
					minutes, _ := strconv.Atoi(strings.TrimSpace(parts[3]))
					output := creerUtilisateurTest(username, password, limite, minutes)
					msg := tgbotapi.NewMessage(update.Message.Chat.ID, output)
					bot.Send(msg)
				}
			} else if text == "/kighmu" {
				msgText := `============================================
          ⚡ KIGHMU MANAGER ⚡
============================================
        AUTEUR : @KIGHMU
        TELEGRAM : https://t.me/lkgcddtoog
============================================
   SÉLECTIONNEZ UNE OPTION CI-DESSOUS !
============================================`
				keyboard := tgbotapi.NewInlineKeyboardMarkup(
					tgbotapi.NewInlineKeyboardRow(
						tgbotapi.NewInlineKeyboardButtonData("Créer utilisateur (jours)", "menu1"),
						tgbotapi.NewInlineKeyboardButtonData("Créer utilisateur test (minutes)", "menu2"),
					),
				)
				msg := tgbotapi.NewMessage(update.Message.Chat.ID, msgText)
				msg.ReplyMarkup = keyboard
				bot.Send(msg)
			} else {
				msg := tgbotapi.NewMessage(update.Message.Chat.ID, "❌ Commande inconnue")
				bot.Send(msg)
			}
		}
	}
}

func main() {
	fmt.Println("✅ Bot prêt à être lancé")
	lancerBot()
}
