package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"strings"
)

const (
	apiURL     = "http://127.0.0.1:10085/stats"
	usersFile  = "/etc/xray/users.json"
	configFile = "/etc/xray/config.json"
)

type Users struct {
	Vmess  []User `json:"vmess"`
	Vless  []User `json:"vless"`
	Trojan []User `json:"trojan"`
}

type User struct {
	UUID  string `json:"uuid,omitempty"`
	Pass  string `json:"password,omitempty"`
	Limit int64  `json:"limit"` // Go
}

type Stat struct {
	Name  string `json:"name"`
	Value int64  `json:"value"`
}

type StatsResponse struct {
	Stat []Stat `json:"stat"`
}

func bytesToGB(b int64) float64 {
	return float64(b) / 1073741824
}

func main() {
	resp, err := http.Get(apiURL)
	if err != nil {
		fmt.Println("❌ Impossible de contacter Xray API")
		return
	}
	defer resp.Body.Close()

	body, _ := ioutil.ReadAll(resp.Body)

	var stats StatsResponse
	json.Unmarshal(body, &stats)

	data, _ := ioutil.ReadFile(usersFile)
	var users Users
	json.Unmarshal(data, &users)

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

	checkUsers := func(uuid string, limit int64) {
		if used, ok := usage[uuid]; ok {
			gb := bytesToGB(used)
			if gb >= float64(limit) {
				fmt.Printf("🚫 Quota dépassé : %s (%.2f / %d Go)\n", uuid, gb, limit)
				disableUser(uuid)
			}
		}
	}

	for _, u := range users.Vmess {
		checkUsers(u.UUID, u.Limit)
	}
	for _, u := range users.Vless {
		checkUsers(u.UUID, u.Limit)
	}
	for _, u := range users.Trojan {
		checkUsers(u.Pass, u.Limit)
	}
}

func disableUser(uuid string) {
	cmd := exec.Command("bash", "-c",
		fmt.Sprintf(`
jq --arg u "%s" '
(.inbounds[].settings.clients) |= map(
  select(.id != $u and .password != $u)
)' %s > /tmp/config.tmp &&
mv /tmp/config.tmp %s &&
systemctl restart xray
`, uuid, configFile, configFile),
	)
	cmd.Run()
}
