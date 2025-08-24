#!/bin/bash
# ==============================================
# menu7.sh - Blocage des torrents, porno et spam
# ==============================================

WIDTH=60
CYAN="\e[36m"
RESET="\e[0m"

# Fonctions d'affichage
line_full() { echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
content_line() { printf "| %-56s |\n" "$1"; }
center_line() {
    local text="$1"
    local clean_text=$(echo -e "$text" | sed 's/\x1B\[[0-9;]*[mK]//g')
    local padding=$(( (WIDTH - ${#clean_text}) / 2 ))
    printf "|%*s%s%*s|\n" "$padding" "" "$text" "$padding" ""
}

# Vérification état blocage
check_block() {
    local type="$1"
    case $type in
        torrents)
            iptables -C OUTPUT -p tcp --dport 6881:6889 -j DROP 2>/dev/null && echo "[ACTIF]" || echo "[INACTIF]"
            ;;
        porno)
            iptables -C OUTPUT -p tcp -m string --string "porn" --algo bm -j DROP 2>/dev/null && echo "[ACTIF]" || echo "[INACTIF]"
            ;;
        spam)
            iptables -C OUTPUT -p tcp --dport 25 -j DROP 2>/dev/null && echo "[ACTIF]" || echo "[INACTIF]"
            ;;
        *)
            echo "[INCONNU]"
            ;;
    esac
}

# Activer blocage
enable_block() {
    local type="$1"
    case $type in
        torrents)
            iptables -A OUTPUT -p tcp --dport 6881:6889 -j DROP
            iptables -A OUTPUT -p udp --dport 1024:65535 -j DROP
            ;;
        porno)
            # Exemple simple : bloquer certains mots (à adapter)
            iptables -A OUTPUT -p tcp -m string --string "porn" --algo bm -j DROP
            ;;
        spam)
            iptables -A OUTPUT -p tcp --dport 25 -j DROP
            ;;
    esac
}

# Désactiver blocage
disable_block() {
    local type="$1"
    case $type in
        torrents)
            iptables -D OUTPUT -p tcp --dport 6881:6889 -j DROP 2>/dev/null
            iptables -D OUTPUT -p udp --dport 1024:65535 -j DROP 2>/dev/null
            ;;
        porno)
            iptables -D OUTPUT -p tcp -m string --string "porn" --algo bm -j DROP 2>/dev/null
            ;;
        spam)
            iptables -D OUTPUT -p tcp --dport 25 -j DROP 2>/dev/null
            ;;
    esac
}

# Boucle menu
while true; do
    clear
    line_full
    center_line "BLOCAGE DES CONTENUS"
    line_full
    content_line "1) Blocage complet des torrents : $(check_block torrents)"
    content_line "2) Blocage complet des sites pornographiques : $(check_block porno)"
    content_line "3) Blocage complet du spam (port 25) : $(check_block spam)"
    content_line "0) Retour au menu principal"
    line_simple

    read -p "Votre choix : " choice
    case $choice in
        1)
            enable_block torrents
            echo "Blocage des torrents activé."
            read -p "Appuyez sur Entrée pour continuer..."
            ;;
        2)
            enable_block porno
            echo "Blocage des sites pornographiques activé."
            read -p "Appuyez sur Entrée pour continuer..."
            ;;
        3)
            enable_block spam
            echo "Blocage du spam activé."
            read -p "Appuyez sur Entrée pour continuer..."
            ;;
        0) break ;;
        *) echo "Choix invalide !" ; read -p "Appuyez sur Entrée pour continuer..." ;;
    esac
done
