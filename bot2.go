// ================================================================
// bot2.go — Telegram VPS Control Bot
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

	if botToken == "" {
		fmt.Print("🔑 Entrez votre BOT_TOKEN : ")
		inputToken, _ := reader.ReadString('\n')
		botToken = strings.TrimSpace(inputToken)
	}

	idStr := os.Getenv("ADMIN_ID")
	if idStr == "" {
		fmt.Print("🆔 Entrez votre ADMIN_ID : ")
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

		// --- Gestion CallbackQuery (boutons) ---
		if update.CallbackQuery != nil {
			if int64(update.CallbackQuery.From.ID) != adminID {
				bot.AnswerCallbackQuery(tgbotapi.NewCallback(update.CallbackQuery.ID, "⛔ Accès refusé"))
				continue
			}

			var scriptPath string
			switch update.CallbackQuery.Data {
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

			output := execScript(scriptPath)
			msg := tgbotapi.NewMessage(update.CallbackQuery.Message.Chat.ID, "Résultat :\n"+output)
			bot.Send(msg)
			continue
		}

		// --- Gestion messages texte ---
		if update.Message == nil {
			continue
		}
		if int64(update.Message.From.ID) != adminID {
			msg := tgbotapi.NewMessage(update.Message.Chat.ID, "⛔ Accès refusé")
			bot.Send(msg)
			continue
		}

		text := strings.TrimSpace(update.Message.Text)
		if text == "/kighmu" {
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
		} else {
			msg := tgbotapi.NewMessage(update.Message.Chat.ID, "❌ Commande inconnue")
			bot.Send(msg)
		}
	}
}

func main() {
	fmt.Println("✅ Bot prêt à être lancé")
	lancerBot()
}
