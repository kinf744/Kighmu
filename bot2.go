// ================================================================
// bot2.go — Telegram VPS Control Bot
// Auteur : Kighmu
// Compatible : Go 1.13+ / Ubuntu 20.04
// ================================================================

package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api"
)

var (
	botToken = os.Getenv("BOT_TOKEN")
	adminID  int64
)

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
					tgbotapi.NewInlineKeyboardButtonURL("Option 1", "https://t.me/tonlien1"),
				),
				tgbotapi.NewInlineKeyboardRow(
					tgbotapi.NewInlineKeyboardButtonURL("Option 2", "https://t.me/tonlien2"),
				),
				tgbotapi.NewInlineKeyboardRow(
					tgbotapi.NewInlineKeyboardButtonURL("Option 3", "https://t.me/tonlien3"),
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
}

func main() {
	fmt.Println("✅ Bot prêt à être lancé")
	lancerBot()
}
