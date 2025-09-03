#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BANNERS_DIR="$SCRIPT_DIR/banners"
CUSTOM_BANNER="$BANNERS_DIR/banner_custom.txt"

mkdir -p "$BANNERS_DIR"

show_banner() {
    if [ -f "$CUSTOM_BANNER" ]; then
        echo -e "\e[36m+===================== Banner Personnalisé =====================+\e[0m"
        while IFS= read -r line; do
            echo -e "$line"
        done < "$CUSTOM_BANNER"
        echo -e "\e[36m+================================================================+\e[0m"
    else
        echo -e "\e[31mAucun banner personnalisé trouvé.\e[0m"
    fi
}

create_banner() {
    echo -e "\e[33mPour ajouter des couleurs et styles, utilisez les séquences suivantes dans votre texte :\e[0m"
    echo -e "\e[33mEx : \\\\e[31mTexte rouge\\\\e[0m, \\\\e[1;34mGras bleu\\\\e[0m, \\\\e[4mSouligné\\\\e[0m\e[0m"
    echo -e "Liste rapide des codes usuels :"
    echo -e "  \e[31m\\e[31m\e[0m Rouge  \e[32m\\e[32m\e[0m Vert  \e[33m\\e[33m\e[0m Jaune  \e[34m\\e[34m\e[0m Bleu"
    echo -e "  \e[35m\\e[35m\e[0m Magenta  \e[36m\\e[36m\e[0m Cyan  \e[1mGras  \e[4mSouligné\e[0m"
    echo -e "\e[33mEntrez votre texte de banner personnalisé ligne par ligne. Terminez par une ligne vide :\e[0m"
    tmpfile=$(mktemp)
    while true; do
        read -r line
        [[ -z "$line" ]] && break
        echo "$line" >> "$tmpfile"
    done
    mv "$tmpfile" "$CUSTOM_BANNER"
    echo -e "\e[32mBanner sauvegardé avec succès dans $CUSTOM_BANNER.\e[0m"
}

delete_banner() {
    if [ -f "$CUSTOM_BANNER" ]; then
        rm -f "$CUSTOM_BANNER"
        echo -e "\e[31mBanner personnalisé supprimé.\e[0m"
    else
        echo -e "\e[33mAucun banner personnalisé à supprimer.\e[0m"
    fi
}

while true; do
    clear
    echo -e "\e[36m+==================================================+\e[0m"
    echo -e "\e[36m|              ${BOLD}GESTION BANNER VPS KIGHMU${RESET}${CYAN}              |\e[0m"
    echo -e "\e[36m+==================================================+\e[0m"
    echo -e "\e[36m|  \e[33m1) Créer / Modifier un banner personnalisé       \e[36m|\e[0m"
    echo -e "\e[36m|  \e[33m2) Afficher le banner personnalisé               \e[36m|\e[0m"
    echo -e "\e[36m|  \e[33m3) Supprimer le banner personnalisé               \e[36m|\e[0m"
    echo -e "\e[36m|  \e[31m0) Quitter                                        \e[36m|\e[0m"
    echo -e "\e[36m+==================================================+\e[0m"
    echo -ne "\e[33mEntrez votre choix [0-3] : \e[0m"
    read -r choix

    case $choix in
        1)
            create_banner
            read -p "Appuyez sur Entrée pour revenir au menu..."
            ;;
        2)
            show_banner
            read -p "Appuyez sur Entrée pour revenir au menu..."
            ;;
        3)
            delete_banner
            read -p "Appuyez sur Entrée pour revenir au menu..."
            ;;
        0)
            echo -e "\e[31mRetour au menu principal...\e[0m"
            break
            ;;
        *)
            echo -e "\e[31mChoix invalide ! Veuillez réessayer.\e[0m"
            sleep 1
            ;;
    esac
done
