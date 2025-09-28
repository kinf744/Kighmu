#!/bin/bash
# menu4.sh - Supprimer un utilisateur ou tous les utilisateurs expirés

USER_FILE="/etc/kighmu/users.list"

# Couleurs
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

clear

echo -e "${CYAN}+--------------------------------------------+${RESET}"
echo -e "${BOLD}|          GESTION DES UTILISATEURS          |${RESET}"
echo -e "${CYAN}+--------------------------------------------+${RESET}"
echo -e ""
echo "[01] Supprimer un utilisateur"
echo "[02] Supprimer tous les utilisateurs expirés"
echo "[00] Quitter"
read -rp "Sélectionnez une option (1/2/0) : " option

# Fonction pour supprimer un utilisateur donné
supprimer_utilisateur() {
    local username=$1

    if ! grep -q "^$username|" "$USER_FILE"; then
        echo -e "${RED}Utilisateur '$username' introuvable dans la liste.${RESET}"
        return 1
    fi

    read -rp "${YELLOW}Confirmez suppression de l'utilisateur '${username}' ? (o/N) : ${RESET}" confirm
    if [[ ! "$confirm" =~ ^[oO]$ ]]; then
        echo -e "${GREEN}Suppression annulée.${RESET}"
        return 0
    fi

    if id "$username" &>/dev/null; then
        if sudo userdel -r "$username"; then
            echo -e "${GREEN}Utilisateur système '${username}' supprimé avec succès.${RESET}"
        else
            echo -e "${RED}Erreur lors de la suppression de l'utilisateur système '${username}'.${RESET}"
            return 1
        fi
    else
        echo -e "${YELLOW}Utilisateur système '${username}' non trouvé ou déjà supprimé.${RESET}"
    fi

    # Suppression de la ligne dans users.list
    if grep -v "^$username|" "$USER_FILE" > "${USER_FILE}.tmp"; then
        mv "${USER_FILE}.tmp" "$USER_FILE"
        echo -e "${GREEN}Utilisateur '${username}' supprimé de la liste utilisateurs.${RESET}"
    else
        echo -e "${RED}Erreur : impossible de mettre à jour la liste des utilisateurs.${RESET}"
        return 1
    fi

    return 0
}

# Fonction pour supprimer tous les utilisateurs expirés
supprimer_expired() {
    if [ ! -f "$USER_FILE" ]; then
        echo -e "${YELLOW}Aucun fichier utilisateurs trouvé.${RESET}"
        return 1
    fi

    # Date actuelle en format YYYY-MM-DD
    local today=$(date +%Y-%m-%d)

    # On parcourt le fichier users.list et on récupère les utilisateurs expirés
    local expired_users=()
    while IFS="|" read -r username password limite expire_date hostip domain slowdns_ns; do
        # Comparer la date d'expiration avec la date actuelle
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

    read -rp "${YELLOW}Confirmez suppression de tous les utilisateurs expirés ci-dessus ? (o/N) : ${RESET}" confirm
    if [[ ! "$confirm" =~ ^[oO]$ ]]; then
        echo -e "${GREEN}Suppression annulée.${RESET}"
        return 0
    fi

    # Suppression des utilisateurs un par un
    local errors=0
    for user in "${expired_users[@]}"; do
        echo "Suppression de l'utilisateur : $user"
        if ! supprimer_utilisateur "$user"; then
            echo -e "${RED}Erreur lors de la suppression de l'utilisateur $user.${RESET}"
            errors=$((errors + 1))
        fi
    done

    if [ $errors -eq 0 ]; then
        echo -e "${GREEN}Tous les utilisateurs expirés ont été supprimés avec succès.${RESET}"
    else
        echo -e "${RED}Certaines suppressions ont échoué.${RESET}"
    fi
}

case "$option" in
    1)
        if [ ! -f "$USER_FILE" ]; then
            echo -e "${YELLOW}Aucun utilisateur trouvé.${RESET}"
            read -rp "${BOLD}Appuyez sur Entrée pour revenir au menu...${RESET}"
            exit 0
        fi
        echo -e "${CYAN}Utilisateurs existants :${RESET}"
        cut -d'|' -f1 "$USER_FILE"
        read -rp "${BOLD}Nom de l'utilisateur à supprimer : ${RESET}" username
        supprimer_utilisateur "$username"
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

read -rp "${BOLD}Appuyez sur Entrée pour revenir au menu...${RESET}"
