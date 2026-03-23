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
	"sort"
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
	Nom     string
	UUID    string
	Expire  string
	LimitGB int
}

var utilisateursV2Ray []UtilisateurV2Ray

// Structures Xray (VMess / VLESS / Trojan)
// ===============================
type UtilisateurXray struct {
	Proto   string // "vmess", "vless", "trojan"
	Nom     string
	UUID    string // uuid pour vmess/vless, password pour trojan
	Tag     string
	LimitGB int
	Expire  string
}

// Etats machine pour la creation Xray (multi-etapes)
type EtatXray struct {
	Proto string // "vmess", "vless", "trojan"
	Etape string // "nom", "quota", "duree"
	Nom   string
	Quota int
}

var etatsXray = make(map[int64]*EtatXray)
var modeSupprimerXray = make(map[int64]bool)

// Etat machine pour creation V2Ray multi-etapes (nom → quota → duree)
type EtatV2Ray struct {
	Etape string // "nom", "quota", "duree"
	Nom   string
	Quota int
}

var etatsV2Ray = make(map[int64]*EtatV2Ray)
var xrayConfigFile = "/etc/xray/config.json"
var xrayUsersFile  = "/etc/xray/users.json"


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

		// Lire limitGB si présent (colonne 4)
		limitGB := 0
		if len(parts) >= 4 {
			if v, e := strconv.Atoi(strings.TrimSpace(parts[3])); e == nil {
				limitGB = v
			}
		}

		// garder seulement les valides
		if !expireDate.Before(today) {
			utilisateursV2Ray = append(utilisateursV2Ray, UtilisateurV2Ray{
				Nom:     nom,
				UUID:    uuid,
				Expire:  expireStr,
				LimitGB: limitGB,
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
func creerUtilisateurV2Ray(nom string, limitGB int, duree int) string {
	uuid := genererUUID()
	expire := time.Now().AddDate(0, 0, duree).Format("2006-01-02")

	// Ajouter au slice et fichier
	u := UtilisateurV2Ray{Nom: nom, UUID: uuid, Expire: expire, LimitGB: limitGB}
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


// ================================================================
// FONCTIONS XRAY — VMess / VLESS / Trojan
// Même logique que menu_6.sh : users.json + config.json + xray reload
// ================================================================

// Charger tous les utilisateurs Xray depuis /etc/xray/users.json
func chargerUtilisateursXray() []UtilisateurXray {
	var liste []UtilisateurXray

	data, err := ioutil.ReadFile(xrayUsersFile)
	if err != nil {
		return liste
	}

	var js map[string][]map[string]interface{}
	if err := json.Unmarshal(data, &js); err != nil {
		return liste
	}

	for _, proto := range []string{"vmess", "vless", "trojan"} {
		clients, ok := js[proto]
		if !ok {
			continue
		}
		for _, c := range clients {
			u := UtilisateurXray{Proto: proto}
			if v, ok := c["name"].(string); ok {
				u.Nom = v
			}
			if v, ok := c["tag"].(string); ok {
				u.Tag = v
			}
			if v, ok := c["expire"].(string); ok {
				u.Expire = v
			}
			if v, ok := c["limit_gb"].(float64); ok {
				u.LimitGB = int(v)
			}
			if proto == "trojan" {
				if v, ok := c["password"].(string); ok {
					u.UUID = v
				}
			} else {
				if v, ok := c["uuid"].(string); ok {
					u.UUID = v
				}
			}
			liste = append(liste, u)
		}
	}
	return liste
}

// Creer un utilisateur Xray (vmess/vless/trojan) — meme logique que create_config() de menu_6.sh
func creerUtilisateurXray(proto, nom string, limitGB, days int) string {
	// Lire le domaine
	domain := DOMAIN
	if domain == "" {
		data, _ := ioutil.ReadFile("/etc/xray/domain")
		domain = strings.TrimSpace(string(data))
	}
	if domain == "" {
		data, _ := ioutil.ReadFile("/tmp/.xray_domain")
		domain = strings.TrimSpace(string(data))
	}
	if domain == "" {
		return "❌ Domaine Xray non defini (/etc/xray/domain introuvable)"
	}

	// Generer UUID et tag
	uuid := genererUUID()
	tag := fmt.Sprintf("%s_%s_%s", proto, nom, uuid[:8])
	expDate := time.Now().AddDate(0, 0, days).Format("2006-01-02")

	// Ports et paths (identiques a menu_6.sh)
	portTLS  := 8443
	portNTLS := 8880
	var pathWS, pathGRPC string
	switch proto {
	case "vmess":
		pathWS   = "/vmess"
		pathGRPC = "vmess-grpc"
	case "vless":
		pathWS   = "/vless"
		pathGRPC = "vless-grpc"
	case "trojan":
		pathWS   = "/trojan-ws"
		pathGRPC = "trojan-grpc"
	}

	// --- Mise a jour users.json ---
	usersData, _ := ioutil.ReadFile(xrayUsersFile)
	var js map[string]interface{}
	if err := json.Unmarshal(usersData, &js); err != nil || js == nil {
		js = map[string]interface{}{
			"vmess":  []interface{}{},
			"vless":  []interface{}{},
			"trojan": []interface{}{},
		}
	}

	// S'assurer que le tableau du protocole existe
	if _, ok := js[proto]; !ok {
		js[proto] = []interface{}{}
	}

	var newClient map[string]interface{}
	if proto == "trojan" {
		newClient = map[string]interface{}{
			"password": uuid, "email": tag, "name": nom,
			"tag": tag, "limit_gb": limitGB, "used_gb": 0, "expire": expDate,
		}
	} else {
		newClient = map[string]interface{}{
			"uuid": uuid, "email": tag, "name": nom,
			"tag": tag, "limit_gb": limitGB, "used_gb": 0, "expire": expDate,
		}
	}

	if arr, ok := js[proto].([]interface{}); ok {
		js[proto] = append(arr, newClient)
	}

	newUsersData, err := json.MarshalIndent(js, "", "  ")
	if err != nil {
		return fmt.Sprintf("❌ Erreur JSON users.json : %v", err)
	}
	if err := ioutil.WriteFile(xrayUsersFile, newUsersData, 0644); err != nil {
		return fmt.Sprintf("❌ Erreur ecriture users.json : %v", err)
	}

	// --- Mise a jour config.json ---
	cfgData, err := ioutil.ReadFile(xrayConfigFile)
	if err != nil {
		return fmt.Sprintf("❌ Impossible de lire config.json : %v", err)
	}
	var cfg map[string]interface{}
	if err := json.Unmarshal(cfgData, &cfg); err != nil {
		return fmt.Sprintf("❌ config.json invalide : %v", err)
	}

	inbounds, _ := cfg["inbounds"].([]interface{})
	for _, inb := range inbounds {
		inbMap, ok := inb.(map[string]interface{})
		if !ok {
			continue
		}
		p, _ := inbMap["protocol"].(string)
		if p != proto {
			continue
		}
		settings, _ := inbMap["settings"].(map[string]interface{})
		if settings == nil {
			settings = map[string]interface{}{}
			inbMap["settings"] = settings
		}
		clients, _ := settings["clients"].([]interface{})
		if proto == "trojan" {
			clients = append(clients, map[string]interface{}{
				"password": uuid, "email": tag,
			})
		} else {
			clients = append(clients, map[string]interface{}{
				"id": uuid, "alterId": 0, "email": tag,
			})
		}
		settings["clients"] = clients
	}
	cfg["inbounds"] = inbounds

	newCfgData, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return fmt.Sprintf("❌ Erreur JSON config.json : %v", err)
	}
	if err := ioutil.WriteFile(xrayConfigFile, newCfgData, 0644); err != nil {
		return fmt.Sprintf("❌ Erreur ecriture config.json : %v", err)
	}

	// Sauvegarder expiration
	expLine := fmt.Sprintf("%s|%s\n", uuid, expDate)
	f, _ := os.OpenFile("/etc/xray/users_expiry.list", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if f != nil {
		f.WriteString(expLine)
		f.Close()
	}

	// Reload Xray
	if err := exec.Command("systemctl", "reload", "xray").Run(); err != nil {
		exec.Command("systemctl", "restart", "xray").Run()
	}

	// Generer les liens (identiques a menu_6.sh)
	var linkTLS, linkNTLS, linkGRPC string
	switch proto {
	case "vmess":
		jsonTLS  := fmt.Sprintf(`{"v":"2","ps":"%s","add":"%s","port":"%d","id":"%s","aid":0,"net":"ws","type":"none","host":"%s","path":"%s","tls":"tls","sni":"%s"}`, nom, domain, portTLS, uuid, domain, pathWS, domain)
		jsonNTLS := fmt.Sprintf(`{"v":"2","ps":"%s","add":"%s","port":"%d","id":"%s","aid":0,"net":"ws","type":"none","host":"%s","path":"%s","tls":"none"}`, nom, domain, portNTLS, uuid, domain, pathWS)
		jsonGRPC := fmt.Sprintf(`{"v":"2","ps":"%s","add":"%s","port":"%d","id":"%s","aid":0,"net":"grpc","type":"none","host":"%s","path":"vmess-grpc","tls":"tls","sni":"%s"}`, nom, domain, portTLS, uuid, domain, domain)
		b64TLS, _ := exec.Command("bash", "-c", fmt.Sprintf(`echo -n '%s' | base64 -w0`, jsonTLS)).Output()
		b64NTLS, _ := exec.Command("bash", "-c", fmt.Sprintf(`echo -n '%s' | base64 -w0`, jsonNTLS)).Output()
		b64GRPC, _ := exec.Command("bash", "-c", fmt.Sprintf(`echo -n '%s' | base64 -w0`, jsonGRPC)).Output()
		linkTLS  = "vmess://" + strings.TrimSpace(string(b64TLS))
		linkNTLS = "vmess://" + strings.TrimSpace(string(b64NTLS))
		linkGRPC = "vmess://" + strings.TrimSpace(string(b64GRPC))
	case "vless", "trojan":
		linkTLS  = fmt.Sprintf("%s://%s@%s:%d?security=tls&type=ws&path=%s&host=%s&sni=%s#%s", proto, uuid, domain, portTLS, pathWS, domain, domain, nom)
		linkNTLS = fmt.Sprintf("%s://%s@%s:%d?security=none&type=ws&path=%s&host=%s#%s", proto, uuid, domain, portNTLS, pathWS, domain, nom)
		linkGRPC = fmt.Sprintf("%s://%s@%s:%d?mode=grpc&security=tls&serviceName=%s#%s", proto, uuid, domain, portTLS, pathGRPC, nom)
	}

	var b strings.Builder
	b.WriteString(fmt.Sprintf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"))
	b.WriteString(fmt.Sprintf("🧩 %s — %s\n", strings.ToUpper(proto), nom))
	b.WriteString(fmt.Sprintf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"))
	b.WriteString(fmt.Sprintf("🌍 Domaine   : %s\n", domain))
	b.WriteString(fmt.Sprintf("🔑 UUID/Pass : %s\n", uuid))
	b.WriteString(fmt.Sprintf("📦 Quota     : %d Go\n", limitGB))
	b.WriteString(fmt.Sprintf("📅 Expiration: %s\n", expDate))
	b.WriteString(fmt.Sprintf("🔌 Port TLS  : %d | Non-TLS : %d\n", portTLS, portNTLS))
	b.WriteString(fmt.Sprintf("📂 Path WS   : %s | gRPC : %s\n", pathWS, pathGRPC))
	b.WriteString("\n━━━━━━━━━━━━━ LIENS ━━━━━━━━━━━━━\n")
	b.WriteString(fmt.Sprintf("📡 TLS WS     : %s\n", linkTLS))
	b.WriteString(fmt.Sprintf("📡 Non-TLS WS : %s\n", linkNTLS))
	b.WriteString(fmt.Sprintf("📡 gRPC TLS   : %s\n", linkGRPC))
	b.WriteString("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
	b.WriteString("✅ COMPTE XRAY CREE AVEC SUCCES\n")
	b.WriteString("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

	return b.String()
}

// Supprimer un utilisateur Xray par index (base 1) parmi la liste combinee
// Meme logique que delete_user_by_number() de menu_6.sh
func supprimerUtilisateursXray(indices []int) string {
	liste := chargerUtilisateursXray()
	if len(liste) == 0 {
		return "❌ Aucun utilisateur Xray"
	}

	// Verifier tous les indices
	for _, idx := range indices {
		if idx < 1 || idx > len(liste) {
			return fmt.Sprintf("❌ Numero invalide : %d (total : %d)", idx, len(liste))
		}
	}

	// Trier les indices en ordre decroissant pour supprimer sans decaler
	sort.Sort(sort.Reverse(sort.IntSlice(indices)))

	var results []string

	for _, idx := range indices {
		u := liste[idx-1]

		// --- Supprimer de users.json ---
		usersData, err := ioutil.ReadFile(xrayUsersFile)
		if err != nil {
			results = append(results, fmt.Sprintf("❌ %s : Erreur lecture users.json", u.Nom))
			continue
		}
		var js map[string]interface{}
		json.Unmarshal(usersData, &js)

		if arr, ok := js[u.Proto].([]interface{}); ok {
			var newArr []interface{}
			for _, c := range arr {
				cm, ok := c.(map[string]interface{})
				if !ok {
					continue
				}
				keep := true
				if u.Proto == "trojan" {
					if cm["password"] == u.UUID {
						keep = false
					}
				} else {
					if cm["uuid"] == u.UUID {
						keep = false
					}
				}
				if keep {
					newArr = append(newArr, cm)
				}
			}
			if newArr == nil {
				newArr = []interface{}{}
			}
			js[u.Proto] = newArr
		}
		newUsersData, _ := json.MarshalIndent(js, "", "  ")
		ioutil.WriteFile(xrayUsersFile, newUsersData, 0644)

		// --- Supprimer de config.json ---
		cfgData, err := ioutil.ReadFile(xrayConfigFile)
		if err != nil {
			results = append(results, fmt.Sprintf("⚠️ %s supprime de users.json, erreur config.json", u.Nom))
			continue
		}
		var cfg map[string]interface{}
		json.Unmarshal(cfgData, &cfg)

		if inbounds, ok := cfg["inbounds"].([]interface{}); ok {
			for _, inb := range inbounds {
				inbMap, ok := inb.(map[string]interface{})
				if !ok {
					continue
				}
				p, _ := inbMap["protocol"].(string)
				if p != u.Proto {
					continue
				}
				settings, _ := inbMap["settings"].(map[string]interface{})
				if settings == nil {
					continue
				}
				clients, _ := settings["clients"].([]interface{})
				var newClients []interface{}
				for _, c := range clients {
					cm, ok := c.(map[string]interface{})
					if !ok {
						continue
					}
					keep := true
					if u.Proto == "trojan" {
						if cm["password"] == u.UUID {
							keep = false
						}
					} else {
						if cm["id"] == u.UUID {
							keep = false
						}
					}
					if keep {
						newClients = append(newClients, cm)
					}
				}
				if newClients == nil {
					newClients = []interface{}{}
				}
				settings["clients"] = newClients
			}
			cfg["inbounds"] = inbounds
		}
		newCfgData, _ := json.MarshalIndent(cfg, "", "  ")
		ioutil.WriteFile(xrayConfigFile, newCfgData, 0644)

		// Nettoyer expiry list
		exec.Command("bash", "-c", fmt.Sprintf("sed -i '/^%s|/d' /etc/xray/users_expiry.list 2>/dev/null", u.UUID)).Run()

		results = append(results, fmt.Sprintf("✅ %s (%s) supprime", u.Nom, u.Proto))
	}

	// Recharger Xray une seule fois
	if err := exec.Command("systemctl", "reload", "xray").Run(); err != nil {
		exec.Command("systemctl", "restart", "xray").Run()
	}

	return strings.Join(results, "\n")
}

// Afficher la liste numerotee des utilisateurs Xray pour suppression
func listeXrayPourSuppression() string {
	liste := chargerUtilisateursXray()
	if len(liste) == 0 {
		return "❌ Aucun utilisateur Xray enregistre"
	}
	var b strings.Builder
	b.WriteString("📋 Liste des utilisateurs Xray :\n\n")
	for i, u := range liste {
		b.WriteString(fmt.Sprintf("[%02d] %s | %s | Exp: %s | %dGo\n",
			i+1, u.Proto, u.Nom, u.Expire, u.LimitGB))
	}
	b.WriteString("\nEnvoyez le(s) numero(s) a supprimer (ex: 1 ou 1,3,5) :")
	return b.String()
}


// ================================================================
// CONSOMMATION — lecture directe des fichiers .usage
// générés par le service kighmu-bandwidth.sh
// ================================================================

const bwDir = "/var/lib/kighmu/bandwidth"

// lireUsageBytes lit le cumul en bytes depuis un fichier .usage
// Retourne 0 si le fichier n'existe pas ou est invalide
func lireUsageBytes(path string) int64 {
	data, err := ioutil.ReadFile(path)
	if err != nil {
		return 0
	}
	val, err := strconv.ParseInt(strings.TrimSpace(string(data)), 10, 64)
	if err != nil {
		return 0
	}
	return val
}

// formatBytes formate des bytes en MB ou GB selon la taille
func formatBytes(bytes int64) string {
	if bytes <= 0 {
		return "0 B"
	}
	if bytes < 1024 {
		return fmt.Sprintf("%d B", bytes)
	}
	kb := float64(bytes) / 1024.0
	if kb < 1024.0 {
		return fmt.Sprintf("%.1f KB", kb)
	}
	mb := float64(bytes) / 1048576.0
	if mb < 1024.0 {
		return fmt.Sprintf("%.2f MB", mb)
	}
	gb := float64(bytes) / 1073741824.0
	return fmt.Sprintf("%.2f GB", gb)
}

// indicateur retourne un emoji selon le pourcentage consommé
func indicateur(used int64, limitGB int) string {
	if limitGB <= 0 {
		return ""
	}
	pct := float64(used) / float64(int64(limitGB)*1073741824) * 100.0
	if pct >= 100.0 {
		return "🔴"
	} else if pct >= 90.0 {
		return "🟡"
	}
	return "🟢"
}


// consommationXray lit les fichiers .usage Xray + users.json pour le quota
func consommationXray() string {
	liste := chargerUtilisateursXray()
	if len(liste) == 0 {
		return "❌ Aucun utilisateur Xray enregistré"
	}

	var b strings.Builder
	b.WriteString("📊 CONSOMMATION XRAY\n")
	b.WriteString("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

	for i, u := range liste {
		// Lire depuis le fichier .usage du service bandwidth
		usageFile := fmt.Sprintf("%s/%s.usage", bwDir, u.Nom)
		totalBytes := lireUsageBytes(usageFile)

		var consoStr string
		ind := indicateur(totalBytes, u.LimitGB)
		if u.LimitGB <= 0 {
			consoStr = fmt.Sprintf("%s / ∞", formatBytes(totalBytes))
		} else {
			limitBytes := int64(u.LimitGB) * 1073741824
			pct := float64(totalBytes) / float64(limitBytes) * 100.0
			consoStr = fmt.Sprintf("%s %s / %d GB (%.0f%%)",
				ind, formatBytes(totalBytes), u.LimitGB, pct)
		}

		b.WriteString(fmt.Sprintf("[%02d] %-12s %-7s %s | Exp:%s\n",
			i+1, u.Nom, u.Proto, consoStr, u.Expire))
	}
	b.WriteString("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
	return b.String()
}

// consommationV2Ray lit les fichiers .usage V2Ray
func consommationV2Ray() string {
	chargerUtilisateursV2Ray()
	if len(utilisateursV2Ray) == 0 {
		return "❌ Aucun utilisateur V2Ray enregistré"
	}

	var b strings.Builder
	b.WriteString("📊 CONSOMMATION V2RAY+FASTDNS\n")
	b.WriteString("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

	for i, u := range utilisateursV2Ray {
		usageFile := fmt.Sprintf("%s/%s.usage", bwDir, u.Nom)
		totalBytes := lireUsageBytes(usageFile)

		var consoStr string
		ind := indicateur(totalBytes, u.LimitGB)
		if u.LimitGB <= 0 {
			consoStr = fmt.Sprintf("%s / ∞", formatBytes(totalBytes))
		} else {
			limitBytes := int64(u.LimitGB) * 1073741824
			pct := float64(totalBytes) / float64(limitBytes) * 100.0
			consoStr = fmt.Sprintf("%s %s / %d GB (%.0f%%)",
				ind, formatBytes(totalBytes), u.LimitGB, pct)
		}

		b.WriteString(fmt.Sprintf("[%02d] %-14s %s | Exp:%s\n",
			i+1, u.Nom, consoStr, u.Expire))
	}
	b.WriteString("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
	return b.String()
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

	// ================== SET BOT COMMANDS ==================
	commands := []tgbotapi.BotCommand{
		{
			Command:     "kighmu",
			Description: "Ouvrir le panneau principal",
		},
		{
			Command:     "help",
			Description: "Guide complet d'utilisation",
		},
	}

	config := tgbotapi.NewSetMyCommands(commands...)
	_, err = bot.Request(config)
	if err != nil {
		fmt.Println("❌ Erreur setMyCommands:", err)
	} else {
		fmt.Println("✅ Menu Telegram configuré")
	}
	// ======================================================

	// Charger utilisateurs SSH
	chargerUtilisateursSSH()

	u := tgbotapi.NewUpdate(0)
	u.Timeout = 60

	// ✅ CORRECTION ICI (v5 retourne 1 seule valeur)
	updates := bot.GetUpdatesChan(u)

	modeSupprimerMultiple := make(map[int64]bool)

	for update := range updates {

		var chatID int64

		if update.CallbackQuery != nil {
			chatID = update.CallbackQuery.Message.Chat.ID
		} else if update.Message != nil {
			chatID = update.Message.Chat.ID
		}

		// ================= ADMIN CHECK =================
		if update.CallbackQuery != nil && int64(update.CallbackQuery.From.ID) != adminID {
			callback := tgbotapi.NewCallback(update.CallbackQuery.ID, "⛔ Accès refusé")
			bot.Request(callback)
			continue
		}

		if update.Message != nil && int64(update.Message.From.ID) != adminID {
			continue
		}

		// ================= CALLBACK =================
		if update.CallbackQuery != nil {

			data := update.CallbackQuery.Data

			// ✅ CORRECTION v5
			callback := tgbotapi.NewCallback(update.CallbackQuery.ID, "✅ Exécution...")
			bot.Request(callback)

			switch data {

			case "menu1":
				bot.Send(tgbotapi.NewMessage(chatID, "Envoyez : username,password,limite,jours"))

			case "menu2":
				bot.Send(tgbotapi.NewMessage(chatID, "Envoyez : username,password,limite,minutes"))

			case "v2ray_creer":
				etatsV2Ray[chatID] = &EtatV2Ray{Etape: "nom"}
				bot.Send(tgbotapi.NewMessage(chatID, "➕ V2Ray+FastDNS\nEntrez le nom d'utilisateur :"))

			case "v2ray_supprimer":
				if len(utilisateursV2Ray) == 0 {
					bot.Send(tgbotapi.NewMessage(chatID, "❌ Aucun utilisateur V2Ray à supprimer"))
					continue
				}

				txt := "Liste des utilisateurs V2Ray :\n"
				for i, u := range utilisateursV2Ray {
					txt += fmt.Sprintf("%d) %s | UUID: %s | Expire: %s\n",
						i+1, u.Nom, u.UUID, u.Expire)
				}
				txt += "\nEnvoyez le numéro à supprimer"
				bot.Send(tgbotapi.NewMessage(chatID, txt))

			case "supprimer_multi":
				bot.Send(tgbotapi.NewMessage(chatID,
					"Envoyez les noms séparés par virgules : user1,user2,user3"))
				modeSupprimerMultiple[chatID] = true

			case "conso_xray":
				bot.Send(tgbotapi.NewMessage(chatID, consommationXray()))

			case "conso_v2ray":
				bot.Send(tgbotapi.NewMessage(chatID, consommationV2Ray()))

			case "voir_appareils":
				bot.Send(tgbotapi.NewMessage(chatID, resumeAppareils()))

			case "modifier_ssh":
				etatsModifs[chatID] = &EtatModification{Etape: ""}
				gererModificationSSH(bot, chatID, "")

			// ── Boutons Xray ───────────────────────────────────
			case "xray_vmess":
				etatsXray[chatID] = &EtatXray{Proto: "vmess", Etape: "nom"}
				bot.Send(tgbotapi.NewMessage(chatID, "🟠 VMess — Entrez le nom d'utilisateur :"))

			case "xray_vless":
				etatsXray[chatID] = &EtatXray{Proto: "vless", Etape: "nom"}
				bot.Send(tgbotapi.NewMessage(chatID, "🔵 VLESS — Entrez le nom d'utilisateur :"))

			case "xray_trojan":
				etatsXray[chatID] = &EtatXray{Proto: "trojan", Etape: "nom"}
				bot.Send(tgbotapi.NewMessage(chatID, "🔴 Trojan — Entrez le nom d'utilisateur :"))

			case "xray_supprimer":
				txt := listeXrayPourSuppression()
				bot.Send(tgbotapi.NewMessage(chatID, txt))
				modeSupprimerXray[chatID] = true
			}

			continue
		}

		// ================= MESSAGE =================
		if update.Message == nil {
			continue
		}

		text := strings.TrimSpace(update.Message.Text)

		// ================= MENU =================
		if text == "/kighmu" {

			msgText := `============================================
🚀 𝗞𝗜𝗚𝗛𝗠𝗨 𝗠𝗔𝗡𝗔𝗚𝗘𝗥 🇨🇲
============================================
👤 AUTEUR : @𝐊𝐈𝐆𝐇𝐌𝐔
📢 CANAL TELEGRAM :
𝗵𝘁𝘁𝗽𝘀://𝘁.𝗺𝗲/𝗹𝗸𝗴𝗰𝗱𝗱𝘁𝗼𝗼𝗴𝘃
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
					tgbotapi.NewInlineKeyboardButtonData("🟠 VMess Xray", "xray_vmess"),
					tgbotapi.NewInlineKeyboardButtonData("🔵 VLESS Xray", "xray_vless"),
				),
				tgbotapi.NewInlineKeyboardRow(
					tgbotapi.NewInlineKeyboardButtonData("🔴 Trojan Xray", "xray_trojan"),
					tgbotapi.NewInlineKeyboardButtonData("🗑 Supprimer Xray", "xray_supprimer"),
				),
				tgbotapi.NewInlineKeyboardRow(
					tgbotapi.NewInlineKeyboardButtonData("📈 Conso Xray", "conso_xray"),
					tgbotapi.NewInlineKeyboardButtonData("📉 Conso V2Ray", "conso_v2ray"),
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

		// ================= HELP =================
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
			continue
		}

		// ================= CREATION XRAY (multi-etapes) =================
		if etat, ok := etatsXray[chatID]; ok {
			switch etat.Etape {
			case "nom":
				nom := strings.TrimSpace(text)
				if nom == "" {
					bot.Send(tgbotapi.NewMessage(chatID, "❌ Nom invalide"))
					delete(etatsXray, chatID)
					break
				}
				etat.Nom = nom
				etat.Etape = "quota"
				bot.Send(tgbotapi.NewMessage(chatID,
					fmt.Sprintf("📦 %s '%s'\nEntrez le quota en Go (ex: 10) :", strings.ToUpper(etat.Proto), nom)))
			case "quota":
				q, err := strconv.Atoi(strings.TrimSpace(text))
				if err != nil || q < 0 {
					bot.Send(tgbotapi.NewMessage(chatID, "❌ Quota invalide (entrez un nombre entier >= 0)"))
					delete(etatsXray, chatID)
					break
				}
				etat.Quota = q
				etat.Etape = "duree"
				bot.Send(tgbotapi.NewMessage(chatID, "📅 Entrez la durée en jours (ex: 30) :"))
			case "duree":
				d, err := strconv.Atoi(strings.TrimSpace(text))
				if err != nil || d <= 0 {
					bot.Send(tgbotapi.NewMessage(chatID, "❌ Durée invalide (entrez un nombre entier > 0)"))
					delete(etatsXray, chatID)
					break
				}
				// Tout est prêt — créer l'utilisateur
				resultat := creerUtilisateurXray(etat.Proto, etat.Nom, etat.Quota, d)
				bot.Send(tgbotapi.NewMessage(chatID, resultat))
				delete(etatsXray, chatID)
			}
			continue
		}

		// ================= SUPPRESSION XRAY (par numero) =================
		if modeSupprimerXray[chatID] {
			// Accepter "1" ou "1,3,5"
			parties := strings.FieldsFunc(text, func(r rune) bool { return r == ',' || r == ' ' })
			var indices []int
			valide := true
			for _, p := range parties {
				n, err := strconv.Atoi(strings.TrimSpace(p))
				if err != nil || n <= 0 {
					bot.Send(tgbotapi.NewMessage(chatID, fmt.Sprintf("❌ Numero invalide : %s", p)))
					valide = false
					break
				}
				indices = append(indices, n)
			}
			delete(modeSupprimerXray, chatID)
			if valide && len(indices) > 0 {
				bot.Send(tgbotapi.NewMessage(chatID, supprimerUtilisateursXray(indices)))
			}
			continue
		}

		// ================= MODIFICATION SSH =================
		if _, ok := etatsModifs[chatID]; ok {
			gererModificationSSH(bot, chatID, text)
			continue
		}

		// ================= SSH =================
		if strings.Count(text, ",") == 3 {
			p := strings.Split(text, ",")
			limite, err1 := strconv.Atoi(strings.TrimSpace(p[2]))
			duree, err2 := strconv.Atoi(strings.TrimSpace(p[3]))

			if err1 != nil || err2 != nil {
				bot.Send(tgbotapi.NewMessage(chatID, "❌ Paramètres invalides"))
				continue
			}

			if duree <= 1440 {
				bot.Send(tgbotapi.NewMessage(chatID,
					creerUtilisateurTest(p[0], p[1], limite, duree)))
			} else {
				bot.Send(tgbotapi.NewMessage(chatID,
					creerUtilisateurNormal(p[0], p[1], limite, duree)))
			}

			chargerUtilisateursSSH()
			continue
		}

		// ================= CREATION V2RAY (multi-etapes) =================
		if etatV2, ok := etatsV2Ray[chatID]; ok {
			switch etatV2.Etape {
			case "nom":
				nom := strings.TrimSpace(text)
				if nom == "" {
					bot.Send(tgbotapi.NewMessage(chatID, "❌ Nom invalide"))
					delete(etatsV2Ray, chatID)
					break
				}
				etatV2.Nom = nom
				etatV2.Etape = "quota"
				bot.Send(tgbotapi.NewMessage(chatID,
					fmt.Sprintf("📦 V2Ray '%s'\nEntrez le quota en Go (0 = illimité) :", nom)))
			case "quota":
				q, err := strconv.Atoi(strings.TrimSpace(text))
				if err != nil || q < 0 {
					bot.Send(tgbotapi.NewMessage(chatID, "❌ Quota invalide (entrez 0 ou un entier > 0)"))
					delete(etatsV2Ray, chatID)
					break
				}
				etatV2.Quota = q
				etatV2.Etape = "duree"
				bot.Send(tgbotapi.NewMessage(chatID, "📅 Entrez la durée en jours (ex: 30) :"))
			case "duree":
				d, err := strconv.Atoi(strings.TrimSpace(text))
				if err != nil || d <= 0 {
					bot.Send(tgbotapi.NewMessage(chatID, "❌ Durée invalide (entrez un nombre > 0)"))
					delete(etatsV2Ray, chatID)
					break
				}
				bot.Send(tgbotapi.NewMessage(chatID,
					creerUtilisateurV2Ray(etatV2.Nom, etatV2.Quota, d)))
				delete(etatsV2Ray, chatID)
			}
			continue
		}

		// ================= SUPPRESSION V2RAY =================
		if num, err := strconv.Atoi(text); err == nil &&
			num > 0 && num <= len(utilisateursV2Ray) {

			bot.Send(tgbotapi.NewMessage(chatID,
				supprimerUtilisateurV2Ray(num-1)))
			continue
		}

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
	chargerUtilisateursSSH()
	// Verifier que users.json Xray existe, sinon créer un fichier vide
	if _, err := os.Stat(xrayUsersFile); os.IsNotExist(err) {
		os.MkdirAll("/etc/xray", 0755)
		ioutil.WriteFile(xrayUsersFile, []byte(`{"vmess":[],"vless":[],"trojan":[]}`), 0644)
	}
	lancerBot()
}
