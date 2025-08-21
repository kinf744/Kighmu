#!/bin/bash
# ==============================================
# Kighmu VPS Manager
# Copyright (c) 2025 Kinf744
# Licence MIT (version française)
# Voir le fichier LICENSE pour plus de détails
# ==============================================

# Récupérer le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fonction pour compter les utilisateurs (adapte le chemin selon ta gestion)
get_users_count() {
  ls /etc/xray/users/ 2>/dev/null | wc -l
}

# Fonction pour compter les appareils connectés (adapte selon ta méthode)
get_devices_count() {
  netstat -ntu | grep ESTABLISHED | wc -l
}

while true; do
    clear
    IP=$(hostname -I | awk '{print $1}')
    RAM_USAGE=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2 }')
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{printf "%.2f%%", $2+$4}')
    USERS_COUNT=$(get_users_count)
    DEVICES_COUNT=$(get_devices_count)

    echo "+============================================+"
    echo "|         K I G H M U   M A N A G E R        |"
    echo "+============================================+"
    printf "| IP: %-17s| RAM utilisée: %-7s |\n" "$IP" "$RAM_USAGE"
    printf "| CPU utilisé: %-38s|\n" "$CPU_USAGE"
    echo "+--------------------------------------------+"
    printf "| Utilisateurs créés: %-4d | Appareils: %-6d |\n" "$USERS_COUNT" "$DEVICES_COUNT"
    echo "+--------------------------------------------+"
    echo "|                MENU PRINCIPAL:             |"
    echo "+--------------------------------------------+"
    echo "| [01] Créer un utilisateur                  |"
    echo "| [02] Créer un test utilisateur             |"
    echo "| [03] Voir les utilisateurs en ligne        |"
    echo "| [05] Supprimer utilisateur                 |"
    echo "| [05] Installation de mode                  |"
    echo "| [06] Xray mode                             |"
    echo "| [07] Blocage de torrents.                  |"
    echo "| [08] Désinstaller le script                |"
    echo "| [09] Quitter                               |"
    echo "+--------------------------------------------+"
    read -p "| Entrez votre choix [1-8]: choix         |"
    case $choix in
    echo "+--------------------------------------------+"

      1) bash "$SCRIPT_DIR/menu1.sh" ;;
      2) bash "$SCRIPT_DIR/menu2.sh" ;;
      3) bash "$SCRIPT_DIR/menu3.sh" ;;
      4) bash "$SCRIPT_DIR/menu4.sh" ;;
      5) bash "$SCRIPT_DIR/menu5.sh" ;;
      6) bash "$SCRIPT_DIR/menu_6.sh" ;;
      7) bash "$SCRIPT_DIR/menu7.sh" ;;
      8) bash "$SCRIPT_DIR/menu8.sh" ;;
      9) echo "Au revoir !" ; exit 0 ;;
      *) echo "Choix invalide !" ;;
    esac

    read -p "Appuyez sur Entrée pour revenir au menu..."
done
