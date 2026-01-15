#!/bin/bash

API="http://127.0.0.1:10085/stats"
USERS="/etc/xray/users.json"

# Couleurs
CYAN="\e[36m"
MAGENTA="\e[35m"
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
WHITE="\e[97m"
BOLD="\e[1m"
RESET="\e[0m"

# ─────────────────────────────────────────
# Fonction : trafic par UUID (Go)
# ─────────────────────────────────────────
usage_gb() {
  local id="$1"
  local up down
  up=$(curl -s "$API" | jq "[.stat[]|select(.name==\"user>>>$id>>>traffic>>>uplink\").value][0]//0")
  down=$(curl -s "$API" | jq "[.stat[]|select(.name==\"user>>>$id>>>traffic>>>downlink\").value][0]//0")
  awk "BEGIN{printf \"%.2f\",($up+$down)/1073741824}"
}

clear

# ───────────── TITRE ─────────────
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}${MAGENTA}          TRAFFIC D'UTILISATEURS${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

TOTAL=0

# ───────────── TOTAL GLOBAL ─────────────
for proto in vmess vless trojan; do
  key="uuid"; [[ "$proto" == "trojan" ]] && key="password"

  jq -r ".${proto}[]?.${key}" "$USERS" | while read -r id; do
    g=$(usage_gb "$id")
    TOTAL=$(awk "BEGIN{print $TOTAL+$g}")
  done
done

printf "${WHITE}Consommation totale : ${GREEN}%.2f Go${RESET}\n" "$TOTAL"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
printf "${BOLD}%-8s %-32s %-20s${RESET}\n" "PROTO" "UTILISATEUR (expiration)" "CONSOMMATION"
echo "---------------------------------------------------------------"

# ───────────── LISTE UTILISATEURS ─────────────
for proto in vmess vless trojan; do
  key="uuid"; [[ "$proto" == "trojan" ]] && key="password"

  jq -c ".${proto}[]?" "$USERS" | while read -r u; do
    id=$(echo "$u" | jq -r ".${key}")
    name=$(echo "$u" | jq -r ".name")
    quota=$(echo "$u" | jq -r ".quota_gb")
    exp=$(echo "$u" | jq -r ".expiry")

    # Date FR
    exp_fr=$(date -d "$exp" +"%d/%m/%Y" 2>/dev/null)

    used=$(usage_gb "$id")

    # Couleur selon quota
    color="$GREEN"
    (( $(echo "$used >= $quota" | bc -l) )) && color="$RED"

    printf "%-8s ${WHITE}%-15s${RESET} ${YELLOW}( %s )${RESET}   ${color}%5.2f Go / %s Go${RESET}\n" \
      "$proto" "$name" "$exp_fr" "$used" "$quota"
  done
done

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

read -p "Appuyez sur Entrée pour continuer..."
