#!/bin/bash
# banner.sh - Gestion complète du banner personnalisé Kighmu VPS Manager

BANNER_DIR="$HOME/.kighmu"
BANNER_FILE="$BANNER_DIR/banner.txt"

# Créer le dossier si inexistant
mkdir -p "$BANNER_DIR"

show_banner() {
    if [ -f "$BANNER_FILE" ]; then
        echo -e "\e[36m+--------------------------------------------------+\e[0m"
        while IFS= read -r line; do
            # Interpréter les codes ANSI pour couleur et style
            echo -e "$line"
        done < "$BANNER_FILE"
        echo -e "\e[36m+--------------------------------------------------+\e[0m"
    else
        echo -e "\e[31mAucun banner personnalisé trouvé. Créez-en un dans ce menu.\e[0m"
    fi
}

create_banner() {
    echo -e "\e[33mEntrez votre texte de banner (supporte séquences ANSI pour couleurs/styles). Terminez par une ligne vide :\e[0m"
    tmpfile=$(mktemp)
    while true; do
        read -r line
        [[ -z "$line" ]] && break
        echo "$line" >> "$tmpfile"
    done
    mv "$tmpfile" "$BANNER_FILE"
    echo -e "\e[32mBanner sauvegardé avec succès : $BANNER_FILE\e[0m"
}

delete_banner() {
    if [ -f "$BANNER_FILE" ]; then
        rm -f "$BANNER_FILE"
        echo -e "\e[31mBanner supprimé avec succès.\e[0m"
    else
        echo -e "\e[33mAucun banner à supprimer.\e[0m"
    fi
}

while true; do
    clear
    echo -e "\e[36m+===================== Gestion Banner =====================+\e[0m"
    echo -e "\e[33m1) Afficher le banner"
    echo -e "2) Créer / Modifier le banner"
    echo -e "3) Supprimer le banner"
    echo -e "\e[31m0) Quitter\e[0m"
    echo -ne "\e[36mChoix : \e[0m"
    read -r choix
    case $choix in
        1) show_banner; read -p "Appuyez sur Entrée pour continuer..." ;;
        2) create_banner; read -p "Appuyez sur Entrée pour continuer..." ;;
        3) delete_banner; read -p "Appuyez sur Entrée pour continuer..." ;;
        0) break ;;
        *) echo -e "\e[31mChoix invalide, réessayez.\e[0m"; sleep 1 ;;
    esac
done
