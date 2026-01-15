package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"strings"
)

// Struct pour users.json
type User struct {
	UUID  string `json:"uuid"`
	Limit int64  `json:"limit"`
}

type TrojanUser struct {
	Password string `json:"password"`
	Limit    int64  `json:"limit"`
}

type Users struct {
	Vmess  []User       `json:"vmess"`
	Vless  []User       `json:"vless"`
	Trojan []TrojanUser `json:"trojan"`
}

// Struct pour StatsService
type Stat struct {
	Tag   string `json:"tag"`
	Uplink   int64 `json:"uplink"`
	Downlink int64 `json:"downlink"`
}

func main() {
	usersFile := "/etc/xray/users.json"
	apiURL := "http://127.0.0.1:10085/stats"

	// Lire les utilisateurs
	data, err := ioutil.ReadFile(usersFile)
	if err != nil {
		fmt.Println("Erreur lecture users.json:", err)
		return
	}

	var users Users
	err = json.Unmarshal(data, &users)
	if err != nil {
		fmt.Println("Erreur parsing users.json:", err)
		return
	}

	// Récupérer stats Xray
	resp, err := http.Get(apiURL)
	if err != nil {
		fmt.Println("Erreur StatsService:", err)
		return
	}
	defer resp.Body.Close()
	body, _ := ioutil.ReadAll(resp.Body)

	var stats []Stat
	err = json.Unmarshal(body, &stats)
	if err != nil {
		fmt.Println("Erreur parsing stats JSON:", err)
		return
	}

	// Fonction pour calculer total traffic d'un UUID
	getTraffic := func(tag string) int64 {
		for _, s := range stats {
			if s.Tag == tag {
				return s.Uplink + s.Downlink
			}
		}
		return 0
	}

	// Appliquer pour VMess et VLESS
	for _, proto := range []struct {
		name  string
		users interface{}
	}{
		{"vmess", users.Vmess},
		{"vless", users.Vless},
	} {
		switch ulist := proto.users.(type) {
		case []User:
			for _, u := range ulist {
				trafficBytes := getTraffic(u.UUID)
				trafficGB := float64(trafficBytes) / 1073741824
				fmt.Printf("[%s] UUID: %s | Traffic: %.2f Go / Limite: %d Go\n", strings.ToUpper(proto.name), u.UUID, trafficGB, u.Limit)

				// Si dépassement de limite, supprimer utilisateur
				if trafficGB >= float64(u.Limit) {
					fmt.Printf("⚠️ Limite dépassée pour %s UUID: %s, suppression...\n", proto.name, u.UUID)
					removeUser(proto.name, u.UUID, usersFile)
				}
			}
		}
	}

	// Appliquer pour Trojan
	for _, u := range users.Trojan {
		trafficBytes := getTraffic(u.Password)
		trafficGB := float64(trafficBytes) / 1073741824
		fmt.Printf("[TROJAN] Password: %s | Traffic: %.2f Go / Limite: %d Go\n", u.Password, trafficGB, u.Limit)
		if trafficGB >= float64(u.Limit) {
			fmt.Printf("⚠️ Limite dépassée pour TROJAN: %s, suppression...\n", u.Password)
			removeUser("trojan", u.Password, usersFile)
		}
	}
}

// Supprimer un utilisateur de users.json et config.json
func removeUser(proto, id, usersFile string) {
	configFile := "/etc/xray/config.json"

	// Sauvegarde
	os.Rename(usersFile, usersFile+".bak")
	os.Rename(configFile, configFile+".bak")

	usersData, _ := ioutil.ReadFile(usersFile + ".bak")
	configData, _ := ioutil.ReadFile(configFile + ".bak")

	var users map[string]interface{}
	json.Unmarshal(usersData, &users)

	switch proto {
	case "vmess", "vless":
		if list, ok := users[proto].([]interface{}); ok {
			newList := []interface{}{}
			for _, u := range list {
				m := u.(map[string]interface{})
				if m["uuid"] != id {
					newList = append(newList, u)
				}
			}
			users[proto] = newList
		}
	case "trojan":
		if list, ok := users["trojan"].([]interface{}); ok {
			newList := []interface{}{}
			for _, u := range list {
				m := u.(map[string]interface{})
				if m["password"] != id {
					newList = append(newList, u)
				}
			}
			users["trojan"] = newList
		}
	}

	newUsersData, _ := json.MarshalIndent(users, "", "  ")
	ioutil.WriteFile(usersFile, newUsersData, 0644)

	// Supprimer du config.json
	var config map[string]interface{}
	json.Unmarshal(configData, &config)

	if inbounds, ok := config["inbounds"].([]interface{}); ok {
		for i, inbound := range inbounds {
			if ib, ok := inbound.(map[string]interface{}); ok {
				if clients, ok := ib["settings"].(map[string]interface{})["clients"].([]interface{}); ok {
					newClients := []interface{}{}
					for _, c := range clients {
						m := c.(map[string]interface{})
						if proto == "trojan" {
							if m["password"] != id {
								newClients = append(newClients, c)
							}
						} else {
							if m["id"] != id {
								newClients = append(newClients, c)
							}
						}
					}
					ib["settings"].(map[string]interface{})["clients"] = newClients
					inbounds[i] = ib
				}
			}
		}
	}
	config["inbounds"] = inbounds
	newConfigData, _ := json.MarshalIndent(config, "", "  ")
	ioutil.WriteFile(configFile, newConfigData, 0644)

	// Redémarrer Xray
	fmt.Println("🔄 Redémarrage Xray pour appliquer les changements...")
	os.Exec("/bin/systemctl", []string{"restart", "xray"})
}
