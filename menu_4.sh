#!/bin/bash
# menu_4.sh - Modifier la durée ou le mot de passe d'un ou plusieurs utilisateurs

USER_FILE="/etc/kighmu/users.list"

# ==========================================================
# Gestion portable des couleurs
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
            MAGENTA_VIF="$(tput setaf 5; tput bold)"
            BOLD="$(tput bold)"
            RESET="$(tput sgr0)"
        fi
    fi
}
setup_colors
clear

# ==========================================================
# Titre du panneau de contrôle
# ==========================================================
echo -e "${MAGENTA_VIF}+--------------------------------------------+${RESET}"
echo -e "${MAGENTA_VIF}|          MODIFIER DUREE / MOT DE PASSE    |${RESET}"
echo -e "${MAGENTA_VIF}+--------------------------------------------+${RESET}"

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

# Lecture des numéros (ex: 1 ou 1,3,5)
read -rp "${CYAN}Entrez le(s) numéro(s) des utilisateurs à modifier (ex: 1,3) : ${RESET}" input_nums

# Vérification et création d'un tableau des indices
IFS=',' read -ra indices <<< "$input_nums"
for idx in "${indices[@]}"; do
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > ${#users[@]} )); then
        echo -e "${RED}Numéro invalide : $idx${RESET}"
        read -rp "Appuyez sur Entrée pour revenir au menu..."
        exit 1
    fi
done

# Menu des actions possibles
echo
echo -e "${GREEN}${BOLD}[01]${RESET} ${YELLOW}Durée d'expiration du compte${RESET}"
echo -e "${GREEN}${BOLD}[02]${RESET} ${YELLOW}Mot de passe${RESET}"
echo -e "${GREEN}${BOLD}[00]${RESET} ${YELLOW}Retour au menu${RESET}"

read -rp "${CYAN}Entrez votre choix [00-02] : ${RESET}" choice2

case $choice2 in
    1|01)  # Modification durée
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

        # Modifier chaque utilisateur sélectionné
        for idx in "${indices[@]}"; do
            idx=$((idx-1))
            username="${users[$idx]}"
            user_line=$(grep "^$username|" "$USER_FILE")
            IFS="|" read -r user pass limite expire_date hostip domain slowdns_ns <<< "$user_line"

            echo -e "${YELLOW}Modification durée de : ${BOLD}$username${RESET} (nouvelle expiration : $new_expire)"
            read -rp "${RED}Confirmer ? (o/N) : ${RESET}" confirm
            if [[ "$confirm" =~ ^[oO]$ ]]; then
                new_line="${user}|${pass}|${new_limit}|${new_expire}|${hostip}|${domain}|${slowdns_ns}"
                sed -i "s/^$user|.*/$new_line/" "$USER_FILE"
                echo -e "${GREEN}Durée modifiée pour $username${RESET}"
            else
                echo -e "${GREEN}Modification annulée pour $username${RESET}"
            fi
        done
        ;;
    2|02)  # Modification mot de passe
        echo
        read -s -rp "Nouveau mot de passe (sera appliqué à chaque utilisateur) : " pass1
        echo
        for idx in "${indices[@]}"; do
            idx=$((idx-1))
            username="${users[$idx]}"
            user_line=$(grep "^$username|" "$USER_FILE")
            IFS="|" read -r user pass limite expire_date hostip domain slowdns_ns <<< "$user_line"

            echo -e "${YELLOW}Modification mot de passe de : ${BOLD}$username${RESET}"
            read -rp "${RED}Confirmer ? (o/N) : ${RESET}" confirm
            if [[ "$confirm" =~ ^[oO]$ ]]; then
                new_line="${user}|${pass1}|${limite}|${expire_date}|${hostip}|${domain}|${slowdns_ns}"
                sed -i "s/^$user|.*/$new_line/" "$USER_FILE"
                # Mise à jour mot de passe système
                echo -e "$pass1\n$pass1" | sudo passwd "$user" >/dev/null 2>&1
                echo -e "${GREEN}Mot de passe modifié pour $username${RESET}"
            else
                echo -e "${GREEN}Modification annulée pour $username${RESET}"
            fi
        done
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
