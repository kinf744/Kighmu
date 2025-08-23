#!/bin/bash
# menu7.sh - Blocage dynamique torrents, sites pornographiques et spam dans un panneau de contrôle

WIDTH=60
CYAN="\e[36m"
YELLOW="\e[33m"
RESET="\e[0m"

DOMAIN_FILE="$HOME/porn_domains.txt"

# Fonctions pour le cadre
line_full() { echo -e "${CYAN}+$(printf '%0.s=' $(seq 1 $WIDTH))+${RESET}"; }
line_simple() { echo -e "${CYAN}+$(printf '%0.s-' $(seq 1 $WIDTH))+${RESET}"; }
content_line() { printf "| %-56s |\n" "$1"; }
center_line() { local text="$1"; local padding=$(( (WIDTH - ${#text}) / 2 )); printf "|%*s%s%*s|\n" "$padding" "" "$text" "$padding" ""; }

# Vérification dynamique des blocages
is_active() { iptables -C $1 2>/dev/null && echo "Actif" || echo "Non actif"; }
porn_active() { [[ ! -f "$DOMAIN_FILE" ]] && echo "Non actif" && return; while read -r domain; do iptables -C OUTPUT -p tcp --dport 80 -m string --string "$domain" --algo bm -j REJECT 2>/dev/null && echo "Actif" && return; done < "$DOMAIN_FILE"; echo "Non actif"; }

# Blocages
block_torrents() { iptables -A OUTPUT -p tcp --dport 6881:6889 -j DROP; iptables -A OUTPUT -p udp --dport 1024:65535 -j DROP; }
unblock_torrents() { iptables -D OUTPUT -p tcp --dport 6881:6889 -j DROP 2>/dev/null; iptables -D OUTPUT -p udp --dport 1024:65535 -j DROP 2>/dev/null; }
block_spam() { iptables -A OUTPUT -p tcp --dport 25 -j DROP; iptables -A OUTPUT -p tcp --dport 465 -j DROP; iptables -A OUTPUT -p tcp --dport 587 -j DROP; }
unblock_spam() { iptables -D OUTPUT -p tcp --dport 25 -j DROP 2>/dev/null; iptables -D OUTPUT -p tcp --dport 465 -j DROP 2>/dev/null; iptables -D OUTPUT -p tcp --dport 587 -j DROP 2>/dev/null; }
block_porn() { [[ ! -f "$DOMAIN_FILE" ]] && echo "Fichier de domaines introuvable." && return; while read -r domain; do iptables -A OUTPUT -p tcp --dport 80 -m string --string "$domain" --algo bm -j REJECT; iptables -A OUTPUT -p tcp --dport 443 -m string --string "$domain" --algo bm -j REJECT; done < "$DOMAIN_FILE"; }
unblock_porn() { [[ ! -f "$DOMAIN_FILE" ]] && return; while read -r domain; do iptables -D OUTPUT -p tcp --dport 80 -m string --string "$domain" --algo bm -j REJECT 2>/dev/null; iptables -D OUTPUT -p tcp --dport 443 -m string --string "$domain" --algo bm -j REJECT 2>/dev/null; done < "$DOMAIN_FILE"; }

# Boucle menu dynamique
while true; do
    clear
    line_full
    center_line "${YELLOW}PANNEAU DE CONTRÔLE DES BLOCAGES${RESET}"
    line_full
    content_line "1) Blocage des torrents        : $(is_active "OUTPUT -p tcp --dport 6881:6889 -j DROP")"
    content_line "2) Blocage sites pornographiques: $(porn_active)"
    content_line "3) Blocage spam SMTP           : $(is_active "OUTPUT -p tcp --dport 25 -j DROP")"
    content_line "0) Quitter"
    line_simple
    echo ""
    read -p "Votre choix : " choice
    echo ""

    case $choice in
        1)
            read -p "Activer (1) ou désactiver (2) le blocage des torrents ? : " act
            [[ "$act" == "1" ]] && block_torrents && echo "Blocage torrents activé."
            [[ "$act" == "2" ]] && unblock_torrents && echo "Blocage torrents désactivé."
            read -p "Appuyez sur Entrée pour continuer..."
            ;;
        2)
            read -p "Activer (1) ou désactiver (2) le blocage sites pornographiques ? : " act
            [[ "$act" == "1" ]] && block_porn && echo "Blocage sites porn activé."
            [[ "$act" == "2" ]] && unblock_porn && echo "Blocage sites porn désactivé."
            read -p "Appuyez sur Entrée pour continuer..."
            ;;
        3)
            read -p "Activer (1) ou désactiver (2) le blocage spam SMTP ? : " act
            [[ "$act" == "1" ]] && block_spam && echo "Blocage spam activé."
            [[ "$act" == "2" ]] && unblock_spam && echo "Blocage spam désactivé."
            read -p "Appuyez sur Entrée pour continuer..."
            ;;
        0)
            echo "Retour au menu principal..."
            sleep 1
            exit 0
            ;;
        *)
            echo "Choix invalide."
            read -p "Appuyez sur Entrée pour continuer..."
            ;;
    esac
done
