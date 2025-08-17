#!/bin/bash
# ==============================================
# Kighmu VPS Manager
# Copyright (c) 2025 Kinf744
# Licence MIT (version française)
# Voir le fichier LICENSE pour plus de détails
# ==============================================

# Exemple de contenu principal du script Kighmu
# Vous pouvez remplacer ceci par le code réel de votre panneau de contrôle

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
  1) bash menu1.sh ;;
  2) bash menu2.sh ;;
  3) bash menu3.sh ;;
  4) bash menu4.sh ;;
  5) bash menu5.sh ;;
  6) bash menu6.sh ;;
  7) bash menu7.sh ;;
  8) exit ;;
  *) echo "Choix invalide !" ;;
esac
