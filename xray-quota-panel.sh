#!/bin/bash

API_URL="http://127.0.0.1:10085/stats"
USERS_FILE="/etc/xray/users.json"

CYAN="\e[36m"
GREEN="\e[32m"
YELLOW="\e[33m"
MAGENTA="\e[35m"
WHITE="\e[97m"
BOLD="\e[1m"
RESET="\e[0m"

# ─────────────────────────────────────────────
# Fonction : trafic par UUID (en Go)
# ─────────────────────────────────────────────
get_usage_gb() {
  local uuid="$1"

  local up down
  up=$(curl -s "$API_URL" | jq "[.stat[] | select(.name==\"user>>>$uuid>>>traffic>>>uplink\").value][0] // 0")
  down=$(curl -s "$API_URL" | jq "[.stat[] | select(.name==\"user>>>$uuid>>>traffic>>>downlink\").value][0] // 0")

  awk "BEGIN {printf \"%.2f\", ($up+$down)/1073741824}"
}

clear

# ─────────────────────────────────────────────
# TITRE
# ─────────────────────────────────────────────
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}${MAGENTA}          TRAFFIC D'UTILISATEURS${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

TOTAL_ALL=0

# ─────────────────────────────────────────────
# CALCUL TOTAL GLOBAL
# ─────────────────────────────────────────────
for proto in vmess vless trojan; do
  key="uuid"
  [[ "$proto" == "trojan" ]] && key="password"

  jq -r ".${proto}[]? | .${key}" "$USERS_FILE" | while read -r uuid; do
    usage=$(get_usage_gb "$uuid")
    TOTAL_ALL=$(awk "BEGIN {print $TOTAL_ALL + $usage}")
  done
done

printf "${WHITE}Consommation totale : ${GREEN}%.2f Go${RESET}\n" "$TOTAL_ALL"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ─────────────────────────────────────────────
# LISTE PAR UTILISATEUR
# ─────────────────────────────────────────────
printf "${BOLD}%-10s %-15s %-12s${RESET}\n" "PROTO" "UTILISATEUR" "CONSOMMATION"
echo "-----------------------------------------------"

for proto in vmess vless trojan; do
  key="uuid"
  [[ "$proto" == "trojan" ]] && key="password"

  jq -c ".${proto}[]?" "$USERS_FILE" | while read -r user; do
    uuid=$(echo "$user" | jq -r ".${key}")
    name=$(echo "$user" | jq -r ".name // \"inconnu\"")

    usage=$(get_usage_gb "$uuid")

    printf "%-10s %-15s ${YELLOW}%6.2f Go${RESET}\n" \
      "$proto" "$name" "$usage"
  done
done

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
