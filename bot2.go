// ================================================================
// bot2.go — Telegram VPS Control Bot (compatible toutes versions Go)
// ================================================================

package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"os/user"
	"strconv"
	"strings"
	"time"

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api/v5"
)

var (
	botToken = os.Getenv("BOT_TOKEN")
	adminID  int64
	DOMAIN   = os.Getenv("DOMAIN")
	v2rayFile = "/etc/kighmu/v2ray_users.list"
)

type UtilisateurSSH struct {
    Nom     string
    Pass    string
    Limite  int
    Expire  string
    HostIP  string
    Domain  string
    SlowDNS string
}

type EtatModification struct {
    Etape   string   // "attente_numero", "attente_type", "attente_valeur"
    Indices []int
    Type    string   // "duree" ou "pass"
}

var utilisateursSSH []UtilisateurSSH
var etatsModifs = make(map[int64]*EtatModification)

// Structure pour V2Ray+FastDNS
type UtilisateurV2Ray struct {
	Nom    string
	UUID   string
	Expire string
}

var utilisateursV2Ray []UtilisateurV2Ray

type Bot struct {
    ID       int    `json:"id"`
    Nom      string `json:"nom"`
    Token    string `json:"token"`
    Role     string `json:"role"`
    ExpireLe string `json:"expire_le"`
}

type User struct {
    Username string `json:"username"`
    Password string `json:"password"`
    ExpireLe string `json:"expire_le"`
    OwnerID  int    `json:"owner_id"`
}

type Data struct {
    Bots  []Bot  `json:"bots"`
    Users []User `json:"users"`
}

var data Data
var mutex sync.Mutex

func chargerData() error {
    file, err := os.ReadFile("data.json")
    if err != nil {
        return err
    }
    return json.Unmarshal(file, &data)
}

func sauvegarderData() error {
    mutex.Lock()
    defer mutex.Unlock()

    bytes, err := json.MarshalIndent(data, "", "  ")
    if err != nil {
        return err
    }

    return os.WriteFile("data.json", bytes, 0644)
}

func getUsersForBot(bot Bot) []User {
    var result []User

    for _, user := range data.Users {
        if bot.Role == "admin" || user.OwnerID == bot.ID {
            result = append(result, user)
        }
    }

    return result
}

func ajouterUtilisateur(bot Bot, username, password, expire string) error {

    newUser := User{
        Username: username,
        Password: password,
        ExpireLe: expire,
        OwnerID:  bot.ID, // 🔥 assignation automatique
    }

    data.Users = append(data.Users, newUser)

    return sauvegarderData()
}

func supprimerUtilisateur(bot Bot, username string) error {

    var newUsers []User

    for _, user := range data.Users {

        if user.Username == username {

            if bot.Role != "admin" && user.OwnerID != bot.ID {
                return fmt.Errorf("permission refusée")
            }

            continue // skip = suppression
        }

        newUsers = append(newUsers, user)
    }

    data.Users = newUsers

    return sauvegarderData()
}

func verifierExpiration() {
    for {
        time.Sleep(1 * time.Hour)

        now := time.Now()
        var newUsers []User

        for _, user := range data.Users {
            expireDate, _ := time.Parse("2006-01-02", user.ExpireLe)

            if now.Before(expireDate) {
                newUsers = append(newUsers, user)
            }
        }

        data.Users = newUsers
        sauvegarderData()
    }
}

func validerIntegrite() {
    for _, user := range data.Users {
        found := false

        for _, bot := range data.Bots {
            if bot.ID == user.OwnerID {
                found = true
                break
            }
        }

        if !found {
            log.Println("Utilisateur orphelin détecté:", user.Username)
        }
    }
}

// Initialisation ADMIN_ID
// ===============================
func initAdminID() {
	if adminID != 0 {
		return
	}

	idStr := os.Getenv("ADMIN_ID")
	if idStr == "" {
		log.Fatal("ADMIN_ID non défini")
	}

	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		log.Fatal("ADMIN_ID invalide")
	}

	adminID = id
}

func hasAccess(userID int64, botData BotData) bool {

	// Super admin peut tout voir
	if userID == adminID {
		return true
	}

	// Propriétaire du bot
	if userID == botData.OwnerTelegramID {
		return true
	}

	return false
}

func isSuperAdmin(userID int64) bool {
	return userID == adminID
}

func isBotOwner(userID int64, botData BotData) bool {
	return userID == botData.OwnerTelegramID
}

func hasBotAccess(userID int64, botData BotData) bool {
	if isSuperAdmin(userID) {
		return true
	}
	if isBotOwner(userID, botData) {
		return true
	}
	return false
}

func utilisateurAppartientAuBot(username, botName string) bool {
	for _, u := range utilisateursSSH {
		if u.Username == username && u.CreatedByBot == botName {
			return true
		}
	}
	return false
}

func creerUtilisateurNormalAvecOwner(
	username string,
	password string,
	limite int,
	duree int,
	botName string,
	telegramID int64,
) string {

	// création système SSH ici

	// sauvegarde JSON avec owner
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
    exec.Command("chmod", "755", home).Run()
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

	f, _ := os.OpenFile(bashrcPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
defer f.Close()
f.WriteString(bashrcContent)
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

	// Restart tunnels (comme menu1.sh)
    exec.Command("systemctl", "restart", "zivpn.service").Run()
    exec.Command("systemctl", "restart", "hysteria.service").Run()
	}
	exec.Command("systemctl", "reload", "ssh").Run()
    exec.Command("systemctl", "reload", "dropbear").Run()
	syncUDPTunnels(username, password, expireDate)
	
	var builder strings.Builder
    builder.WriteString("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
    builder.WriteString("✨ 𝙉𝙊𝙐𝙑𝙀𝘼𝙐 𝙐𝙏𝙄𝙇𝙄𝙎𝘼𝙏𝙀𝙐𝙍 𝘾𝙍𝙀𝙀𝙍 ✨\n")
    builder.WriteString("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n")
    builder.WriteString(fmt.Sprintf("🌍 Domaine        : %s\n", DOMAIN))
    builder.WriteString(fmt.Sprintf("📌 IP Host        : %s\n", hostIP))
    builder.WriteString(fmt.Sprintf("👤 Utilisateur    : %s\n", username))
    builder.WriteString(fmt.Sprintf("🔑 Mot de passe   : %s\n", password))
    builder.WriteString(fmt.Sprintf("📦 Limite devices : %d\n", limite))
    builder.WriteString(fmt.Sprintf("📅 Expiration     : %s\n", expireDate))
    builder.WriteString("\n━━━━ 𝗣𝗢𝗥𝗧𝗦 𝗗𝗜𝗦𝗣𝗢𝗡𝗜𝗕𝗟𝗘𝗦 ━━━━\n")
    builder.WriteString(" SSH:22   WS:80   SSL:444   PROXY:9090\n")
    builder.WriteString(" DROPBEAR:109   FASTDNS:5300   HYSTERIA:22000\n")
    builder.WriteString(" UDP-CUSTOM:1-65535   BADVPN:7200/7300\n")
    builder.WriteString("\n━━━━━━━ 𝗦𝗦𝗛 𝗖𝗢𝗡𝗙𝗜𝗚 ━━━━━━━\n")
    builder.WriteString(fmt.Sprintf("➡️ SSH WS     : %s:80@%s:%s\n", DOMAIN, username, password))
    builder.WriteString(fmt.Sprintf("➡️ SSL/TLS    : %s:444@%s:%s\n", DOMAIN, username, password))
    builder.WriteString(fmt.Sprintf("➡️ PROXY WS   : %s:9090@%s:%s\n", DOMAIN, username, password))
    builder.WriteString(fmt.Sprintf("➡️ SSH UDP    : %s:1-65535@%s:%s\n", DOMAIN, username, password))
    builder.WriteString("\n━━━━━━━━ 𝗣𝗔𝗬𝗟𝗢𝗔𝗗 𝗪𝗦 ━━━━━━━\n")
    builder.WriteString("GET / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]\n")
    builder.WriteString("\n━━━━━━━ 𝗛𝗬𝗦𝗧𝗘𝗥𝗜𝗔 𝗨𝗗𝗣 ━━━━━━\n")
    builder.WriteString(fmt.Sprintf("🌐 Domaine : %s\n", DOMAIN))
    builder.WriteString("👤 Obfs    : hysteria\n")
    builder.WriteString(fmt.Sprintf("🔐 Pass    : %s\n", password))
    builder.WriteString("🔌 Port    : 22000\n")
    builder.WriteString("\n━━━━━━━━ 𝗭𝗜𝗩𝗣𝗡 𝗨𝗗𝗣 ━━━━━━━\n")
    builder.WriteString(fmt.Sprintf("🌐 Domaine : %s\n", DOMAIN))
    builder.WriteString("👤 Obfs    : zivpn\n")
    builder.WriteString(fmt.Sprintf("🔐 Pass    : %s\n", password))
    builder.WriteString("🔌 Port    : 5667\n")
    builder.WriteString("\n━━━━━━ 𝗙𝗔𝗦𝗧𝗗𝗡𝗦 𝗖𝗢𝗡𝗙𝗜𝗚 ━━━━━\n")
    builder.WriteString("🔐 PubKey:\n")
    builder.WriteString(slowdnsKey + "\n")
    builder.WriteString("NameServer:\n")
    builder.WriteString(slowdnsNS + "\n")
    builder.WriteString("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
    builder.WriteString("✅ COMPTE CRÉÉ AVEC SUCCÈS\n")
    builder.WriteString("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

    return builder.String()
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
	exec.Command("systemctl", "reload", "ssh").Run()
    exec.Command("systemctl", "reload", "dropbear").Run()
	syncUDPTunnels(username, password, expireTime)

	var builder strings.Builder
    builder.WriteString("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
    builder.WriteString("✨ 𝙉𝙊𝙐𝙑𝙀𝘼𝙐 𝙐𝙏𝙄𝙇𝙄𝙎𝘼𝙏𝙀𝙐𝙍 𝗧𝗘𝗦𝗧 𝘾𝙍𝙀𝙀𝙍 ✨\n")
    builder.WriteString("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n")
    builder.WriteString(fmt.Sprintf("🌍 Domaine        : %s\n", DOMAIN))
    builder.WriteString(fmt.Sprintf("📌 IP Host        : %s\n", hostIP))
    builder.WriteString(fmt.Sprintf("👤 Utilisateur    : %s\n", username))
    builder.WriteString(fmt.Sprintf("🔑 Mot de passe   : %s\n", password))
    builder.WriteString(fmt.Sprintf("📦 Limite devices : %d\n", limite))
    builder.WriteString(fmt.Sprintf("📅 Expiration     : %s\n", expireTime))
    builder.WriteString("\n━━━━ PORTS DISPONIBLES ━━━━\n")
    builder.WriteString(" SSH:22   WS:80   SSL:444   PROXY:9090\n")
    builder.WriteString(" DROPBEAR:109   FASTDNS:5300   HYSTERIA:22000\n")
    builder.WriteString(" UDP-CUSTOM:1-65535   BADVPN:7200/7300\n")
    builder.WriteString("\n━━━━━━━ SSH CONFIG ━━━━━━\n")
    builder.WriteString(fmt.Sprintf("➡️ SSH WS     : %s:80@%s:%s\n", DOMAIN, username, password))
    builder.WriteString(fmt.Sprintf("➡️ SSL/TLS    : %s:444@%s:%s\n", DOMAIN, username, password))
    builder.WriteString(fmt.Sprintf("➡️ PROXY WS   : %s:9090@%s:%s\n", DOMAIN, username, password))
    builder.WriteString(fmt.Sprintf("➡️ SSH UDP    : %s:1-65535@%s:%s\n", DOMAIN, username, password))
    builder.WriteString("\n━━━━━━━ PAYLOAD WS ━━━━━━━\n")
    builder.WriteString("GET / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]\n")
    builder.WriteString("\n━━━━━━ HYSTERIA UDP ━━━━━━\n")
    builder.WriteString(fmt.Sprintf("🌐 Domaine : %s\n", DOMAIN))
    builder.WriteString("👤 Obfs    : hysteria\n")
    builder.WriteString(fmt.Sprintf("🔐 Pass    : %s\n", password))
    builder.WriteString("🔌 Port    : 22000\n")
    builder.WriteString("\n━━━━━━━ ZIVPN UDP ━━━━━━━━\n")
    builder.WriteString(fmt.Sprintf("🌐 Domaine : %s\n", DOMAIN))
    builder.WriteString("👤 Obfs    : zivpn\n")
    builder.WriteString(fmt.Sprintf("🔐 Pass    : %s\n", password))
    builder.WriteString("🔌 Port    : 5667\n")
    builder.WriteString("\n━━━━━━ FASTDNS CONFIG ━━━━━\n")
    builder.WriteString("🔐 PubKey:\n")
    builder.WriteString(slowdnsKey + "\n")
    builder.WriteString("NameServer:\n")
    builder.WriteString(slowdnsNS + "\n")
    builder.WriteString("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
    builder.WriteString("✅ COMPTE CRÉÉ AVEC SUCCÈS\n")
    builder.WriteString("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

    return builder.String()
}

func syncUDPTunnels(username, password, expireDate string) {

    // ================= ZIVPN =================
    zivpnConfig := "/etc/zivpn/config.json"
    zivpnUsers := "/etc/zivpn/users.list"

    if _, err := os.Stat(zivpnConfig); err == nil {
        phone := username
        if len(username) > 10 {
            phone = username[:10]
        }

        line := fmt.Sprintf("%s|%s|%s\n", phone, password, expireDate)

        data, _ := ioutil.ReadFile(zivpnUsers)
        lines := strings.Split(string(data), "\n")

        var newLines []string
        for _, l := range lines {
            if !strings.HasPrefix(l, phone+"|") {
                newLines = append(newLines, l)
            }
        }
        newLines = append(newLines, strings.TrimSpace(line))
        ioutil.WriteFile(zivpnUsers, []byte(strings.Join(newLines, "\n")), 0600)

        exec.Command("bash","-c",
            `TODAY=$(date +%F); PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' `+zivpnUsers+` | sort -u | paste -sd, -); jq --arg passwords "$PASSWORDS" '.auth.config = ($passwords | split(","))' `+zivpnConfig+` > /tmp/zivpn.json && mv /tmp/zivpn.json `+zivpnConfig,
        ).Run()

        exec.Command("systemctl","restart","zivpn.service").Run()
    }

    // ================= HYSTERIA =================
    hysteriaConfig := "/etc/hysteria/config.json"
    hysteriaUsers := "/etc/hysteria/users.txt"

    if _, err := os.Stat(hysteriaConfig); err == nil {

        line := fmt.Sprintf("%s|%s|%s\n", username, password, expireDate)

        data, _ := ioutil.ReadFile(hysteriaUsers)
        lines := strings.Split(string(data), "\n")

        var newLines []string
        for _, l := range lines {
            if !strings.HasPrefix(l, username+"|") {
                newLines = append(newLines, l)
            }
        }
        newLines = append(newLines, strings.TrimSpace(line))
        ioutil.WriteFile(hysteriaUsers, []byte(strings.Join(newLines, "\n")), 0600)

        exec.Command("bash","-c",
            `TODAY=$(date +%F); PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' `+hysteriaUsers+` | sort -u | paste -sd, -); jq --arg passwords "$PASSWORDS" '.auth.config = ($passwords | split(","))' `+hysteriaConfig+` > /tmp/hysteria.json && mv /tmp/hysteria.json `+hysteriaConfig,
        ).Run()

        exec.Command("systemctl","restart","hysteria.service").Run()
    }
}

// Calculer la nouvelle date d'expiration selon les jours
func calculerNouvelleDate(jours int) string {
    if jours == 0 {
        return "none"
    }
    return time.Now().AddDate(0, 0, jours).Format("2006-01-02 15:04:05")
}

func traiterSuppressionMultiple(bot *tgbotapi.BotAPI, chatID int64, text string) {
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
}

func resumeAppareils() string {
	file := "/etc/kighmu/users.list"

	data, err := ioutil.ReadFile(file)
	if err != nil {
		return "❌ Impossible de lire users.list"
	}

	lines := strings.Split(string(data), "\n")

	var builder strings.Builder
	builder.WriteString("📊 APPAREILS CONNECTÉS PAR COMPTE\n\n")

	total := 0

	// Compter toutes les sessions SSH / Dropbear correctement
	userCounts := make(map[string]int)

	out, err := exec.Command("ps", "-eo", "user,cmd").Output()
	if err == nil {
		for _, line := range strings.Split(string(out), "\n") {
			fields := strings.Fields(line)
			if len(fields) < 2 {
				continue
			}

			user := fields[0]
			cmd := strings.Join(fields[1:], " ")

			// Detecter vraies sessions
			if user != "root" &&
				(strings.Contains(cmd, "sshd") || strings.Contains(cmd, "dropbear")) {
				userCounts[user]++
			}
		}
	}

	for _, line := range lines {
		if strings.TrimSpace(line) == "" {
			continue
		}

		parts := strings.Split(line, "|")
		if len(parts) < 3 {
			continue
		}

		username := parts[0]
		limite := parts[2]

		nb := userCounts[username]
		total += nb

		status := "🔴 HORS LIGNE"
		if nb > 0 {
			status = "🟢 EN LIGNE"
		}

		builder.WriteString(
			fmt.Sprintf("👤 %-10s : [ %d/%s ] %s\n", username, nb, limite, status),
		)
	}

	builder.WriteString("━━━━━━━━━━━━━━\n")
	builder.WriteString(fmt.Sprintf("📱 TOTAL CONNECTÉS : %d\n", total))

	return builder.String()
}

// Slice global des utilisateurs SSH
func chargerUtilisateursSSH() {
    utilisateursSSH = []UtilisateurSSH{}
    data, err := ioutil.ReadFile("/etc/kighmu/users.list")
    if err != nil {
        fmt.Println("⚠️ Impossible de lire users.list:", err)
        return
    }
    lignes := strings.Split(string(data), "\n")
    for _, l := range lignes {
        if l == "" {
            continue
        }
        parts := strings.Split(l, "|")
        if len(parts) >= 2 {
            utilisateursSSH = append(utilisateursSSH, UtilisateurSSH{
                Nom:    parts[0],
                Pass:   parts[1],
                Limite: 0,
                Expire: parts[2],
            })
        }
    }
}

func sauvegarderUtilisateursSSH() error {
    var lines []string
    for _, u := range utilisateursSSH {
        lines = append(lines, fmt.Sprintf("%s|%s|%d|%s|%s|%s|%s", u.Nom, u.Pass, u.Limite, u.Expire, u.HostIP, u.Domain, u.SlowDNS))
    }
    return ioutil.WriteFile("/etc/kighmu/users.list", []byte(strings.Join(lines, "\n")), 0600)
}

func gererModificationSSH(bot *tgbotapi.BotAPI, chatID int64, text string) {
    if len(utilisateursSSH) == 0 {
        bot.Send(tgbotapi.NewMessage(chatID, "❌ Aucun utilisateur SSH trouvé"))
        return
    }

    etat, ok := etatsModifs[chatID]
    if !ok || etat.Etape == "" {
        // Étape 1 : afficher liste
        msg := "📝   MODIFIER DUREE / MOT DE PASSE\n\nListe des utilisateurs :\n"
        for i, u := range utilisateursSSH {
            msg += fmt.Sprintf("[%02d] %s   (expire : %s)\n", i+1, u.Nom, u.Expire)
        }
        msg += "\nEntrez le(s) numéro(s) des utilisateurs à modifier (ex: 1,3) :"
        bot.Send(tgbotapi.NewMessage(chatID, msg))

        etatsModifs[chatID] = &EtatModification{Etape: "attente_numero"}
        return
    }

    switch etat.Etape {
    case "attente_numero":
        indicesStr := strings.Split(text, ",")
        var indices []int
        for _, s := range indicesStr {
            n, err := strconv.Atoi(strings.TrimSpace(s))
            if err != nil || n < 1 || n > len(utilisateursSSH) {
                bot.Send(tgbotapi.NewMessage(chatID, fmt.Sprintf("❌ Numéro invalide : %s", s)))
                delete(etatsModifs, chatID)
                return
            }
            indices = append(indices, n-1)
        }
        etat.Indices = indices
        etat.Etape = "attente_type"
        bot.Send(tgbotapi.NewMessage(chatID, "[01] Durée\n[02] Mot de passe\n[00] Retour\nChoix :"))

    case "attente_type":
        switch text {
        case "1", "01":
            etat.Type = "duree"
            etat.Etape = "attente_valeur"
            bot.Send(tgbotapi.NewMessage(chatID, "Entrez la nouvelle durée en jours (0 = pas d'expiration) :"))
        case "2", "02":
            etat.Type = "pass"
            etat.Etape = "attente_valeur"
            bot.Send(tgbotapi.NewMessage(chatID, "Entrez le nouveau mot de passe :"))
        case "0", "00":
            bot.Send(tgbotapi.NewMessage(chatID, "Retour au menu"))
            delete(etatsModifs, chatID)
        default:
            bot.Send(tgbotapi.NewMessage(chatID, "❌ Choix invalide"))
            delete(etatsModifs, chatID)
        }

    case "attente_valeur":
        if etat.Type == "duree" {
            jours, err := strconv.Atoi(text)
            if err != nil {
                bot.Send(tgbotapi.NewMessage(chatID, "❌ Durée invalide"))
                delete(etatsModifs, chatID)
                return
            }
            for _, i := range etat.Indices {
                utilisateursSSH[i].Expire = calculerNouvelleDate(jours)
                bot.Send(tgbotapi.NewMessage(chatID, fmt.Sprintf("✅ Durée modifiée pour %s", utilisateursSSH[i].Nom)))
            }
        } else if etat.Type == "pass" {
            for _, i := range etat.Indices {
                cmd := exec.Command("bash", "-c", fmt.Sprintf("echo -e '%s\n%s' | passwd %s", text, text, utilisateursSSH[i].Nom))
                cmd.Run()
                bot.Send(tgbotapi.NewMessage(chatID, fmt.Sprintf("✅ Mot de passe modifié pour %s", utilisateursSSH[i].Nom)))
            }
        }
        sauvegarderUtilisateursSSH()
        delete(etatsModifs, chatID)
    }
}

// Charger utilisateurs V2Ray depuis fichier
// ===============================
func chargerUtilisateursV2Ray() {
	utilisateursV2Ray = []UtilisateurV2Ray{}

	data, err := ioutil.ReadFile(v2rayFile)
	if err != nil {
		return
	}

	lignes := strings.Split(string(data), "\n")
	today := time.Now()

	for _, ligne := range lignes {
		ligne = strings.TrimSpace(ligne)
		if ligne == "" {
			continue
		}

		parts := strings.Split(ligne, "|")
		if len(parts) < 3 {
			continue
		}

		nom := strings.TrimSpace(parts[0])
		uuid := strings.TrimSpace(parts[1])
		expireStr := strings.TrimSpace(parts[2])

		expireDate, err := time.Parse("2006-01-02", expireStr)
		if err != nil {
			continue
		}

		// garder seulement les valides
		if !expireDate.Before(today) {
			utilisateursV2Ray = append(utilisateursV2Ray, UtilisateurV2Ray{
				Nom:    nom,
				UUID:   uuid,
				Expire: expireStr,
			})
		}
	}
}

func ajouterClientV2Ray(uuid, nom string) error {
	configFile := "/etc/v2ray/config.json"

	data, err := ioutil.ReadFile(configFile)
	if err != nil {
		return fmt.Errorf("Impossible de lire config.json : %v", err)
	}

	var config map[string]interface{}
	if err := json.Unmarshal(data, &config); err != nil {
		return fmt.Errorf("JSON invalide : %v", err)
	}

	inbounds, ok := config["inbounds"].([]interface{})
	if !ok {
		return fmt.Errorf("Structure inbounds invalide")
	}

	for _, inbound := range inbounds {
		inb, ok := inbound.(map[string]interface{})
		if !ok {
			continue
		}
		if proto, ok := inb["protocol"].(string); ok && proto == "vless" {
			settings, ok := inb["settings"].(map[string]interface{})
			if !ok {
				continue
			}

			clients, ok := settings["clients"].([]interface{})
			if !ok {
				clients = []interface{}{}
			}

			existe := false
			for _, c := range clients {
				clientMap, ok := c.(map[string]interface{})
				if !ok {
					continue
				}
				if clientMap["id"] == uuid {
					existe = true
					break
				}
			}
			if existe {
				return fmt.Errorf("UUID %s déjà existant", uuid)
			}

			nouveauClient := map[string]interface{}{
				"id":    uuid,
				"email": nom,
			}
			clients = append(clients, nouveauClient)
			settings["clients"] = clients
			inb["settings"] = settings
		}
	}

	newData, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return fmt.Errorf("Erreur lors du marshalling JSON : %v", err)
	}

	if err := ioutil.WriteFile(configFile, newData, 0644); err != nil {
		return fmt.Errorf("Impossible d'écrire config.json : %v", err)
	}

	cmd := exec.Command("systemctl", "restart", "v2ray")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("Impossible de redémarrer V2Ray : %v", err)
	}

	return nil
}

// Enregistrer un utilisateur V2Ray dans le fichier
// ===============================
func enregistrerUtilisateurV2Ray(u UtilisateurV2Ray) error {
	file := "/etc/v2ray/utilisateurs.json"

	data, _ := ioutil.ReadFile(file)

	var users []map[string]string
	json.Unmarshal(data, &users)

	users = append(users, map[string]string{
		"nom":    u.Nom,
		"uuid":   u.UUID,
		"expire": u.Expire,
	})

	newData, err := json.MarshalIndent(users, "", "  ")
	if err != nil {
		return err
	}

	return ioutil.WriteFile(file, newData, 0644)
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

	// ⚡️ Ajouter l'UUID dans config.json V2Ray
	if err := ajouterClientV2Ray(u.UUID, u.Nom); err != nil {
		return fmt.Sprintf("❌ Erreur ajout UUID dans config.json : %v", err)
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

	for _, user := range utilisateursV2Ray {
		f.WriteString(fmt.Sprintf("%s|%s|%s\n", user.Nom, user.UUID, user.Expire))
	}

	// Supprimer l'utilisateur du config.json V2Ray
	if err := supprimerClientV2Ray(u.UUID); err != nil {
		return fmt.Sprintf("⚠️ Utilisateur supprimé du fichier, mais erreur V2Ray : %v", err)
	}

	return fmt.Sprintf("✅ Utilisateur %s supprimé.", u.Nom)
}

func supprimerClientV2Ray(uuid string) error {
	configFile := "/etc/v2ray/config.json"

	data, err := ioutil.ReadFile(configFile)
	if err != nil {
		return fmt.Errorf("Impossible de lire config.json : %v", err)
	}

	var config map[string]interface{}
	if err := json.Unmarshal(data, &config); err != nil {
		return fmt.Errorf("JSON invalide : %v", err)
	}

	inbounds, ok := config["inbounds"].([]interface{})
	if !ok {
		return fmt.Errorf("Structure inbounds invalide")
	}

	modifie := false

	for i, inbound := range inbounds {
		inb, ok := inbound.(map[string]interface{})
		if !ok {
			continue
		}
		if proto, ok := inb["protocol"].(string); ok && proto == "vless" {
			settings, ok := inb["settings"].(map[string]interface{})
			if !ok {
				continue
			}
			clients, ok := settings["clients"].([]interface{})
			if !ok {
				continue
			}

			nouveauxClients := []interface{}{}
			for _, c := range clients {
				clientMap, ok := c.(map[string]interface{})
				if !ok {
					continue
				}
				if clientMap["id"] != uuid {
					nouveauxClients = append(nouveauxClients, clientMap)
				} else {
					modifie = true
				}
			}
			settings["clients"] = nouveauxClients
			inb["settings"] = settings
			inbounds[i] = inb
		}
	}

	config["inbounds"] = inbounds

	if !modifie {
		return nil
	}

	newData, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return fmt.Errorf("Erreur lors du marshalling JSON : %v", err)
	}

	if err := ioutil.WriteFile(configFile, newData, 0644); err != nil {
		return fmt.Errorf("Impossible d'écrire config.json : %v", err)
	}

	cmd := exec.Command("systemctl", "restart", "v2ray")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("Impossible de redémarrer V2Ray : %v", err)
	}

	return nil
}

// Lancement Bot Telegram
// ===============================

func lancerBot() {

	// ================= TOKEN CHECK =================
	botToken = os.Getenv("BOT_TOKEN")
	if botToken == "" {
		fmt.Println("❌ BOT_TOKEN non défini (export BOT_TOKEN=xxxx)")
		return
	}

	bot, err := tgbotapi.NewBotAPI(botToken)
	if err != nil {
		fmt.Println("❌ Impossible de créer le bot:", err)
		return
	}

	fmt.Println("🤖 Bot Telegram démarré :", bot.Self.UserName)

	// ================= COMMANDES TELEGRAM =================
	commands := []tgbotapi.BotCommand{
		{Command: "kighmu", Description: "Ouvrir le panneau principal"},
		{Command: "help", Description: "Guide complet d'utilisation"},
	}

	_, err = bot.Request(tgbotapi.NewSetMyCommands(commands...))
	if err != nil {
		fmt.Println("❌ Erreur setMyCommands:", err)
	} else {
		fmt.Println("✅ Menu Telegram configuré")
	}

	// ================= LOAD DATA =================
	chargerUtilisateursSSH()
	chargerUtilisateursV2Ray()

	u := tgbotapi.NewUpdate(0)
	u.Timeout = 60

	updates := bot.GetUpdatesChan(u)

	modeSupprimerMultiple := make(map[int64]bool)

	for update := range updates {

		var chatID int64
		var userID int64

		// ================= IDENTIFICATION =================
		if update.CallbackQuery != nil && update.CallbackQuery.Message != nil {
			chatID = update.CallbackQuery.Message.Chat.ID
			userID = int64(update.CallbackQuery.From.ID)
		} else if update.Message != nil {
			chatID = update.Message.Chat.ID
			userID = int64(update.Message.From.ID)
		} else {
			continue
		}

		// ================= ADMIN PROTECTION =================
		if userID != adminID {

			if update.CallbackQuery != nil {
				callback := tgbotapi.NewCallback(update.CallbackQuery.ID, "⛔ Accès refusé")
				bot.Request(callback)
			}
			continue
		}

		// ====================================================
		// ================= CALLBACK ==========================
		// ====================================================

		if update.CallbackQuery != nil {

			data := update.CallbackQuery.Data
			bot.Request(tgbotapi.NewCallback(update.CallbackQuery.ID, "✅"))

			switch data {

			case "menu1":
				bot.Send(tgbotapi.NewMessage(chatID,
					"Envoyez : username,password,limite,jours"))

			case "menu2":
				bot.Send(tgbotapi.NewMessage(chatID,
					"Envoyez : username,password,limite,minutes"))

			case "v2ray_creer":
				bot.Send(tgbotapi.NewMessage(chatID,
					"Envoyez : nom,duree"))

			case "v2ray_supprimer":

				if len(utilisateursV2Ray) == 0 {
					bot.Send(tgbotapi.NewMessage(chatID,
						"❌ Aucun utilisateur V2Ray à supprimer"))
					continue
				}

				txt := "📋 Liste des utilisateurs V2Ray :\n\n"
				for i, u := range utilisateursV2Ray {
					txt += fmt.Sprintf("%d) %s | UUID: %s | Expire: %s\n",
						i+1, u.Nom, u.UUID, u.Expire)
				}
				txt += "\nEnvoyez le numéro à supprimer"

				bot.Send(tgbotapi.NewMessage(chatID, txt))

			case "supprimer_multi":
				modeSupprimerMultiple[chatID] = true
				bot.Send(tgbotapi.NewMessage(chatID,
					"Envoyez les noms séparés par virgules : user1,user2,user3"))

			case "voir_appareils":
				bot.Send(tgbotapi.NewMessage(chatID, resumeAppareils()))

			case "modifier_ssh":
				etatsModifs[chatID] = &EtatModification{Etape: ""}
				gererModificationSSH(bot, chatID, "")
			}

			continue
		}

		// ====================================================
		// ================= MESSAGE ===========================
		// ====================================================

		if update.Message == nil || update.Message.Text == "" {
			continue
		}

		text := strings.TrimSpace(update.Message.Text)

		// ================= MENU PRINCIPAL =================
		if text == "/kighmu" {

			msgText := `============================================
🚀 𝗞𝗜𝗚𝗛𝗠𝗨 𝗠𝗔𝗡𝗔𝗚𝗘𝗥 🇨🇲
============================================
👤 AUTEUR : @𝐊𝐈𝐆𝐇𝐌𝐔
📢 CANAL TELEGRAM :
https://t.me/lkgcddtoogv
============================================
𝔾𝕖𝕤𝕥𝕚𝕠𝕟 𝕔𝕠𝕞𝕡𝕝𝕖𝕥𝕖 :

• SSH (jours / minutes)
• V2Ray + FastDNS
• Suppression multiple
• Modification SSH (durée/password)
• Statistiques appareils
============================================`

			keyboard := tgbotapi.NewInlineKeyboardMarkup(
				tgbotapi.NewInlineKeyboardRow(
					tgbotapi.NewInlineKeyboardButtonData("Compte_SSH (jours)", "menu1"),
					tgbotapi.NewInlineKeyboardButtonData("Compte_SSH test(minutes)", "menu2"),
				),
				tgbotapi.NewInlineKeyboardRow(
					tgbotapi.NewInlineKeyboardButtonData("➕ Compte V2Ray+FastDNS", "v2ray_creer"),
					tgbotapi.NewInlineKeyboardButtonData("➖ Supprimer V2Ray+FastDNS", "v2ray_supprimer"),
				),
				tgbotapi.NewInlineKeyboardRow(
					tgbotapi.NewInlineKeyboardButtonData("❌ Supprimer SSH(s)", "supprimer_multi"),
				),
				tgbotapi.NewInlineKeyboardRow(
					tgbotapi.NewInlineKeyboardButtonData("📊 APPAREILS", "voir_appareils"),
					tgbotapi.NewInlineKeyboardButtonData("📝 MODIFIER SSH", "modifier_ssh"),
				),
			)

			msg := tgbotapi.NewMessage(chatID, msgText)
			msg.ReplyMarkup = keyboard
			bot.Send(msg)
			continue
		}

		// ================= HELP COMPLET =================
		if text == "/help" {

			helpText := `📘 GUIDE COMPLET - KIGHMU MANAGER

1️⃣ SSH (jours)
username,password,limite,jours

2️⃣ SSH test (minutes)
username,password,limite,minutes

3️⃣ V2Ray
nom,duree (jours)

4️⃣ Suppression V2Ray
Envoyer numéro affiché.

5️⃣ Suppression multiple SSH
user1,user2,user3

6️⃣ APPAREILS
Affiche connexions actives.

7️⃣ MODIFIER SSH
Modifier mot de passe / limite / expiration.

⚠️ Respecter strictement le format.
Séparer uniquement par virgules.`

			bot.Send(tgbotapi.NewMessage(chatID, helpText))
			continue
		}

		// ================= SUPPRESSION MULTIPLE =================
		if modeSupprimerMultiple[chatID] {
			traiterSuppressionMultiple(bot, chatID, text)
			delete(modeSupprimerMultiple, chatID)
			chargerUtilisateursSSH()
			continue
		}

		// ================= MODIFICATION SSH =================
		if _, ok := etatsModifs[chatID]; ok {
			gererModificationSSH(bot, chatID, text)
			chargerUtilisateursSSH()
			continue
		}

		// ================= SSH CREATION =================
		if strings.Count(text, ",") == 3 {

			p := strings.Split(text, ",")
			username := strings.TrimSpace(p[0])
			password := strings.TrimSpace(p[1])
			limite, err1 := strconv.Atoi(strings.TrimSpace(p[2]))
			duree, err2 := strconv.Atoi(strings.TrimSpace(p[3]))

			if err1 != nil || err2 != nil {
				bot.Send(tgbotapi.NewMessage(chatID, "❌ Paramètres invalides"))
				continue
			}

			if duree <= 1440 {
				bot.Send(tgbotapi.NewMessage(chatID,
					creerUtilisateurTest(username, password, limite, duree)))
			} else {
				bot.Send(tgbotapi.NewMessage(chatID,
					creerUtilisateurNormal(username, password, limite, duree)))
			}

			chargerUtilisateursSSH()
			continue
		}

		// ================= V2RAY CREATION =================
		if strings.Count(text, ",") == 1 {

			p := strings.Split(text, ",")
			nom := strings.TrimSpace(p[0])
			duree, err := strconv.Atoi(strings.TrimSpace(p[1]))

			if err != nil {
				bot.Send(tgbotapi.NewMessage(chatID, "❌ Durée invalide"))
				continue
			}

			bot.Send(tgbotapi.NewMessage(chatID,
				creerUtilisateurV2Ray(nom, duree)))

			chargerUtilisateursV2Ray()
			continue
		}

		// ================= SUPPRESSION V2RAY =================
		if num, err := strconv.Atoi(text); err == nil &&
			num > 0 && num <= len(utilisateursV2Ray) {

			bot.Send(tgbotapi.NewMessage(chatID,
				supprimerUtilisateurV2Ray(num-1)))

			chargerUtilisateursV2Ray()
			continue
		}

		bot.Send(tgbotapi.NewMessage(chatID,
			"❌ Commande ou format inconnu"))
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
	chargerUtilisateursSSH()
	lancerBot()
}
