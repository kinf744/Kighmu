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
# Fonction : consommation d’un UUID en Go
# ─────────────────────────────────────────
usage_gb() {
    local id="$1"
    local up down
    up=$(curl -s "$API" | jq "[.stat[] | select(.name==\"user>>>$id>>>traffic>>>uplink\").value] | add // 0")
    down=$(curl -s "$API" | jq "[.stat[] | select(.name==\"user>>>$id>>>traffic>>>downlink\").value] | add // 0")
    awk "BEGIN{printf \"%.2f\",($up+$down)/1073741824}"
}

# ───────────── AFFICHAGE TITRE ─────────────
clear
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}${MAGENTA}          TRAFFIC D'UTILISATEURS${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ───────────── CALCUL CONSOMMATION TOTALE ─────────────
TOTAL=0

for proto in vmess vless trojan; do
    key="uuid"
    [[ "$proto" == "trojan" ]] && key="password"

    ids=($(jq -r ".${proto}[]?.${key}" "$USERS"))
    for id in "${ids[@]}"; do
        g=$(usage_gb "$id")
        TOTAL=$(awk "BEGIN{print $TOTAL+$g}")
    done
done

echo -e "${WHITE}Consommation totale : ${GREEN}$(printf "%.2f" "$TOTAL") Go${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ───────────── ENTÊTE UTILISATEURS ─────────────
printf "${BOLD}%-8s %-20s %-25s %-15s${RESET}\n" "PROTO" "UTILISATEUR" "EXPIRATION" "CONSOMMATION"
echo "---------------------------------------------------------------"

# ───────────── LISTE UTILISATEURS ─────────────
for proto in vmess vless trojan; do
    key="uuid"
    [[ "$proto" == "trojan" ]] && key="password"

    users_count=$(jq ".${proto} | length" "$USERS")
    for ((i=0;i<users_count;i++)); do
        u=$(jq -c ".${proto}[$i]" "$USERS")
        id=$(echo "$u" | jq -r ".${key}")
        name=$(echo "$u" | jq -r ".name")
        quota=$(echo "$u" | jq -r ".limit_gb")
        exp=$(echo "$u" | jq -r ".expire")
        exp_fr=$(date -d "$exp" +"%d/%m/%Y" 2>/dev/null)

        used=$(usage_gb "$id")

        # Couleur selon quota
        color="$GREEN"
        (( $(echo "$used >= $quota" | bc -l) )) && color="$RED"

        printf "%-8s ${WHITE}%-20s${RESET} ${YELLOW}%-25s${RESET} ${color}%5.2f Go / %s Go${RESET}\n" \
            "$proto" "$name" "$exp_fr" "$used" "$quota"
    done
done

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

read -p "Appuyez sur Entrée pour continuer..."
