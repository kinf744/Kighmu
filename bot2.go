// ================================================================
// bot2.go — Telegram VPS Control Bot avec menu1 dynamique
// ================================================================

package main

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api"
)

var (
	botToken = os.Getenv("BOT_TOKEN")
	adminID  int64
	homeDir  = os.Getenv("HOME")
)

// Fonction utilitaire pour exécuter une commande et récupérer le stdout
func execOutput(cmd string) string {
	out, _ := exec.Command("bash", "-c", cmd).Output()
	return string(out)
}

// Lecture de fichier, renvoie "N/A" si absent
func readFile(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return "N/A"
	}
	return string(b)
}

// Création utilisateur (menu1) avec Go
func CreateUserMenu1(username, password string, limite, days int) (string, error) {
	if username == "" || password == "" {
		return "", fmt.Errorf("paramètres invalides")
	}

	// Vérifier si l'utilisateur existe déjà
	if err := exec.Command("id", username).Run(); err == nil {
		return "", fmt.Errorf("l'utilisateur existe déjà")
	}

	// Date d'expiration
	expireDate := time.Now().AddDate(0, 0, days).Format("2006-01-02")

	// Création de l'utilisateur
	if err := exec.Command("useradd", "-m", "-s", "/bin/bash", username).Run(); err != nil {
		return "", fmt.Errorf("erreur lors de la création de l'utilisateur")
	}

	// Définir le mot de passe
	cmd := exec.Command("bash", "-c", fmt.Sprintf("echo '%s:%s' | chpasswd", username, password))
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("erreur lors de la définition du mot de passe")
	}

	// Définir la date d'expiration
	exec.Command("chage", "-E", expireDate, username).Run()

	// Infos système
	hostIP := strings.TrimSpace(execOutput("hostname -I | awk '{print $1}'"))
	domain := strings.TrimSpace(execOutput("grep DOMAIN ~/.kighmu_info | cut -d= -f2"))
	slowDNSKey := readFile("/etc/slowdns/server.pub")
	slowDNSNS := readFile("/etc/slowdns/ns.conf")

	// Enregistrement
	os.MkdirAll("/etc/kighmu", 0700)
	f, _ := os.OpenFile("/etc/kighmu/users.list", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	defer f.Close()
	fmt.Fprintf(f, "%s|%s|%d|%s|%s|%s|%s\n", username, password, limite, expireDate, hostIP, domain, slowDNSNS)

	result := fmt.Sprintf(`
✅ *NOUVEAU UTILISATEUR CRÉÉ*

🌍 Domaine : %s
🖥 IP : %s
👤 Utilisateur : %s
🔑 Mot de passe : %s
📱 Limite : %d
⏳ Expire : %s

🔑 FASTDNS PUB KEY :
%s

📡 NS : %s
`, domain, hostIP, username, password, limite, expireDate, slowDNSKey, slowDNSNS)

	return result, nil
}

// ================================================================
// LANCEMENT DU BOT
// ================================================================
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

	// Etat de saisie par utilisateur
	type session struct {
		step     string
		username string
		password string
		limite   int
		days     int
	}
	sessions := make(map[int64]*session)

	for update := range updates {

		if update.Message == nil {
			continue
		}
		chatID := update.Message.Chat.ID
		userID := int64(update.Message.From.ID)

		// Vérification admin
		if userID != adminID {
			bot.Send(tgbotapi.NewMessage(chatID, "⛔ Accès refusé"))
			continue
		}

		// Gestion saisie menu1
		if s, ok := sessions[userID]; ok {
			switch s.step {
			case "username":
				s.username = update.Message.Text
				s.step = "password"
				bot.Send(tgbotapi.NewMessage(chatID, "🔑 Entrez le mot de passe :"))
			case "password":
				s.password = update.Message.Text
				s.step = "limite"
				bot.Send(tgbotapi.NewMessage(chatID, "📱 Entrez le nombre d'appareils autorisés :"))
			case "limite":
				lim, err := strconv.Atoi(update.Message.Text)
				if err != nil {
					bot.Send(tgbotapi.NewMessage(chatID, "❌ Limite invalide, réessayez :"))
					continue
				}
				s.limite = lim
				s.step = "days"
				bot.Send(tgbotapi.NewMessage(chatID, "⏳ Entrez la durée de validité en jours :"))
			case "days":
				d, err := strconv.Atoi(update.Message.Text)
				if err != nil {
					bot.Send(tgbotapi.NewMessage(chatID, "❌ Durée invalide, réessayez :"))
					continue
				}
				s.days = d

				// Créer l'utilisateur
				out, err := CreateUserMenu1(s.username, s.password, s.limite, s.days)
				if err != nil {
					bot.Send(tgbotapi.NewMessage(chatID, "❌ "+err.Error()))
				} else {
					msg := tgbotapi.NewMessage(chatID, out)
					msg.ParseMode = "Markdown"
					bot.Send(msg)
				}
				delete(sessions, userID) // fin session
			}
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

			msg := tgbotapi.NewMessage(chatID, msgText)
			msg.ReplyMarkup = keyboard
			bot.Send(msg)
		} else if text == "menu1" || strings.Contains(text, "Créer utilisateur") {
			// Initialiser session menu1
			sessions[userID] = &session{step: "username"}
			bot.Send(tgbotapi.NewMessage(chatID, "👤 Entrez le nom d'utilisateur :"))
		} else {
			bot.Send(tgbotapi.NewMessage(chatID, "❌ Commande inconnue"))
		}
	}
}

func main() {
	fmt.Println("✅ Bot prêt à être lancé")
	lancerBot()
}
