// ================================================================
// bot2.go — Telegram VPS Control Bot (compatible toutes versions Go)
// ================================================================

package main

import (
	"bufio"
	"fmt"
	"io/ioutil"
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

// Structure pour V2Ray+FastDNS
type UtilisateurV2Ray struct {
	Nom    string
	UUID   string
	Expire string
}

var utilisateursV2Ray []UtilisateurV2Ray

// ===============================
// Initialisation ADMIN_ID
// ===============================
func initAdminID() {
	if adminID != 0 {
		return
	}

	idStr := os.Getenv("ADMIN_ID")
	if idStr == "" {
		fmt.Print("🆔 Entrez votre ADMIN_ID Telegram : ")
		fmt.Scanln(&idStr)
	}

	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		fmt.Println("❌ ADMIN_ID invalide")
		os.Exit(1)
	}
	adminID = id
}

// ===============================
// Charger DOMAIN depuis kighmu_info si non défini
// ===============================
func loadDomain() string {
	if DOMAIN != "" {
		return DOMAIN
	}

	paths := []string{"/etc/kighmu/kighmu_info", "/root/.kighmu_info"}

	for _, path := range paths {
		file, err := os.Open(path)
		if err != nil {
			continue
		}
		defer file.Close()

		scanner := bufio.NewScanner(file)
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())
			if strings.HasPrefix(line, "DOMAIN=") {
				domain := strings.Trim(strings.SplitN(line, "=", 2)[1], "\"")
				if domain != "" {
					fmt.Println("[OK] Domaine chargé depuis", path)
					return domain
				}
			}
		}
	}

	fmt.Println("[ERREUR] Aucun fichier kighmu_info valide trouvé, domaine vide")
	return ""
}

// ===============================
// Fonctions auxiliaires FastDNS
// ===============================
func slowdnsPubKey() string {
	data, err := ioutil.ReadFile("/etc/slowdns/server.pub")
	if err != nil {
		return "clé_non_disponible"
	}
	return strings.TrimSpace(string(data))
}

func slowdnsNameServer() string {
	data, err := ioutil.ReadFile("/etc/slowdns/ns.conf")
	if err != nil {
		return "NS_non_defini"
	}
	return strings.TrimSpace(string(data))
}

func genererUUID() string {
	out, _ := exec.Command("cat", "/proc/sys/kernel/random/uuid").Output()
	return strings.TrimSpace(string(out))
}

// ===============================
// Création utilisateur normal (jours)
// ===============================
func creerUtilisateurNormal(username, password string, limite int, days int) string {
	if _, err := user.Lookup(username); err == nil {
		return fmt.Sprintf("❌ L'utilisateur %s existe déjà", username)
	}

	cmdAdd := exec.Command("useradd", "-m", "-s", "/bin/bash", username)
	if err := cmdAdd.Run(); err != nil {
		return fmt.Sprintf("❌ Erreur création utilisateur: %v", err)
	}

	cmdPass := exec.Command("bash", "-c", fmt.Sprintf("echo '%s:%s' | chpasswd", username, password))
	if err := cmdPass.Run(); err != nil {
		return fmt.Sprintf("❌ Erreur mot de passe: %v", err)
	}

	expireDate := time.Now().AddDate(0, 0, days).Format("2006-01-02")
	exec.Command("chage", "-E", expireDate, username).Run()

	hostIPBytes, _ := exec.Command("hostname", "-I").Output()
	hostIP := strings.Fields(string(hostIPBytes))[0]

	slowdnsKey := slowdnsPubKey()
	slowdnsNS := slowdnsNameServer()

	userFile := "/etc/kighmu/users.list"
	os.MkdirAll("/etc/kighmu", 0755)
	entry := fmt.Sprintf("%s|%s|%d|%s|%s|%s|%s\n", username, password, limite, expireDate, hostIP, DOMAIN, slowdnsNS)
	f, _ := os.OpenFile(userFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	defer f.Close()
	f.WriteString(entry)

	res := []string{
		fmt.Sprintf("✅ Utilisateur %s créé avec succès", username),
		"∘ SSH: 22  ∘ System-DNS: 53",
		"∘ SSH WS: 80  ∘ WEB-NGINX: 81",
		"∘ DROPBEAR: 2222  ∘ SSL: 444",
		"∘ BadVPN: 7200  ∘ BadVPN: 7300",
		"∘ FASTDNS: 5300  ∘ UDP-Custom: 54000",
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

// ===============================
// Création utilisateur V2Ray + FastDNS
// ===============================
func creerUtilisateurV2Ray() string {
	reader := bufio.NewReader(os.Stdin)
	fmt.Print("Entrez le nom de l'utilisateur : ")
	nom, _ := reader.ReadString('\n')
	nom = strings.TrimSpace(nom)
	var duree int
	fmt.Print("Durée de validité (en jours) : ")
	fmt.Scanf("%d\n", &duree)
	uuid := genererUUID()
	dateExp := time.Now().AddDate(0, 0, duree).Format("2006-01-02")
	v2rayPort := 5401
	fastdnsPort := 5400
	pubKey := slowdnsPubKey()
	nameServer := slowdnsNameServer()
	domaine := DOMAIN
	lienVLESS := fmt.Sprintf("vless://%s@%s:%d?type=tcp&encryption=none&host=%s#%s-VLESS-TCP",
		uuid, domaine, v2rayPort, domaine, nom)
	var builder strings.Builder
	builder.WriteString("============================================\n")
	builder.WriteString("🧩 VLESS TCP + FASTDNS\n")
	builder.WriteString("====================================================\n")
	builder.WriteString(fmt.Sprintf("📄 Configuration pour : %s\n", nom))
	builder.WriteString("-------------------------------------------------------------\n")
	builder.WriteString(fmt.Sprintf("➤ DOMAINE : %s\n", domaine))
	builder.WriteString("➤ PORTS :\n")
	builder.WriteString(fmt.Sprintf("   FastDNS UDP: %d\n", fastdnsPort))
	builder.WriteString(fmt.Sprintf("   V2Ray TCP  : %d\n", v2rayPort))
	builder.WriteString(fmt.Sprintf("➤ UUID / Password : %s\n", uuid))
	builder.WriteString(fmt.Sprintf("➤ Validité : %d jours (expire: %s)\n", duree, dateExp))
	builder.WriteString("━━━━━━━━━━━━━  CONFIGS SLOWDNS PORT 5400 ━━━━━━━━━━━━━●\n")
	builder.WriteString("Clé publique FastDNS:\n")
	builder.WriteString(pubKey + "\n")
	builder.WriteString(fmt.Sprintf("NameServer: %s\n", nameServer))
	builder.WriteString("●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●\n")
	builder.WriteString(fmt.Sprintf("┃ Lien VLESS  : %s\n", lienVLESS))
	builder.WriteString("┃\n")
	builder.WriteString("●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●\n")
	return builder.String()
}

// ===============================
// Suppression utilisateur V2Ray + FastDNS
// ===============================
func supprimerUtilisateurV2Ray(index int) string {
	if index < 0 || index >= len(utilisateursV2Ray) {
		return "❌ Index invalide"
	}
	u := utilisateursV2Ray[index]
	utilisateursV2Ray = append(utilisateursV2Ray[:index], utilisateursV2Ray[index+1:]...)
	return fmt.Sprintf("✅ Utilisateur %s supprimé.", u.Nom)
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

			case "v2ray_creer":
				msg := tgbotapi.NewMessage(update.CallbackQuery.Message.Chat.ID,
					"Envoyez les infos pour créer un utilisateur V2Ray + FastDNS sous ce format :\n`nom,durée`")
				msg.ParseMode = "Markdown"
				bot.Send(msg)

			case "v2ray_supprimer":
				if len(utilisateursV2Ray) == 0 {
					bot.Send(tgbotapi.NewMessage(update.CallbackQuery.Message.Chat.ID, "❌ Aucun utilisateur V2Ray+FastDNS à supprimer."))
				} else {
					msgText := "Liste des utilisateurs V2Ray+FastDNS :\n"
					for i, u := range utilisateursV2Ray {
						msgText += fmt.Sprintf("%d) %s | UUID: %s | Expire: %s\n", i+1, u.Nom, u.UUID, u.Expire)
					}
					msgText += "\nRépondez avec le numéro de l'utilisateur à supprimer."
					bot.Send(tgbotapi.NewMessage(update.CallbackQuery.Message.Chat.ID, msgText))
				}

			default:
				bot.AnswerCallbackQuery(tgbotapi.NewCallback(update.CallbackQuery.ID, "❌ Option inconnue"))
			}
		}

		if update.Message != nil && int64(update.Message.From.ID) == adminID {
			text := strings.TrimSpace(update.Message.Text)

			// Gestion V2Ray+FastDNS création
			if strings.Count(text, ",") == 1 {
				parts := strings.Split(text, ",")
				nom := strings.TrimSpace(parts[0])
				duree, _ := strconv.Atoi(strings.TrimSpace(parts[1]))
				output := creerUtilisateurV2Ray(nom, duree)
				bot.Send(tgbotapi.NewMessage(update.Message.Chat.ID, output))
				continue
			}

			// Gestion V2Ray+FastDNS suppression
			if num, err := strconv.Atoi(text); err == nil && num > 0 && num <= len(utilisateursV2Ray) {
				output := supprimerUtilisateurV2Ray(num - 1)
				bot.Send(tgbotapi.NewMessage(update.Message.Chat.ID, output))
				continue
			}

			// Commande principale
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
						tgbotapi.NewInlineKeyboardButtonData("➕ Créer utilisateur V2Ray+FastDNS", "v2ray_creer"),
						tgbotapi.NewInlineKeyboardButtonData("➖ Supprimer utilisateur V2Ray+FastDNS", "v2ray_supprimer"),
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

// ===============================
// Main
// ===============================
func main() {
	initAdminID()
	DOMAIN = loadDomain()
	fmt.Println("✅ Bot prêt à être lancé")
	lancerBot()
}
