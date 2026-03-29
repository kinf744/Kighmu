#!/bin/bash
# menu4.sh - Supprimer un utilisateur ou tous les utilisateurs expirés

USER_FILE="/etc/kighmu/users.list"

setup_colors() {
  RED=""; GREEN=""; YELLOW=""; CYAN=""; MAGENTA_VIF=""; BOLD=""; RESET=""
  if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"
    CYAN="$(tput setaf 6)"; MAGENTA_VIF="$(tput setaf 5; tput bold)"
    BOLD="$(tput bold)"; RESET="$(tput sgr0)"
  fi
}
setup_colors
clear

echo -e "${CYAN}+--------------------------------------------+${RESET}"
echo -e "${MAGENTA_VIF}|          GESTION DES UTILISATEURS          |${RESET}"
echo -e "${CYAN}+--------------------------------------------+${RESET}"
echo
echo -e "${GREEN}[01]${RESET} Supprimer un utilisateur"
echo -e "${YELLOW}[02]${RESET} Supprimer tous les utilisateurs expirés"
echo -e "${RED}[00]${RESET} Quitter"
echo
read -rp "${CYAN}Sélectionnez une option (1/2/0) : ${RESET}" option

# ==========================================================
# Fonction : supprimer un utilisateur (même si connecté)
# ==========================================================
supprimer_utilisateur() {
  local username="$1"
  local TODAY
  TODAY=$(date +%Y-%m-%d)

  # Vérifier existence dans users.list
  if ! grep -q "^${username}|" "$USER_FILE" 2>/dev/null; then
    # Vérifier au moins dans /etc/passwd
    if ! id "$username" &>/dev/null; then
      echo -e "${RED}Utilisateur '$username' introuvable.${RESET}"
      return 1
    fi
  fi

  # ── 1. Tuer toutes les sessions actives (même si connecté) ──
  if id "$username" &>/dev/null; then
    pkill -u "$username" 2>/dev/null || true
    sleep 1
    # Force kill si toujours actif
    pkill -9 -u "$username" 2>/dev/null || true
    sleep 1
  fi

  # ── 2. Suppression système ──────────────────────────────────
  if id "$username" &>/dev/null; then
    if userdel -r "$username" 2>/dev/null; then
      echo -e "${GREEN}✅ Utilisateur système '$username' supprimé.${RESET}"
    else
      # Forcer même si le répertoire home pose problème
      userdel "$username" 2>/dev/null || true
      rm -rf "/home/${username}" 2>/dev/null || true
      echo -e "${YELLOW}⚠️  '$username' supprimé (home nettoyé manuellement).${RESET}"
    fi
  fi

  # ── 3. Suppression kighmu users.list ────────────────────────
  if [[ -f "$USER_FILE" ]]; then
    grep -v "^${username}|" "$USER_FILE" > "${USER_FILE}.tmp" &&
    mv "${USER_FILE}.tmp" "$USER_FILE"
    echo -e "${GREEN}✅ Kighmu: '$username' retiré de users.list.${RESET}"
  fi

  # ── 4. Nettoyage règles iptables SSH ────────────────────────
  # (les règles iptables par UID sont devenues orphelines)
  # On ne peut plus récupérer l'UID après suppression — déjà nettoyé par userdel

  # ── 5. ZIVPN sync ───────────────────────────────────────────
  local ZIVPN_USER_FILE="/etc/zivpn/users.list"
  local ZIVPN_CONFIG="/etc/zivpn/config.json"
  if [[ -f "$ZIVPN_USER_FILE" ]]; then
    grep -v "^${username}|" "$ZIVPN_USER_FILE" > "${ZIVPN_USER_FILE}.tmp" &&
    mv "${ZIVPN_USER_FILE}.tmp" "$ZIVPN_USER_FILE"
    chmod 600 "$ZIVPN_USER_FILE"

    if [[ -f "$ZIVPN_CONFIG" ]]; then
      local ZPASS tmp
      ZPASS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" | sort -u)
      tmp=$(mktemp)
      if jq --argjson arr "$(printf '%s\n' "$ZPASS" | jq -R . | jq -s .)" \
            '.auth.config = $arr' "$ZIVPN_CONFIG" > "$tmp" &&
         jq empty "$tmp" >/dev/null 2>&1; then
        mv "$tmp" "$ZIVPN_CONFIG"
        systemctl restart zivpn.service 2>/dev/null || true
        echo -e "${GREEN}✅ ZIVPN synchronisé.${RESET}"
      else
        rm -f "$tmp"
        echo -e "${YELLOW}⚠️  ZIVPN non modifié (JSON invalide).${RESET}"
      fi
    fi
  fi

  # ── 6. Hysteria sync ────────────────────────────────────────
  local HYSTERIA_USER_FILE="/etc/hysteria/users.txt"
  local HYSTERIA_CONFIG="/etc/hysteria/config.json"
  if [[ -f "$HYSTERIA_USER_FILE" ]]; then
    grep -v "^${username}|" "$HYSTERIA_USER_FILE" > "${HYSTERIA_USER_FILE}.tmp" &&
    mv "${HYSTERIA_USER_FILE}.tmp" "$HYSTERIA_USER_FILE"
    chmod 600 "$HYSTERIA_USER_FILE"

    if [[ -f "$HYSTERIA_CONFIG" ]]; then
      local HPASS tmp
      HPASS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$HYSTERIA_USER_FILE" | sort -u)
      tmp=$(mktemp)
      if jq --argjson arr "$(printf '%s\n' "$HPASS" | jq -R . | jq -s .)" \
            '.auth.config = $arr' "$HYSTERIA_CONFIG" > "$tmp" &&
         jq empty "$tmp" >/dev/null 2>&1; then
        mv "$tmp" "$HYSTERIA_CONFIG"
        systemctl restart hysteria.service 2>/dev/null || true
        echo -e "${GREEN}✅ Hysteria synchronisé.${RESET}"
      else
        rm -f "$tmp"
        echo -e "${YELLOW}⚠️  Hysteria non modifié (JSON invalide).${RESET}"
      fi
    fi
  fi

  # ── 7. Fichiers bandwidth/compteurs ─────────────────────────
  local BW_DIR="/var/lib/kighmu/bandwidth"
  rm -f "${BW_DIR}/${username}.usage" \
        "${BW_DIR}/sent/${username}.sent" \
        "${BW_DIR}/udp_zivpn_${username}.usage" \
        "${BW_DIR}/udp_hysteria_${username}.usage" \
        "/var/lib/kighmu/ssh-counters/${username}.out" \
        "/var/lib/kighmu/ssh-counters/${username}.in" \
        "/etc/zivpn/blocked/${username}.blocked" \
        "/etc/hysteria/blocked/${username}.blocked" 2>/dev/null || true

  return 0
}

# ==========================================================
# Fonction : supprimer tous les utilisateurs expirés
# ==========================================================
supprimer_expired() {
  if [ ! -f "$USER_FILE" ] || [ ! -s "$USER_FILE" ]; then
    echo -e "${YELLOW}Aucun utilisateur trouvé.${RESET}"
    return 1
  fi

  local today
  today=$(date +%Y-%m-%d)
  local expired_users=()

  while IFS="|" read -r username password limite expire_date rest; do
    [[ -z "$username" ]] && continue
    if [[ "$expire_date" < "$today" ]]; then
      expired_users+=("$username")
    fi
  done < "$USER_FILE"

  if [ ${#expired_users[@]} -eq 0 ]; then
    echo -e "${GREEN}Aucun utilisateur expiré à supprimer.${RESET}"
    return 0
  fi

  echo -e "${YELLOW}Utilisateurs expirés détectés :${RESET}"
  for u in "${expired_users[@]}"; do
    echo -e "  ${RED}- $u${RESET}"
  done

  echo
  read -rp "${RED}Confirmer suppression de tous ces utilisateurs ? (o/N) : ${RESET}" confirm
  if [[ ! "$confirm" =~ ^[oO]$ ]]; then
    echo -e "${GREEN}Suppression annulée.${RESET}"
    return 0
  fi

  local errors=0
  for user in "${expired_users[@]}"; do
    echo -e "\n${CYAN}── Suppression de $user...${RESET}"
    supprimer_utilisateur "$user" || errors=$(( errors + 1 ))
  done

  echo
  if [ $errors -eq 0 ]; then
    echo -e "${GREEN}✅ Tous les utilisateurs expirés supprimés.${RESET}"
  else
    echo -e "${YELLOW}⚠️  $errors suppression(s) ont échoué.${RESET}"
  fi
}

# ==========================================================
# Menu principal
# ==========================================================
case "$option" in
  1)
    if [ ! -f "$USER_FILE" ] || [ ! -s "$USER_FILE" ]; then
      echo -e "${YELLOW}Aucun utilisateur trouvé.${RESET}"
      read -rp "Appuyez sur Entrée pour revenir au menu..."
      exit 0
    fi

    echo -e "${CYAN}Liste des utilisateurs :${RESET}"
    echo

    TODAY=$(date +%Y-%m-%d)
    mapfile -t ALL_LINES < "$USER_FILE"

    # Filtrer les lignes vides
    VALID_LINES=()
    for line in "${ALL_LINES[@]}"; do
      [[ -n "$line" ]] && VALID_LINES+=("$line")
    done

    if [ ${#VALID_LINES[@]} -eq 0 ]; then
      echo -e "${YELLOW}Aucun utilisateur disponible.${RESET}"
      read -rp "Appuyez sur Entrée pour revenir au menu..."
      exit 0
    fi

    for i in "${!VALID_LINES[@]}"; do
      username=$(echo "${VALID_LINES[$i]}" | cut -d'|' -f1)
      expire=$(echo "${VALID_LINES[$i]}" | cut -d'|' -f4)
      # Statut expiration
      if [[ "$expire" < "$TODAY" ]]; then
        statut="${RED}[EXPIRÉ]${RESET}"
      else
        statut="${GREEN}[ACTIF]${RESET}"
      fi
      # Connecté ?
      if id "$username" &>/dev/null && kill -0 "$(ps -u "$username" -o pid= 2>/dev/null | head -1)" 2>/dev/null; then
        connecte="${YELLOW}[EN LIGNE]${RESET}"
      else
        connecte=""
      fi
      printf "${GREEN}[%02d]${RESET} %-20s expire: %-12s %b %b\n" \
        "$((i+1))" "$username" "$expire" "$statut" "$connecte"
    done

    echo
    read -rp "${CYAN}Entrez les numéros à supprimer (ex: 1,3,5) : ${RESET}" selection

    if ! [[ "$selection" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
      echo -e "${RED}Format invalide. Exemple : 1,3,5${RESET}"
      read -rp "Appuyez sur Entrée pour revenir au menu..."
      exit 1
    fi

    IFS=',' read -ra indexes <<< "$selection"
    declare -A seen
    selected_users=()
    for idx in "${indexes[@]}"; do
      if (( idx < 1 || idx > ${#VALID_LINES[@]} )); then
        echo -e "${RED}Numéro invalide : $idx${RESET}"
        read -rp "Appuyez sur Entrée pour revenir au menu..."
        exit 1
      fi
      if [ -z "${seen[$idx]}" ]; then
        seen[$idx]=1
        selected_users+=("$(echo "${VALID_LINES[$((idx-1))]}" | cut -d'|' -f1)")
      fi
    done

    echo
    echo -e "${YELLOW}Utilisateurs sélectionnés :${RESET}"
    for u in "${selected_users[@]}"; do echo " - $u"; done

    echo
    read -rp "${RED}Confirmer suppression ? (o/N) : ${RESET}" confirm
    if [[ "$confirm" =~ ^[oO]$ ]]; then
      errors=0
      for u in "${selected_users[@]}"; do
        echo -e "\n${CYAN}── Suppression de $u...${RESET}"
        supprimer_utilisateur "$u" || errors=$(( errors + 1 ))
      done
      echo
      if [ "$errors" -eq 0 ]; then
        echo -e "${GREEN}✅ Tous les utilisateurs sélectionnés supprimés.${RESET}"
      else
        echo -e "${YELLOW}⚠️  $errors suppression(s) ont échoué.${RESET}"
      fi
    else
      echo -e "${GREEN}Suppression annulée.${RESET}"
    fi
    ;;
  2)
    supprimer_expired
    ;;
  0|00)
    echo "Sortie..."
    exit 0
    ;;
  *)
    echo -e "${RED}Option invalide.${RESET}"
    ;;
esac

read -rp "Appuyez sur Entrée pour revenir au menu..."
