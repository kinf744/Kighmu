#!/bin/bash
# ==============================================
# Kighmu VPS Manager
# Copyright (c) 2025 Kinf744
# Licence MIT (version française)
# Voir le fichier LICENSE pour plus de détails
# ==============================================

# --- Locale UTF-8 pour gérer correctement les accents ---
export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=en_US.UTF-8
export LANG="$LC_ALL"

# Largeur interne du cadre (entre les deux '+')
INNER=50                      # <-- ajuste ici si tu veux un cadre plus large
INNER_TEXT=$((INNER-2))       # largeur utile du texte (à l'intérieur des espaces)

# ---------- Utilitaires d'affichage sûrs UTF-8 ----------
# Longueur d'affichage (UTF-8)
disp_len() {
  awk -v s="$1" 'BEGIN{print length(s)}'
}

# Tronquer une chaîne à n caractères (UTF-8 safe)
truncate_utf8() {
  local s="$1" n="$2"
  awk -v s="$s" -v n="$n" 'BEGIN{
    if (length(s) > n) print substr(s,1,n-1) "…";
    else print s
  }'
}

# Nettoyer TABs et codes ANSI (au cas où)
sanitize() {
  local s="${1//$'\t'/    }"
  # strip ANSI
  printf "%s" "$s" | sed -E 's/\x1B\[[0-9;]*[mK]//g'
}

# ---------- Dessin du cadre ----------
line_full()   { echo "+$(printf '%0.s=' $(seq 1 $INNER))+"; }
line_simple() { echo "+$(printf '%0.s-' $(seq 1 $INNER))+"; }

# Ligne de contenu alignée à gauche, bord droit garanti droit
content_line() {
  local content="$(sanitize "$1")"
  # Tronquer si trop long, puis pad exactement à INNER_TEXT
  content="$(truncate_utf8 "$content" "$INNER_TEXT")"
  printf "| %-*s |\n" "$INNER_TEXT" "$content"
}

# Ligne centrée (UTF-8 safe)
center_line() {
  local text="$(sanitize "$1")"
  local len; len=$(disp_len "$text")
  (( len > INNER_TEXT )) && text="$(truncate_utf8 "$text" "$INNER_TEXT")" && len=$INNER_TEXT
  local left=$(( (INNER_TEXT - len) / 2 ))
  local right=$(( INNER_TEXT - len - left ))
  printf "| %*s%s%*s |\n" "$left" "" "$text" "$right" ""
}

# Deux colonnes (gauche/droite) avec ajustement si ça dépasse
double_content() {
  local left="$(sanitize "$1")"
  local right="$(sanitize "$2")"
  local ll rr space

  ll=$(disp_len "$left")
  rr=$(disp_len "$right")
  space=$(( INNER_TEXT - ll - rr ))
  # Si ça dépasse, on tronque d'abord la partie droite, puis la gauche
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

# ---------- Répertoire du script ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while true; do
  clear

  line_full
  center_line "K I G H M U   M A N A G E R"
  line_full

  # Récupération IP, RAM et CPU
  IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -z "$IP" ]] && IP=$(ip -4 addr show 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)

  RAM_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }')
  CPU_USAGE=$(top -bn1 | awk -F'[, ]+' '/Cpu\(s\)/{printf "%.2f%%", $2+$4}')

  # Compter utilisateurs normaux (UID >= 1000 et < 65534)
  USER_COUNT=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd | wc -l)

  # Connexions TCP établies au port 8080 (proxy SOCKS)
  CONNECTED_DEVICES=$(ss -tn state established '( sport = :8080 )' 2>/dev/null | tail -n +2 | wc -l)

  double_content "IP: $IP" "RAM utilisée: $RAM_USAGE"
  double_content "CPU utilisé: $CPU_USAGE" ""
  line_simple

  double_content "Utilisateurs créés: $USER_COUNT" "Appareils connectés: $CONNECTED_DEVICES"
  line_simple

  center_line "MENU PRINCIPAL:"
  line_simple

  # --- Bloc MENU (le côté droit restera parfaitement droit) ---
  content_line "1. Créer un utilisateur"
  content_line "2. Créer un test utilisateur"
  content_line "3. Voir les utilisateurs en ligne"
  content_line "4. Supprimer utilisateur"
  content_line "5. Installation de mode"
  content_line "6. Désinstaller le script"
  content_line "7. Blocage de torrents"
  content_line "8. Quitter"
  line_simple

  content_line "Entrez votre choix [1-8]:"
  line_full   # fermeture du cadre (haut = '=', bas = '=')

  # Prompt hors cadre (clair et lisible)
  read -p "| Votre choix: " choix

  case $choix in
    1) bash "$SCRIPT_DIR/menu1.sh" ;;
    2) bash "$SCRIPT_DIR/menu2.sh" ;;
    3) bash "$SCRIPT_DIR/menu3.sh" ;;
    4) bash "$SCRIPT_DIR/menu4.sh" ;;
    5) bash "$SCRIPT_DIR/menu5.sh" ;;
    6) bash "$SCRIPT_DIR/menu6.sh" ;;
    7) bash "$SCRIPT_DIR/menu7.sh" ;;
    8) echo "Au revoir !"; exit 0 ;;
    *) echo "Choix invalide !" ;;
  esac

  read -p "Appuyez sur Entrée pour revenir au menu..."
done
