#!/bin/bash
# ==============================================
# Kighmu VPS Manager
# Copyright (c) 2025 Kinf744
# Licence MIT (version française)
# Voir le fichier LICENSE pour plus de détails
# ==============================================

# Récupérer le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while true; do
    clear
    echo "+--------------------------------------------+"
    echo "|         K I G H M U   M A N A G E R        |"
    echo "+--------------------------------------------+"

    # Récupération de l'IP, RAM et CPU
    IP=$(hostname -I | awk '{print $1}')
    RAM_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }')
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{printf "%.2f%%", $2+$4}')

    # Compter utilisateurs normaux (UID >= 1000 et < 65534)
    USER_COUNT=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd | wc -l)

    # Compter connexions TCP établies au port 8080 (proxy SOCKS)
    CONNECTED_DEVICES=$(ss -tn state established '( sport = :8080 )' | tail -n +2 | wc -l)

    echo "IP: $IP | RAM utilisée: $RAM_USAGE | CPU utilisé: $CPU_USAGE"
    echo "Utilisateurs créés : $USER_COUNT | Appareils connectés : $CONNECTED_DEVICES"
    echo ""
    echo "MENU PRINCIPAL:"
    echo "1. Créer un utilisateur"
    echo "2. Créer un test utilisateur"
    echo "3. Voir les utilisateurs en ligne"
    echo "4. Supprimer utilisateur"
    echo "5. Installation de mode"
    echo "6. Désinstaller le script"
    echo "7. Blocage de torrents"
    echo "8. Quitter"

    read -p "Entrez votre choix [1-8]: " choix
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
