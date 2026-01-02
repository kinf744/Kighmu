#!/bin/bash
# menu_4.sh - Modifier la durée ou le mot de passe d'un utilisateur

USER_FILE="/etc/kighmu/users.list"

# ==========================================================
# Gestion portable des couleurs
# ==========================================================
setup_colors() {
    RED=""
    GREEN=""
    YELLOW=""
    CYAN=""
    BOLD=""
    RESET=""
    if [ -t 1 ]; then
        if [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
            RED="$(tput setaf 1)"
            GREEN="$(tput setaf 2)"
            YELLOW="$(tput setaf 3)"
            CYAN="$(tput setaf 6)"
            BOLD="$(tput bold)"
            RESET="$(tput sgr0)"
        fi
    fi
}
setup_colors
clear

echo -e "${CYAN}+--------------------------------------------+${RESET}"
echo -e "${BOLD}|          MODIFIER DUREE / MOT DE PASSE    |${RESET}"
echo -e "${CYAN}+--------------------------------------------+${RESET}"

if [ ! -f "$USER_FILE" ]; then
    echo -e "${RED}Aucun utilisateur trouvé.${RESET}"
    read -rp "Appuyez sur Entrée pour revenir au menu..."
    exit 0
fi

# ==========================================================
# Charger utilisateurs + dates d'expiration
# ==========================================================
mapfile -t users < <(cut -d'|' -f1 "$USER_FILE")
mapfile -t expires < <(cut -d'|' -f4 "$USER_FILE")

if [ ${#users[@]} -eq 0 ]; then
    echo -e "${RED}Aucun utilisateur disponible.${RESET}"
    read -rp "Appuyez sur Entrée pour revenir au menu..."
    exit 0
fi

# Affichage numéroté avec date d'expiration
echo -e "${BOLD}Liste des utilisateurs :${RESET}"
for i in "${!users[@]}"; do
    printf "%s[%02d]%s %-20s %s(expire : %s)%s\n" \
        "$GREEN" "$((i+1))" "$RESET" \
        "${users[$i]}" \
        "$CYAN" "${expires[$i]}" "$RESET"
done
echo

# Lecture du numéro de l'utilisateur
read -rp "${CYAN}Entrez le numéro de l'utilisateur à modifier : ${RESET}" choice

# Validation stricte
if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#users[@]} )); then
    echo -e "${RED}Numéro invalide.${RESET}"
    read -rp "Appuyez sur Entrée pour revenir au menu..."
    exit 1
fi

username="${users[$((choice-1))]}"
user_line=$(grep "^$username|" "$USER_FILE")
IFS="|" read -r user pass limite expire_date hostip domain slowdns_ns <<< "$user_line"

# ==========================================================
# Menu des actions possibles
# ==========================================================
echo
echo -e "${GREEN}${BOLD}[01]${RESET} ${YELLOW}Durée d'expiration du compte${RESET}"
echo -e "${GREEN}${BOLD}[02]${RESET} ${YELLOW}Mot de passe${RESET}"
echo -e "${GREEN}${BOLD}[00]${RESET} ${YELLOW}Retour au menu${RESET}"

read -rp "${CYAN}Entrez votre choix [00-02] : ${RESET}" choice2

case $choice2 in
    1|01)
        echo
        read -rp "Nouvelle durée d'expiration (en jours, 0 pour pas d'expiration) : " new_limit
        if ! [[ "$new_limit" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Valeur invalide.${RESET}"
            read -rp "Appuyez sur Entrée pour revenir au menu..."
            exit 1
        fi

        if [ "$new_limit" -eq 0 ]; then
            new_expire="none"
        else
            new_expire=$(date -d "+$new_limit days" +%Y-%m-%d)
        fi

        # Confirmation
        echo -e "${YELLOW}Vous êtes sur le point de modifier la durée de : ${BOLD}$username${RESET} (expire : $new_expire)"
        read -rp "${RED}Confirmer ? (o/N) : ${RESET}" confirm
        if [[ ! "$confirm" =~ ^[oO]$ ]]; then
            echo -e "${GREEN}Modification annulée.${RESET}"
            exit 0
        fi

        # Mise à jour du fichier users.list
        new_line="${user}|${pass}|${new_limit}|${new_expire}|${hostip}|${domain}|${slowdns_ns}"
        sed -i "s/^$user|.*/$new_line/" "$USER_FILE"

        echo -e "${GREEN}Durée modifiée avec succès.${RESET}"
        ;;
    2|02)
        echo
        read -s -rp "Nouveau mot de passe : " pass1
        echo
        read -s -rp "Confirmez le mot de passe : " pass2
        echo
        if [ "$pass1" != "$pass2" ]; then
            echo -e "${RED}Les mots de passe ne correspondent pas.${RESET}"
            read -rp "Appuyez sur Entrée pour revenir au menu..."
            exit 1
        fi

        # Confirmation
        echo -e "${YELLOW}Vous êtes sur le point de modifier le mot de passe de : ${BOLD}$username${RESET}"
        read -rp "${RED}Confirmer ? (o/N) : ${RESET}" confirm
        if [[ ! "$confirm" =~ ^[oO]$ ]]; then
            echo -e "${GREEN}Modification annulée.${RESET}"
            exit 0
        fi

        # Mise à jour du fichier users.list
        new_line="${user}|${pass1}|${limite}|${expire_date}|${hostip}|${domain}|${slowdns_ns}"
        sed -i "s/^$user|.*/$new_line/" "$USER_FILE"

        # Mise à jour mot de passe système
        if echo -e "$pass1\n$pass1" | sudo passwd "$user" >/dev/null 2>&1; then
            echo -e "${GREEN}Mot de passe modifié avec succès.${RESET}"
        else
            echo -e "${RED}Erreur lors de la modification du mot de passe système.${RESET}"
        fi
        ;;
    0|00)
        echo "Retour au menu..."
        exit 0
        ;;
    *)
        echo -e "${RED}Choix invalide.${RESET}"
        ;;
esac

read -rp "Appuyez sur Entrée pour revenir au menu..."
