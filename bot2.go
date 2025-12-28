// ================================================================
// bot2.go — Telegram VPS Control Bot avec panneau de contrôle
// Auteur : Kighmu
// Compatible : Go 1.13+ / Ubuntu 20.04
// ================================================================

package main

import (
	"bufio"
	"fmt"
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
// Menu panneau de contrôle
// =====================
func menuPanel() {
	reader := bufio.NewReader(os.Stdin)

	for {
		fmt.Println("======================================")
		fmt.Println("   🤖 PANNEAU BOT TELEGRAM VPS")
		fmt.Println("======================================")
		fmt.Println("1️⃣  Installer la librairie Telegram Go et compiler le bot")
		fmt.Println("2️⃣  Lancer le bot Telegram")
		fmt.Println("3️⃣  Quitter")
		fmt.Print("👉 Choisissez une option [1-3] : ")

		choice, _ := reader.ReadString('\n')
		choice = strings.TrimSpace(choice)

		switch choice {
		case "1":
			installerEtCompiler()
		case "2":
			lancerBot()
		case "3":
			fmt.Println("👋 Sortie du panneau")
			os.Exit(0)
		default:
			fmt.Println("❌ Option invalide")
		}
		fmt.Println()
	}
}

// =====================
// Installer la librairie et compiler le bot
// =====================
func installerEtCompiler() {
	fmt.Println("⏳ Installation des dépendances Go...")

	if !commandExists("go") {
		fmt.Println("❌ Go n'est pas installé")
		pause()
		return
	}

	if _, err := os.Stat("go.mod"); os.IsNotExist(err) {
		cmd := exec.Command("go", "mod", "init", "telegram-bot")
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		cmd.Run()
	}

	cmd := exec.Command("go", "get", "github.com/go-telegram-bot-api/telegram-bot-api")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Run()

	fmt.Println("⏳ Compilation du bot...")
	build := exec.Command("go", "build", "-o", "bot2", "bot2.go")
	build.Stdout = os.Stdout
	build.Stderr = os.Stderr
	if err := build.Run(); err != nil {
		fmt.Println("❌ Erreur lors de la compilation :", err)
		pause()
		return
	}

	fmt.Println("✅ Librairie installée et bot compilé")
	pause()
}

// =====================
// Vérifie si une commande existe
// =====================
func commandExists(cmd string) bool {
	_, err := exec.LookPath(cmd)
	return err == nil
}

// =====================
// Pause console
// =====================
func pause() {
	fmt.Print("Appuyez sur Entrée pour continuer...")
	bufio.NewReader(os.Stdin).ReadBytes('\n')
}

// =====================
// Lancer le bot Telegram
// =====================
func lancerBot() {
	if _, err := os.Stat("bot2"); os.IsNotExist(err) {
		fmt.Println("❌ Bot non compilé. Veuillez d'abord choisir l'option 1 pour compiler.")
		pause()
		return
	}

	if botToken == "" {
		fmt.Println("❌ BOT_TOKEN manquant dans l'environnement")
		pause()
		return
	}

	idStr := os.Getenv("ADMIN_ID")
	if idStr == "" {
		fmt.Println("❌ ADMIN_ID manquant dans l'environnement")
		pause()
		return
	}
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		fmt.Println("❌ ADMIN_ID invalide")
		pause()
		return
	}
	adminID = id

	bot, err := tgbotapi.NewBotAPI(botToken)
	if err != nil {
		fmt.Println("❌ Impossible de créer le bot:", err)
		pause()
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

		if update.Message.From.ID != adminID {
			msg := tgbotapi.NewMessage(update.Message.Chat.ID, "⛔ Accès refusé")
			bot.Send(msg)
			continue
		}

		text := strings.TrimSpace(update.Message.Text)
		var response string

		switch text {
		case "/start":
			response = "👋 VPS Control Bot\n\n" +
				"/status\n" +
				"/uptime\n" +
				"/disk\n" +
				"/ram\n" +
				"/sshws\n" +
				"/slowdns"
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
		default:
			response = "❓ Commande inconnue"
		}

		msg := tgbotapi.NewMessage(update.Message.Chat.ID, response)
		msg.ParseMode = "Markdown"
		bot.Send(msg)
	}
}

// =====================
// MAIN
// =====================
func main() {
	menuPanel()
}
