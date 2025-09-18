#!/bin/bash
# menu4_2.sh - Gestion complète du banner personnalisé Kighmu VPS Manager

BANNER_DIR="$HOME/.kighmu"
BANNER_FILE="$BANNER_DIR/banner.txt"

# Couleurs
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# Créer le dossier si inexistant
mkdir -p "$BANNER_DIR"

show_banner() {
    clear
    if [ -f "$BANNER_FILE" ]; then
        echo -e "${CYAN}+--------------------------------------------------+${RESET}"
        while IFS= read -r line; do
            echo -e "$line"
        done < "$BANNER_FILE"
        echo -e "${CYAN}+--------------------------------------------------+${RESET}"
    else
        echo -e "${RED}Aucun banner personnalisé trouvé. Créez-en un dans ce menu.${RESET}"
    fi
    read -p "Appuyez sur Entrée pour continuer..."
}

create_banner() {
    # S'assurer que le dossier existe
    mkdir -p "$BANNER_DIR"

    clear
    echo -e "${YELLOW}Entrez votre texte de banner (supporte séquences ANSI pour couleurs/styles). Terminez par une ligne vide :${RESET}"
    tmpfile=$(mktemp)
    while true; do
        read -r line
        [[ -z "$line" ]] && break
        echo "$line" >> "$tmpfile"
    done
    mv "$tmpfile" "$BANNER_FILE"
    echo -e "${GREEN}Banner sauvegardé avec succès : $BANNER_FILE${RESET}"
    read -p "Appuyez sur Entrée pour continuer..."
}

delete_banner() {
    clear
    if [ -f "$BANNER_FILE" ]; then
        rm -f "$BANNER_FILE"
        echo -e "${RED}Banner supprimé avec succès.${RESET}"
    else
        echo -e "${YELLOW}Aucun banner à supprimer.${RESET}"
    fi
    read -p "Appuyez sur Entrée pour continuer..."
}

while true; do
    clear
    echo -e "${CYAN}+===================== Gestion Banner =====================+${RESET}"
    echo -e "${GREEN}${BOLD}[01]${RESET} ${YELLOW}Afficher le banner${RESET}"
    echo -e "${GREEN}${BOLD}[02]${RESET} ${YELLOW}Créer / Modifier le banner${RESET}"
    echo -e "${GREEN}${BOLD}[03]${RESET} ${YELLOW}Supprimer le banner${RESET}"
    echo -e "${RED}[00]${RESET} Quitter"
    echo -ne "${CYAN}Choix : ${RESET}"
    read -r choix
    case $choix in
        1|01) show_banner ;;
        2|02) create_banner ;;
        3|03) delete_banner ;;
        0|00) break ;;
        *) echo -e "${RED}Choix invalide, réessayez.${RESET}"; sleep 1 ;;
    esac
done
