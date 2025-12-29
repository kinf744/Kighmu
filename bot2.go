// ================================================================
// bot2.go — Telegram VPS Control Bot
// Auteur : Kighmu
// Compatible : Go 1.13+ / Ubuntu 20.04
// ================================================================

package main

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"bufio"

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api"
)

var (
	botToken = os.Getenv("BOT_TOKEN")
	adminID  int64
	homeDir  = os.Getenv("HOME")
)

// Exécute un script bash et retourne stdout/stderr
func execScript(script string) string {
	cmd := exec.Command("bash", script)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Sprintf("❌ Erreur : %v\n%s", err, string(out))
	}
	return string(out)
}

func lancerBot() {
	reader := bufio.NewReader(os.Stdin)

	// Demande BOT_TOKEN si manquant
	if botToken == "" {
		fmt.Print("🔑 Entrez votre BOT_TOKEN : ")
		inputToken, _ := reader.ReadString('\n')
		botToken = strings.TrimSpace(inputToken)
	}

	// Demande ADMIN_ID si manquant
	idStr := os.Getenv("ADMIN_ID")
	if idStr == "" {
		fmt.Print("🆔 Entrez votre ADMIN_ID (Telegram) : ")
		inputID, _ := reader.ReadString('\n')
		idStr = strings.TrimSpace(inputID)
	}

	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		fmt.Println("❌ ADMIN_ID invalide")
		return
	}
	adminID = id

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
		if update.Message == nil {
			continue
		}

		// Vérifie si c'est l'admin
		if int64(update.Message.From.ID) != adminID {
			msg := tgbotapi.NewMessage(update.Message.Chat.ID, "⛔ Accès refusé")
			bot.Send(msg)
			continue
		}

		text := strings.TrimSpace(update.Message.Text)

		switch text {
		case "/kighmu":
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
				tgbotapi.NewInlineKeyboardRow(
					tgbotapi.NewInlineKeyboardButtonData("Gestion utilisateurs en ligne", "menu3"),
					tgbotapi.NewInlineKeyboardButtonData("Supprimer utilisateur", "menu4"),
				),
			)

			msg := tgbotapi.NewMessage(update.Message.Chat.ID, msgText)
			msg.ReplyMarkup = keyboard
			bot.Send(msg)

		default:
			msg := tgbotapi.NewMessage(update.Message.Chat.ID, "❌ Commande inconnue")
			bot.Send(msg)
		}
	}

	// Gestion des callbacks (boutons)
	for update := range bot.ListenForWebhook("/") {
		if update.CallbackQuery != nil {
			data := update.CallbackQuery.Data
			var scriptPath string

			switch data {
			case "menu1":
				scriptPath = homeDir + "/Kighmu/menu1.sh"
			case "menu2":
				scriptPath = homeDir + "/Kighmu/menu2.sh"
			case "menu3":
				scriptPath = homeDir + "/Kighmu/menu3.sh"
			case "menu4":
				scriptPath = homeDir + "/Kighmu/menu4.sh"
			default:
				bot.AnswerCallbackQuery(tgbotapi.NewCallback(update.CallbackQuery.ID, "❌ Option inconnue"))
				continue
			}

			bot.AnswerCallbackQuery(tgbotapi.NewCallback(update.CallbackQuery.ID, "✅ Exécution du script..."))

			// Exécution du script et envoi du résultat dans Telegram
			output := execScript(scriptPath)
			msg := tgbotapi.NewMessage(update.CallbackQuery.Message.Chat.ID, "Résultat de "+data+":\n"+output)
			bot.Send(msg)
		}
	}
}

func main() {
	fmt.Println("✅ Bot prêt à être lancé")
	lancerBot()
}
