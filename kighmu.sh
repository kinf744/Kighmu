#!/bin/bash
# ==============================================
# Kighmu VPS Manager
# Copyright (c) 2025 Kinf744
# Licence MIT (version française)
# Voir le fichier LICENSE pour plus de détails
# ==============================================

# Largeur cadre
WIDTH=50

# Fonction affiche ligne cadre plein
line_full() {
    echo "+$(printf '%0.s=' $(seq 1 $WIDTH))+"
}

# Fonction affiche ligne cadre simple
line_simple() {
    echo "+$(printf '%0.s-' $(seq 1 $WIDTH))+"
}

# Fonction affiche une ligne de contenu avec padding droite
content_line() {
    local content="$1"
    printf "| %-${WIDTH}s |\n" "$content"
}

# Fonction affiche ligne centrée (corrigée pour toujours fermer)
center_line() {
    local text="$1"
    local text_len=${#text}
    local padding=$(( (WIDTH - text_len) / 2 ))
    local extra=$(( (WIDTH - text_len) % 2 ))
    printf "|%*s%s%*s|\n" $padding "" "$text" $((padding+extra)) ""
}

# Fonction pour afficher une ligne avec deux éléments alignés
double_content() {
    local left="$1"
    local right="$2"
    local total_space=$((WIDTH - ${#left} - ${#right}))
    printf "| %s%*s%s |\n" "$left" $total_space "" "$right"
}

# Récupérer le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while true; do
    clear

    line_full
    center_line "K I G H M U   M A N A G E R"
    line_full

    # Récupération IP, RAM et CPU
    IP=$(hostname -I | awk '{print $1}')
    RAM_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }')
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{printf "%.2f%%", $2+$4}')

    # Compter utilisateurs normaux (UID >= 1000 et < 65534)
    USER_COUNT=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd | wc -l)

    # Compter connexions TCP établies au port 8080 (proxy SOCKS)
    CONNECTED_DEVICES=$(ss -tn state established '( sport = :8080 )' | tail -n +2 | wc -l)

    double_content "IP: $IP" "RAM utilisée: $RAM_USAGE"
    double_content "CPU utilisé: $CPU_USAGE" " "
    line_simple

    double_content "Utilisateurs créés: $USER_COUNT" "Appareils connectés: $CONNECTED_DEVICES"
    line_simple

    center_line "MENU PRINCIPAL:"
    line_simple

    content_line "1. Créer un utilisateur"
    content_line "2. Créer un test utilisateur"
    content_line "3. Voir les utilisateurs en ligne"
    content_line "4. Supprimer utilisateur"
    content_line "5. Installation de mode"
    content_line "6. Désinstaller le script"
    content_line "7. Blocage de torrents"
    content_line "8. Quitter"
    line_simple

    printf "| %-${WIDTH}s |\n" "Entrez votre choix [1-8]: "
    line_full   # <<< fermée complètement en bas !

    read -p "| Votre choix: " choix
    
    case $choix in
      1) bash "$SCRIPT_DIR/menu1.sh" ;;
      2) bash "$SCRIPT_DIR/menu2.sh" ;;
      3) bash "$SCRIPT_DIR/menu3.sh" ;;
      4) bash "$SCRIPT_DIR/menu4.sh" ;;
      5) bash "$SCRIPT_DIR/menu5.sh" ;;
      6) bash "$SCRIPT_DIR/menu6.sh" ;;
      7) bash "$SCRIPT_DIR/menu7.sh" ;;
      8) echo "Au revoir !" ; exit 0 ;;
      *) echo "Choix invalide !" ;;
    esac

    read -p "Appuyez sur Entrée pour revenir au menu..."
done
