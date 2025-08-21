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

    echo "IP: $IP | RAM utilisée: $RAM_USAGE | CPU utilisé: $CPU_USAGE"
    echo ""
    echo "MENU PRINCIPAL:"
    echo "[01] Créer un utilisateur"
    echo "[02] Créer un test utilisateur"
    echo "[03] Voir les utilisateurs en ligne"
    echo "[04] Supprimer utilisateur"
    echo "[05] Installation de mode"
    echo "[06] Xray mode"
    echo "[07] Désinstaller le script"
    echo "[08] Blocage de torrents"
    echo "[09] Quitter"

    read -p "Entrez votre choix [1-8]: " choix
    case $choix in
      1) bash "$SCRIPT_DIR/menu1.sh" ;;
      2) bash "$SCRIPT_DIR/menu2.sh" ;;
      3) bash "$SCRIPT_DIR/menu3.sh" ;;
      4) bash "$SCRIPT_DIR/menu4.sh" ;;
      5) bash "$SCRIPT_DIR/menu5.sh" ;;
      6) bash "$SCRIPT_DIR/menu_6.sh" ;;
      7) bash "$SCRIPT_DIR/menu6.sh" ;;
      8) bash "$SCRIPT_DIR/menu7.sh" ;;
      9) echo "Au revoir !" ; exit 0 ;;
      *) echo "Choix invalide !" ;;
    esac

    read -p "Appuyez sur Entrée pour revenir au menu..."
done
