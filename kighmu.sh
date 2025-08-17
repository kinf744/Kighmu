#!/bin/bash
# kighmu.sh
# Panneau de contrôle KIGHMU Manager

# Chemin des scripts de menu
MENU_DIR="$(dirname "$(realpath "$0")")"

# Fonction pour afficher IP, RAM et CPU
show_system_info() {
    IP=$(curl -s https://api.ipify.org)
    RAM_USED=$(free -m | awk '/Mem:/ {printf("%.0f%%"), $3/$2*100}')
    CPU_USED=$(top -bn1 | grep "Cpu(s)" | awk '{printf("%.0f%%", $2+$4)}')
    echo "IP: $IP | RAM: $RAM_USED | CPU: $CPU_USED"
}

while true; do
    clear
    echo "+--------------------------------------------+"
    echo "|            K I G H M U   M A N A G E R    |"
    echo "+--------------------------------------------+"
    
    # Afficher infos système
    show_system_info
    echo ""

    # Menu principal
    echo "MENU PRINCIPAL:"
    echo "1. Créer un utilisateur"
    echo "2. Créer un test utilisateur"
    echo "3. Voir les utilisateurs en ligne"
    echo "4. Supprimer utilisateur"
    echo "5. Installation de mode"
    echo "6. Désinstaller le script"
    echo "7. Blocage de torrents"
    echo "8. Quitter"
    echo ""

    read -p "Entrez votre choix [1-8]: " choice

    case $choice in
        1) bash "$MENU_DIR/menu1.sh" ;;
        2) bash "$MENU_DIR/menu2.sh" ;;
        3) bash "$MENU_DIR/menu3.sh" ;;
        4) bash "$MENU_DIR/menu4.sh" ;;
        5) bash "$MENU_DIR/menu5.sh" ;;
        6) bash "$MENU_DIR/menu6.sh"; exit 0 ;;
        7) bash "$MENU_DIR/menu7.sh" ;;
        8) echo "Au revoir !"; exit 0 ;;
        *) echo "Choix invalide."; sleep 2 ;;
    esac

    read -p "Appuyez sur Entrée pour revenir au menu principal..."
done
