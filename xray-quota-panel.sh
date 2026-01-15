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
# Fonction : trafic par UUID ou password (Go)
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

# ───────────── CALCUL CONSOMMATION TOTALE ─────────────
for proto in vmess vless trojan; do
    key="uuid"; [[ "$proto" == "trojan" ]] && key="password"
    mapfile -t ids < <(jq -r ".${proto}[]?.${key}" "$USERS")
    for id in "${ids[@]}"; do
        g=$(usage_gb "$id")
        TOTAL=$(awk "BEGIN{print $TOTAL+$g}")
    done
done

echo -e "${WHITE}Consommation totale : ${GREEN}$(printf "%.2f" "$TOTAL") Go${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ───────────── ENTÊTE LISTE UTILISATEURS ─────────────
printf "${BOLD}%-8s %-25s %-25s %-20s${RESET}\n" "PROTO" "UTILISATEUR" "EXPIRATION" "CONSOMMATION"
echo "--------------------------------------------------------------------------"

# ───────────── LISTE UTILISATEURS ─────────────
for proto in vmess vless trojan; do
    key="uuid"; [[ "$proto" == "trojan" ]] && key="password"
    mapfile -t users_json < <(jq -c ".${proto}[]?" "$USERS")
    for u in "${users_json[@]}"; do
        id=$(echo "$u" | jq -r ".${key}")
        name=$(echo "$u" | jq -r ".name")
        quota=$(echo "$u" | jq -r ".limit_gb")
        exp=$(echo "$u" | jq -r ".expire")

        exp_fr=$(date -d "$exp" +"%d/%m/%Y" 2>/dev/null)
        used=$(usage_gb "$id")

        # Couleur selon quota
        color="$GREEN"
        (( $(echo "$used >= $quota" | bc -l) )) && color="$RED"

        printf "%-8s ${WHITE}%-25s${RESET} ${YELLOW}%-25s${RESET} ${color}%6.2f Go / %-6s${RESET}\n" \
            "$proto" "$name" "$exp_fr" "$used" "$quota"
    done
done

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

read -p "Appuyez sur Entrée pour continuer..."
