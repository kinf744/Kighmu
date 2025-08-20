#!/bin/bash
# ==============================================
# Kighmu VPS Manager
# Copyright (c) 2025 Kinf744
# Licence MIT (version française)
# ==============================================

export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=en_US.UTF-8
export LANG="$LC_ALL"

INNER=50
INNER_TEXT=$((INNER-2))

disp_len() { awk -v s="$1" 'BEGIN{print length(s)}'; }
truncate_utf8() {
  local s="$1" n="$2"
  awk -v s="$s" -v n="$n" 'BEGIN{
    if (length(s) > n) print substr(s,1,n-1) "…";
    else print s
  }'
}
sanitize() {
  local s="${1//$'\t'/    }"
  printf "%s" "$s" | sed -E 's/\x1B\[[0-9;]*[mK]//g'
}
line_full()   { echo "+$(printf '%0.s=' $(seq 1 $INNER))+"; }
line_simple() { echo "+$(printf '%0.s-' $(seq 1 $INNER))+"; }
content_line() {
  local content="$(sanitize "$1")"
  content="$(truncate_utf8 "$content" "$INNER_TEXT")"
  printf "| %-*s |\n" "$INNER_TEXT" "$content"
}
center_line() {
  local text="$(sanitize "$1")"
  local len; len=$(disp_len "$text")
  (( len > INNER_TEXT )) && text="$(truncate_utf8 "$text" "$INNER_TEXT")" && len=$INNER_TEXT
  local left=$(( (INNER_TEXT - len) / 2 ))
  local right=$(( INNER_TEXT - len - left ))
  printf "| %*s%s%*s |\n" "$left" "" "$text" "$right" ""
}
double_content() {
  local left="$(sanitize "$1")"
  local right="$(sanitize "$2")"
  local ll rr space

  ll=$(disp_len "$left")
  rr=$(disp_len "$right")
  space=$(( INNER_TEXT - ll - rr ))
  if (( space < 0 )); then
    right="$(truncate_utf8 "$right" $(( rr + space )))"
    rr=$(disp_len "$right")
    space=$(( INNER_TEXT - ll - rr ))
  fi
  if (( space < 0 )); then
    left="$(truncate_utf8 "$left"  $(( ll + space )))"
    ll=$(disp_len "$left")
    space=$(( INNER_TEXT - ll - rr ))
  fi
  printf "| %s%*s%s |\n" "$left" "$space" "" "$right"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INTERFACE="eth0"

if ! command -v iptables &> /dev/null; then
  apt update
  apt install -y iptables
fi

if ! iptables -L INPUT -v -n | grep --quiet "dpt:22"; then
  iptables -I INPUT -p tcp --dport 22 -j ACCEPT
fi
if ! iptables -L OUTPUT -v -n | grep --quiet "spt:22"; then
  iptables -I OUTPUT -p tcp --sport 22 -j ACCEPT
fi

get_cpu_usage() {
  top -bn2 | grep "Cpu(s)" | tail -n1 | awk -F'id,' '{ usage=100-$1; print usage }' | awk '{printf "%.2f%%", $1}'
}
get_ram_usage() {
  free | awk '/Mem:/ { printf("%.2f%%", $3/$2 * 100) }'
}
get_connected_devices() {
  ss -tn state established '( sport = :8080 )' 2>/dev/null | tail -n +2 | wc -l
}
get_users_count() {
  awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd | wc -l
}
get_ssh_traffic_bytes() {
  local input_bytes=$(iptables -L INPUT -v -n | grep -- 'dpt:22' | awk '{print $2}' | paste -sd+ - | bc)
  local output_bytes=$(iptables -L OUTPUT -v -n | grep -- 'spt:22' | awk '{print $2}' | paste -sd+ - | bc)
  echo $((input_bytes + output_bytes))
}
get_traffic_stats() {
  local xray_traffic=$(vnstat --oneline $INTERFACE 2>/dev/null | awk -F';' '{print $3}')
  local ssh_bytes=$(get_ssh_traffic_bytes)
  local ssh_traffic=$(echo "scale=2; $ssh_bytes / 1073741824" | bc)
  local total_today=$(echo "$xray_traffic + $ssh_traffic" | bc)
  local total_month="$total_today"
  echo "${total_today}|${total_month}"
}

while true; do
  clear

  line_full
  center_line "K I G H M U   M A N A G E R"
  line_full

  IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -z "$IP" ]] && IP=$(ip -4 addr show 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)

  RAM_USAGE=$(get_ram_usage)
  CPU_USAGE=$(get_cpu_usage)
  USER_COUNT=$(get_users_count)
  CONNECTED_DEVICES=$(get_connected_devices)
  traffic_stats=$(get_traffic_stats)
  today_usage=$(echo "$traffic_stats" | cut -d'|' -f1)
  month_usage=$(echo "$traffic_stats" | cut -d'|' -f2)

  double_content "IP: $IP" "RAM utilisée: $RAM_USAGE"
  double_content "CPU utilisé: $CPU_USAGE" ""
  line_simple

  double_content "Utilisateurs: $USER_COUNT" "Appareils connectés: $CONNECTED_DEVICES"
  line_simple

  double_content "Trafic aujourd'hui: ${today_usage} GB" "Trafic mois: ${month_usage} GB"
  line_simple

  center_line "MENU PRINCIPAL:"
  line_simple

  content_line "1. Créer un utilisateur"
  content_line "2. Créer un test utilisateur"
  content_line "3. Voir les utilisateurs en ligne"
  content_line "4. Supprimer utilisateur"
  content_line "5. Installation de mode"
  content_line "6. Xray mode"
  content_line "7. Désinstaller le script"
  content_line "8. Blocage de torrents"
  content_line "9. Quitter"
  line_simple

  content_line "Appuyez sur Ctrl+C pour quitter. Tapez choix puis Entrée:"
  line_full

  read -t 1 -p "| Votre choix (1-9): " choix
  if [[ -n "$choix" ]]; then
    case $choix in
      1) bash "$SCRIPT_DIR/menu1.sh" ;;
      2) bash "$SCRIPT_DIR/menu2.sh" ;;
      3) bash "$SCRIPT_DIR/menu3.sh" ;;
      4) bash "$SCRIPT_DIR/menu4.sh" ;;
      5) bash "$SCRIPT_DIR/menu5.sh" ;;
      6) bash "$SCRIPT_DIR/menu_6.sh" ;;
      7) bash "$SCRIPT_DIR/menu6.sh" ;;
      8) bash "$SCRIPT_DIR/menu7.sh" ;;
      9) echo "Au revoir !"; exit 0 ;;
      *) echo "Choix invalide !" ;;
    esac
    read -p "Appuyez sur Entrée pour revenir au menu..."
  fi
done
