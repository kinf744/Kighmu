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
	v2rayFile = "/etc/kighmu/v2ray_users.list"
)

// Structure pour V2Ray+FastDNS
type UtilisateurV2Ray struct {
	Nom    string
	UUID   string
	Expire string
}

var utilisateursV2Ray []UtilisateurV2Ray

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

// Créer utilisateur normal (jours)
// ===============================
func setPassword(username, password string) error {
    fmt.Printf("[DEBUG] setPassword %s (len=%d)\n", username, len(password))

    // Assurer que le home existe avant
    home := "/home/" + username
    if _, err := os.Stat(home); os.IsNotExist(err) {
        os.MkdirAll(home, 0700)
        exec.Command("chown", "-R", username+":"+username, home).Run()
    }

    // Utiliser un shell login pour chpasswd
    cmd := exec.Command("bash", "-lc",
        fmt.Sprintf("echo '%s:%s' | chpasswd", username, password),
    )
    cmd.Env = append(os.Environ(),
        "HOME="+home,
        "SHELL=/bin/bash",
    )
    out, err := cmd.CombinedOutput()
    if err != nil {
        return fmt.Errorf("chpasswd failed: %v | %s", err, string(out))
    }

    // Déverrouiller le compte (optionnel, mais sûr)
    exec.Command("passwd", "-u", username).Run()

    // Debug shadow
    shadowOut, _ := exec.Command("getent", "shadow", username).CombinedOutput()
    fmt.Printf("[DEBUG shadow] %s\n", string(shadowOut))

    return nil
}

func fixHome(username string) {
    home := "/home/" + username
    if _, err := os.Stat(home); os.IsNotExist(err) {
        os.MkdirAll(home, 0700)
    }
    exec.Command("chown", "-R", username+":"+username, home).Run()
    exec.Command("chmod", "700", home).Run()
}

func creerUtilisateurNormal(username, password string, limite, days int) string {
	// Vérifier existence
	if _, err := user.Lookup(username); err == nil {
		return fmt.Sprintf("❌ L'utilisateur %s existe déjà", username)
	}

	// Création utilisateur
	if err := exec.Command("useradd", "-m", "-s", "/bin/bash", username).Run(); err != nil {
		return fmt.Sprintf("❌ Erreur création utilisateur: %v", err)
	}

	// FIX HOME (OBLIGATOIRE)
    fixHome(username)

	// Définir mot de passe (CORRIGÉ)
	if err := setPassword(username, password); err != nil {
		return fmt.Sprintf("❌ Erreur mot de passe: %v", err)
	}

	// Déverrouiller le compte (important HTTP Custom)
	exec.Command("passwd", "-u", username).Run()

	// Expiration
	expireDate := time.Now().AddDate(0, 0, days).Format("2006-01-02")
	exec.Command("chage", "-E", expireDate, username).Run()

	// Home & bashrc
	userHome := "/home/" + username
	bashrcPath := userHome + "/.bashrc"
	bannerPath := "/etc/ssh/sshd_banner"

	os.MkdirAll(userHome, 0755)

	bashrcContent := fmt.Sprintf(`
# Affichage du banner Kighmu VPS Manager
if [ -f %s ]; then
    cat %s
fi
`, bannerPath, bannerPath)

	ioutil.WriteFile(bashrcPath, []byte(bashrcContent), 0644)
	exec.Command("chown", "-R", username+":"+username, userHome).Run()

	// IP
	hostIP := "IP_non_disponible"
	if ipBytes, err := exec.Command("hostname", "-I").Output(); err == nil {
		ips := strings.Fields(string(ipBytes))
		if len(ips) > 0 {
			hostIP = ips[0]
		}
	}

	// SlowDNS
	slowdnsKey := slowdnsPubKey()
	slowdnsNS := slowdnsNameServer()

	// Sauvegarde
	os.MkdirAll("/etc/kighmu", 0755)
	userFile := "/etc/kighmu/users.list"
	entry := fmt.Sprintf("%s|%s|%d|%s|%s|%s|%s\n",
		username, password, limite, expireDate, hostIP, DOMAIN, slowdnsNS)

	if f, err := os.OpenFile(userFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600); err == nil {
		defer f.Close()
		f.WriteString(entry)
	}

	// Résumé
	return strings.Join([]string{
		fmt.Sprintf("✅ Utilisateur %s créé avec succès", username),
		fmt.Sprintf("Host/IP: %s", hostIP),
		fmt.Sprintf("Utilisateur: %s", username),
		fmt.Sprintf("Mot de passe: %s", password),
		fmt.Sprintf("Limite appareils: %d", limite),
		fmt.Sprintf("Date expiration: %s", expireDate),
		"Pub KEY SlowDNS:\n" + slowdnsKey,
		"NameServer NS:\n" + slowdnsNS,
	}, "\n")
}

func creerUtilisateurTest(username, password string, limite, minutes int) string {
	if _, err := user.Lookup(username); err == nil {
		return fmt.Sprintf("❌ L'utilisateur %s existe déjà", username)
	}

	// Création
	exec.Command("useradd", "-m", "-s", "/bin/bash", username).Run()
    fixHome(username)

	// Mot de passe (CORRIGÉ)
	if err := setPassword(username, password); err != nil {
		return fmt.Sprintf("❌ Erreur mot de passe: %v", err)
	}

	exec.Command("passwd", "-u", username).Run()

	// Expiration logique
	expireTime := time.Now().Add(time.Duration(minutes) * time.Minute).Format("2006-01-02 15:04:05")

	// IP
	hostIP := "IP_non_disponible"
	if ipBytes, err := exec.Command("hostname", "-I").Output(); err == nil {
		ips := strings.Fields(string(ipBytes))
		if len(ips) > 0 {
			hostIP = ips[0]
		}
	}

	// SlowDNS
	slowdnsKey := slowdnsPubKey()
	slowdnsNS := slowdnsNameServer()

	// Sauvegarde
	os.MkdirAll("/etc/kighmu", 0755)
	userFile := "/etc/kighmu/users.list"
	entry := fmt.Sprintf("%s|%s|%d|%s|%s|%s|%s\n",
		username, password, limite, expireTime, hostIP, DOMAIN, slowdnsNS)

	if f, err := os.OpenFile(userFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600); err == nil {
		defer f.Close()
		f.WriteString(entry)
	}

	return strings.Join([]string{
		fmt.Sprintf("✅ Utilisateur test %s créé avec succès", username),
		fmt.Sprintf("Host/IP: %s", hostIP),
		fmt.Sprintf("Utilisateur: %s", username),
		fmt.Sprintf("Mot de passe: %s", password),
		fmt.Sprintf("Date expiration: %s", expireTime),
		"Pub KEY SlowDNS:\n" + slowdnsKey,
		"NameServer NS:\n" + slowdnsNS,
	}, "\n")
}

// Charger utilisateurs V2Ray depuis fichier
// ===============================
func chargerUtilisateursV2Ray() {
	utilisateursV2Ray = []UtilisateurV2Ray{}
	data, err := ioutil.ReadFile(v2rayFile)
	if err != nil {
		// fichier inexistant, on continue avec slice vide
		return
	}
	lignes := strings.Split(string(data), "\n")
	for _, ligne := range lignes {
		if strings.TrimSpace(ligne) == "" {
			continue
		}
		parts := strings.Split(ligne, "|")
		if len(parts) >= 3 {
			utilisateursV2Ray = append(utilisateursV2Ray, UtilisateurV2Ray{
				Nom:    parts[0],
				UUID:   parts[1],
				Expire: parts[2],
			})
		}
	}
}

// Enregistrer un utilisateur V2Ray dans le fichier
// ===============================
func enregistrerUtilisateurV2Ray(u UtilisateurV2Ray) error {
	if err := os.MkdirAll("/etc/kighmu", 0755); err != nil {
		return err
	}
	f, err := os.OpenFile(v2rayFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = f.WriteString(fmt.Sprintf("%s|%s|%s\n", u.Nom, u.UUID, u.Expire))
	return err
}

// Créer utilisateur V2Ray + FastDNS
// ===============================
func creerUtilisateurV2Ray(nom string, duree int) string {
	uuid := genererUUID()
	expire := time.Now().AddDate(0, 0, duree).Format("2006-01-02")

	// Ajouter au slice et fichier
	u := UtilisateurV2Ray{Nom: nom, UUID: uuid, Expire: expire}
	utilisateursV2Ray = append(utilisateursV2Ray, u)
	if err := enregistrerUtilisateurV2Ray(u); err != nil {
		return fmt.Sprintf("❌ Erreur sauvegarde utilisateur : %v", err)
	}

	// Ports et infos FastDNS / V2Ray
	v2rayPort := 5401
	fastdnsPort := 5400
	pubKey := slowdnsPubKey()
	nameServer := slowdnsNameServer()

	// Lien VLESS TCP
	lienVLESS := fmt.Sprintf(
		"vless://%s@%s:%d?type=tcp&encryption=none&host=%s#%s-VLESS-TCP",
		u.UUID, DOMAIN, v2rayPort, DOMAIN, u.Nom,
	)

	// Message complet
	var builder strings.Builder
	builder.WriteString("====================================================\n")
	builder.WriteString("🧩 VLESS TCP + FASTDNS\n")
	builder.WriteString("====================================================\n")
	builder.WriteString(fmt.Sprintf("📄 Configuration pour : %s\n", u.Nom))
	builder.WriteString("----------------------------------------------------\n")
	builder.WriteString(fmt.Sprintf("➤ DOMAINE : %s\n", DOMAIN))
	builder.WriteString("➤ PORTS :\n")
	builder.WriteString(fmt.Sprintf("   FastDNS UDP : %d\n", fastdnsPort))
	builder.WriteString(fmt.Sprintf("   V2Ray TCP   : %d\n", v2rayPort))
	builder.WriteString(fmt.Sprintf("➤ UUID / Password : %s\n", u.UUID))
	builder.WriteString(fmt.Sprintf("➤ Validité : %d jours (expire : %s)\n", duree, expire))
	builder.WriteString("\n━━━━━━━━━━━━━  CONFIGS SLOWDNS PORT 5400 ━━━━━━━━━━━━━\n")
	builder.WriteString(fmt.Sprintf("Clé publique FastDNS :\n%s\n", pubKey))
	builder.WriteString(fmt.Sprintf("NameServer : %s\n", nameServer))
	builder.WriteString("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
	builder.WriteString(fmt.Sprintf("Lien VLESS  : %s\n", lienVLESS))
	builder.WriteString("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

	return builder.String()
}

// Supprimer utilisateur V2Ray + FastDNS
// ===============================
func supprimerUtilisateurV2Ray(index int) string {
	if index < 0 || index >= len(utilisateursV2Ray) {
		return "❌ Index invalide"
	}
	u := utilisateursV2Ray[index]
	// Retirer du slice
	utilisateursV2Ray = append(utilisateursV2Ray[:index], utilisateursV2Ray[index+1:]...)
	// Réécrire le fichier complet
	if err := os.MkdirAll("/etc/kighmu", 0755); err != nil {
		return fmt.Sprintf("❌ Erreur dossier : %v", err)
	}
	f, err := os.Create(v2rayFile)
	if err != nil {
		return fmt.Sprintf("❌ Erreur fichier : %v", err)
	}
	defer f.Close()
	for _, u := range utilisateursV2Ray {
		f.WriteString(fmt.Sprintf("%s|%s|%s\n", u.Nom, u.UUID, u.Expire))
	}
	return fmt.Sprintf("✅ Utilisateur %s supprimé.", u.Nom)
}

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

	// Map pour gérer le mode suppression multiple par chat
	modeSupprimerMultiple := make(map[int64]bool)

	for update := range updates {

		/* ===============================
		   CALLBACKS (INLINE MENU)
		================================ */
		if update.CallbackQuery != nil {
			if int64(update.CallbackQuery.From.ID) != adminID {
				bot.AnswerCallbackQuery(
					tgbotapi.NewCallback(update.CallbackQuery.ID, "⛔ Accès refusé"),
				)
				continue
			}

			bot.AnswerCallbackQuery(
				tgbotapi.NewCallback(update.CallbackQuery.ID, "✅ Exécution..."),
			)

			switch update.CallbackQuery.Data {

			case "menu1":
				msg := tgbotapi.NewMessage(
					update.CallbackQuery.Message.Chat.ID,
					"Envoyez :\n`username,password,limite,jours`",
				)
				msg.ParseMode = "Markdown"
				bot.Send(msg)

			case "menu2":
				msg := tgbotapi.NewMessage(
					update.CallbackQuery.Message.Chat.ID,
					"Envoyez :\n`username,password,limite,minutes`",
				)
				msg.ParseMode = "Markdown"
				bot.Send(msg)

			case "v2ray_creer":
				msg := tgbotapi.NewMessage(
					update.CallbackQuery.Message.Chat.ID,
					"Envoyez :\n`nom,duree`",
				)
				msg.ParseMode = "Markdown"
				bot.Send(msg)

			case "v2ray_supprimer":
				if len(utilisateursV2Ray) == 0 {
					bot.Send(tgbotapi.NewMessage(
						update.CallbackQuery.Message.Chat.ID,
						"❌ Aucun utilisateur V2Ray à supprimer",
					))
					continue
				}
				txt := "Liste des utilisateurs V2Ray :\n"
				for i, u := range utilisateursV2Ray {
					txt += fmt.Sprintf("%d) %s | UUID: %s | Expire: %s\n", i+1, u.Nom, u.UUID, u.Expire)
				}
				txt += "\nEnvoyez le numéro à supprimer"
				bot.Send(tgbotapi.NewMessage(update.CallbackQuery.Message.Chat.ID, txt))

			case "supprimer_multi":
				msg := tgbotapi.NewMessage(update.CallbackQuery.Message.Chat.ID,
					"Envoyez les noms des utilisateurs à supprimer, séparés par des virgules ou espaces :\n`user1,user2,user3`")
				msg.ParseMode = "Markdown"
				bot.Send(msg)
				modeSupprimerMultiple[update.CallbackQuery.Message.Chat.ID] = true
			}
			continue
		}

		/* ===============================
		   MESSAGES TEXTE
		================================ */
		if update.Message == nil || int64(update.Message.From.ID) != adminID {
			continue
		}

		chatID := update.Message.Chat.ID
		text := strings.TrimSpace(update.Message.Text)

		/* ===== MODE SUPPRESSION MULTIPLE ===== */
		if modeSupprimerMultiple[chatID] {
			users := strings.FieldsFunc(text, func(r rune) bool { return r == ',' || r == ' ' })
			var results []string
			for _, u := range users {
				u = strings.TrimSpace(u)
				if u == "" {
					continue
				}
				if _, err := user.Lookup(u); err == nil {
					cmd := exec.Command("userdel", "-r", u)
					if err := cmd.Run(); err != nil {
						results = append(results, fmt.Sprintf("❌ Erreur suppression %s", u))
					} else {
						// Supprimer ligne users.list
						data, _ := ioutil.ReadFile("/etc/kighmu/users.list")
						lines := strings.Split(string(data), "\n")
						var newLines []string
						for _, line := range lines {
							if !strings.HasPrefix(line, u+"|") {
								newLines = append(newLines, line)
							}
						}
						ioutil.WriteFile("/etc/kighmu/users.list", []byte(strings.Join(newLines, "\n")), 0600)
						results = append(results, fmt.Sprintf("✅ Utilisateur %s supprimé", u))
					}
				} else {
					results = append(results, fmt.Sprintf("⚠️ Utilisateur %s introuvable", u))
				}
			}
			bot.Send(tgbotapi.NewMessage(chatID, strings.Join(results, "\n")))
			delete(modeSupprimerMultiple, chatID)
			continue
		}

		/* ===== MENU PRINCIPAL ===== */
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
					tgbotapi.NewInlineKeyboardButtonData("Compte_SSH (jours)", "menu1"),
					tgbotapi.NewInlineKeyboardButtonData("Compte_SSH test(minutes)", "menu2"),
				),
				tgbotapi.NewInlineKeyboardRow(
					tgbotapi.NewInlineKeyboardButtonData("➕ Compte V2Ray+FastDNS", "v2ray_creer"),
					tgbotapi.NewInlineKeyboardButtonData("➖ Supprimer_Compte V2Ray+FastDNS", "v2ray_supprimer"),
				),
				tgbotapi.NewInlineKeyboardRow(
					tgbotapi.NewInlineKeyboardButtonData("❌ Supprimer_Compte_SSH(s)", "supprimer_multi"),
				),
			)
			msg := tgbotapi.NewMessage(chatID, msgText)
			msg.ReplyMarkup = keyboard
			bot.Send(msg)
			continue
		}

		/* ===== SSH NORMAL / TEST ===== */
		if strings.Count(text, ",") == 3 {
			p := strings.Split(text, ",")
			limite, err1 := strconv.Atoi(strings.TrimSpace(p[2]))
			duree, err2 := strconv.Atoi(strings.TrimSpace(p[3]))
			if err1 != nil || err2 != nil {
				bot.Send(tgbotapi.NewMessage(chatID, "❌ Paramètres invalides"))
				continue
			}
			if duree <= 1440 {
				bot.Send(tgbotapi.NewMessage(chatID, creerUtilisateurTest(p[0], p[1], limite, duree)))
			} else {
				bot.Send(tgbotapi.NewMessage(chatID, creerUtilisateurNormal(p[0], p[1], limite, duree)))
			}
			continue
		}

		/* ===== V2RAY ===== */
		if strings.Count(text, ",") == 1 {
			p := strings.Split(text, ",")
			duree, err := strconv.Atoi(strings.TrimSpace(p[1]))
			if err != nil {
				bot.Send(tgbotapi.NewMessage(chatID, "❌ Durée invalide"))
				continue
			}
			bot.Send(tgbotapi.NewMessage(chatID, creerUtilisateurV2Ray(p[0], duree)))
			continue
		}

		/* ===== SUPPRESSION V2RAY ===== */
		if num, err := strconv.Atoi(text); err == nil && num > 0 && num <= len(utilisateursV2Ray) {
			bot.Send(tgbotapi.NewMessage(chatID, supprimerUtilisateurV2Ray(num-1)))
			continue
		}

		/* ===== INCONNU ===== */
		bot.Send(tgbotapi.NewMessage(chatID, "❌ Commande ou format inconnu"))
	}
}

// ===============================
// Main
// ===============================
func main() {
	initAdminID()
	DOMAIN = loadDomain()
	chargerUtilisateursV2Ray() // <- ajouter cette ligne
	fmt.Println("✅ Bot prêt à être lancé")
	lancerBot()
}
