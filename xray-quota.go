package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"os/exec"
	"strings"
)

const (
	apiURL     = "http://127.0.0.1:10085/stats"
	usersFile  = "/etc/xray/users.json"
	configFile = "/etc/xray/config.json"
)

// Structures JSON
type Users struct {
	Vmess  []User `json:"vmess"`
	Vless  []User `json:"vless"`
	Trojan []User `json:"trojan"`
}

type User struct {
	UUID  string `json:"uuid,omitempty"`
	Pass  string `json:"password,omitempty"`
	Name  string `json:"name"`
	Limit int64  `json:"limit"` // Go
	Expire string `json:"expire"`
}

type Stat struct {
	Name  string `json:"name"`
	Value int64  `json:"value"`
}

type StatsResponse struct {
	Stat []Stat `json:"stat"`
}

// Conversion bytes -> Go
func bytesToGB(b int64) float64 {
	return float64(b) / 1073741824
}

// Désactive l'utilisateur dans config.json et redémarre Xray
func disableUser(uuid string) {
	cmd := exec.Command("bash", "-c",
		fmt.Sprintf(`
jq --arg u "%s" '
(.inbounds[].settings.clients) |= map(select(.id != $u and .password != $u))
' %s > /tmp/config.tmp &&
mv /tmp/config.tmp %s &&
systemctl restart xray
`, uuid, configFile, configFile))
	cmd.Run()
}

func main() {
	// ─── Lecture des stats
	resp, err := http.Get(apiURL)
	if err != nil {
		fmt.Println("❌ Impossible de contacter Xray API")
		return
	}
	defer resp.Body.Close()
	body, _ := ioutil.ReadAll(resp.Body)

	var stats StatsResponse
	json.Unmarshal(body, &stats)

	// ─── Lecture des utilisateurs
	data, _ := ioutil.ReadFile(usersFile)
	var users Users
	json.Unmarshal(data, &users)

	// ─── Calcul de la consommation
	usage := make(map[string]int64)
	for _, s := range stats.Stat {
		if strings.Contains(s.Name, "user>>>") {
			parts := strings.Split(s.Name, ">>>")
			if len(parts) >= 2 {
				uuid := parts[1]
				usage[uuid] += s.Value
			}
		}
	}

	// ─── Affichage du panneau
	fmt.Println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	fmt.Println("          TRAFFIC D'UTILISATEURS")
	fmt.Println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

	totalUsed := 0.0

	printUser := func(proto, id, name, expire string, limit int64) {
		used := bytesToGB(usage[id])
		totalUsed += used

		colorStart := "\033[32m" // vert
		colorEnd := "\033[0m"
		if used >= float64(limit) {
			colorStart = "\033[31m" // rouge
			disableUser(id)
		}

		expFr := expire
		if len(expire) > 0 {
			expFr = expire // tu peux convertir en dd/mm/yyyy si nécessaire
		}

		fmt.Printf("%-8s %-15s ( %s )   %s%5.2f Go / %d Go%s\n",
			proto, name, expFr, colorStart, used, limit, colorEnd)
	}

	// Vmess
	for _, u := range users.Vmess {
		printUser("vmess", u.UUID, u.Name, u.Expire, u.Limit)
	}
	// Vless
	for _, u := range users.Vless {
		printUser("vless", u.UUID, u.Name, u.Expire, u.Limit)
	}
	// Trojan
	for _, u := range users.Trojan {
		printUser("trojan", u.Pass, u.Name, u.Expire, u.Limit)
	}

	fmt.Println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	fmt.Printf("Consommation totale : %.2f Go\n", totalUsed)
	fmt.Println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
}
