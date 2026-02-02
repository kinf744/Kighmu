#!/bin/bash
# menu4.sh - Supprimer un utilisateur ou tous les utilisateurs expirés

USER_FILE="/etc/kighmu/users.list"

# ==========================================================
# Détection portable et sûre des couleurs
# ==========================================================
setup_colors() {
    RED=""
    GREEN=""
    YELLOW=""
    CYAN=""
    MAGENTA_VIF=""
    BOLD=""
    RESET=""

    if [ -t 1 ]; then
        if [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
            RED="$(tput setaf 1)"
            GREEN="$(tput setaf 2)"
            YELLOW="$(tput setaf 3)"
            CYAN="$(tput setaf 6)"
            MAGENTA_VIF="$(tput setaf 5; tput bold)"  # titre panneau
            BOLD="$(tput bold)"
            RESET="$(tput sgr0)"
        fi
    fi
}

setup_colors
clear

# ==========================================================
# Titre du panneau de contrôle en MAGENTA vif
# ==========================================================
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
# Fonction : supprimer un utilisateur donné (sans confirmation)
# ==========================================================
supprimer_utilisateur() {
    local username="$1"
    local phone password
    local TODAY
    TODAY=$(date +%Y-%m-%d)

    # 🔎 Récupération AVANT suppression
    read -r phone password < <(
        awk -F'|' -v u="$username" '$1==u {print $1, $2}' "$USER_FILE"
    )

    if [[ -z "$password" ]]; then
        echo -e "${RED}Utilisateur '$username' introuvable.${RESET}"
        return 1
    fi

    # 1️⃣ SUPPRESSION UTILISATEUR SYSTÈME
    if id "$username" &>/dev/null; then
        if userdel -r "$username" &>/dev/null; then
            echo -e "${GREEN}Utilisateur système '$username' supprimé.${RESET}"
        else
            echo -e "${RED}Erreur suppression système '$username'.${RESET}"
            return 1
        fi
    fi

    # 2️⃣ SUPPRESSION KIGHMU
    grep -v "^$username|" "$USER_FILE" > "${USER_FILE}.tmp" &&
    mv "${USER_FILE}.tmp" "$USER_FILE"
    echo -e "${GREEN}Kighmu: '$username' supprimé.${RESET}"

    # ================== ZIVPN SYNC ==================
    ZIVPN_USER_FILE="/etc/zivpn/users.list"
    ZIVPN_CONFIG="/etc/zivpn/config.json"

    if [[ -f "$ZIVPN_USER_FILE" ]]; then
        grep -v "^$phone|" "$ZIVPN_USER_FILE" > "${ZIVPN_USER_FILE}.tmp" &&
        mv "${ZIVPN_USER_FILE}.tmp" "$ZIVPN_USER_FILE" &&
        chmod 600 "$ZIVPN_USER_FILE"

        ZPASS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" | sort -u)
        tmp=$(mktemp)

        if jq --argjson arr "$(printf '%s\n' "$ZPASS" | jq -R . | jq -s .)" \
              '.auth.config = $arr' "$ZIVPN_CONFIG" > "$tmp" &&
           jq empty "$tmp" >/dev/null 2>&1; then

            mv "$tmp" "$ZIVPN_CONFIG"
            systemctl restart zivpn.service
            echo -e "${GREEN}✅ ZIVPN synchronisé.${RESET}"
        else
            rm -f "$tmp"
            echo -e "${YELLOW}⚠️ ZIVPN non modifié (sécurité).${RESET}"
        fi
    fi

    # ================== HYSTERIA SYNC ==================
    HYSTERIA_USER_FILE="/etc/hysteria/users.txt"
    HYSTERIA_CONFIG="/etc/hysteria/config.json"

    if [[ -f "$HYSTERIA_USER_FILE" ]]; then
        grep -v "^$username|" "$HYSTERIA_USER_FILE" > "${HYSTERIA_USER_FILE}.tmp" &&
        mv "${HYSTERIA_USER_FILE}.tmp" "$HYSTERIA_USER_FILE" &&
        chmod 600 "$HYSTERIA_USER_FILE"

        HPASS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$HYSTERIA_USER_FILE" | sort -u)
        tmp=$(mktemp)

        if jq --argjson arr "$(printf '%s\n' "$HPASS" | jq -R . | jq -s .)" \
              '.auth.config = $arr' "$HYSTERIA_CONFIG" > "$tmp" &&
           jq empty "$tmp" >/dev/null 2>&1; then

            mv "$tmp" "$HYSTERIA_CONFIG"
            systemctl restart hysteria.service
            echo -e "${GREEN}✅ HYSTERIA synchronisé.${RESET}"
        else
            rm -f "$tmp"
            echo -e "${YELLOW}⚠️ HYSTERIA non modifié (sécurité).${RESET}"
        fi
    fi

    return 0
}

# ==========================================================
# Fonction : supprimer tous les utilisateurs expirés
# ==========================================================
supprimer_expired() {
    if [ ! -f "$USER_FILE" ]; then
        echo -e "${YELLOW}Aucun fichier utilisateurs trouvé.${RESET}"
        return 1
    fi

    local today
    today=$(date +%Y-%m-%d)

    local expired_users=()
    while IFS="|" read -r username password limite expire_date hostip domain slowdns_ns; do
        if [[ "$expire_date" < "$today" ]]; then
            expired_users+=("$username")
        fi
    done < "$USER_FILE"

    if [ ${#expired_users[@]} -eq 0 ]; then
        echo -e "${GREEN}Aucun utilisateur expiré à supprimer.${RESET}"
        return 0
    fi

    echo -e "${YELLOW}Les utilisateurs suivants sont expirés :${RESET}"
    printf '%s\n' "${expired_users[@]}"

    read -rp "${RED}Confirmez suppression de tous ces utilisateurs expirés ? (o/N) : ${RESET}" confirm
    if [[ ! "$confirm" =~ ^[oO]$ ]]; then
        echo -e "${GREEN}Suppression annulée.${RESET}"
        return 0
    fi

    local errors=0
    for user in "${expired_users[@]}"; do
        if ! supprimer_utilisateur "$user"; then
            errors=$((errors + 1))
        fi
    done

    if [ $errors -eq 0 ]; then
        echo -e "${GREEN}Tous les utilisateurs expirés ont été supprimés avec succès.${RESET}"
    else
        echo -e "${YELLOW}Certaines suppressions ont échoué.${RESET}"
    fi
}

# ==========================================================
# Menu principal
# ==========================================================
case "$option" in
    1)
        if [ ! -f "$USER_FILE" ]; then
            echo -e "${YELLOW}Aucun utilisateur trouvé.${RESET}"
            read -rp "Appuyez sur Entrée pour revenir au menu..."
            exit 0
        fi

        echo -e "${CYAN}Liste des utilisateurs :${RESET}"
        echo

        mapfile -t users < <(cut -d'|' -f1 "$USER_FILE")
        mapfile -t expires < <(cut -d'|' -f4 "$USER_FILE")

        if [ ${#users[@]} -eq 0 ]; then
            echo -e "${YELLOW}Aucun utilisateur disponible.${RESET}"
            read -rp "Appuyez sur Entrée pour revenir au menu..."
            exit 0
        fi

        for i in "${!users[@]}"; do
            printf "%s[%02d]%s %-20s %s(expire : %s)%s\n" \
                "$GREEN" "$((i+1))" "$RESET" \
                "${users[$i]}" \
                "$CYAN" "${expires[$i]}" "$RESET"
        done

        echo
        read -rp "${CYAN}Entrez les numéros à supprimer (ex: 1,3,5) : ${RESET}" selection

        if ! [[ "$selection" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
            echo -e "${RED}Format invalide. Exemple valide : 1,3,5${RESET}"
            read -rp "Appuyez sur Entrée pour revenir au menu..."
            exit 1
        fi

        IFS=',' read -ra indexes <<< "$selection"
        declare -A seen
        selected_users=()
        for idx in "${indexes[@]}"; do
            if (( idx < 1 || idx > ${#users[@]} )); then
                echo -e "${RED}Numéro invalide : $idx${RESET}"
                read -rp "Appuyez sur Entrée pour revenir au menu..."
                exit 1
            fi
            if [ -z "${seen[$idx]}" ]; then
                seen[$idx]=1
                selected_users+=("${users[$((idx-1))]}")
            fi
        done

        echo
        echo -e "${YELLOW}Utilisateurs sélectionnés pour suppression :${RESET}"
        for u in "${selected_users[@]}"; do
            echo " - $u"
        done

        echo
        read -rp "${RED}Confirmer la suppression de TOUS ces utilisateurs ? (o/N) : ${RESET}" confirm

        if [[ "$confirm" =~ ^[oO]$ ]]; then
            errors=0
            for u in "${selected_users[@]}"; do
                if ! supprimer_utilisateur "$u"; then
                    errors=$((errors + 1))
                fi
            done

            if [ "$errors" -eq 0 ]; then
                echo -e "${GREEN}Tous les utilisateurs sélectionnés ont été supprimés avec succès.${RESET}"
            else
                echo -e "${YELLOW}Certaines suppressions ont échoué.${RESET}"
            fi
        else
            echo -e "${GREEN}Suppression annulée.${RESET}"
        fi
        ;;
    2)
        supprimer_expired
        ;;
    0)
        echo "Sortie..."
        exit 0
        ;;
    *)
        echo -e "${RED}Option invalide.${RESET}"
        ;;
esac

read -rp "Appuyez sur Entrée pour revenir au menu..."
