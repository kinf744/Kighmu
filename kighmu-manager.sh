#!/bin/bash
# kighmu-manager.sh
# Panneau principal KIGHMU MANAGER

# Charger la configuration globale si elle existe
if [ -f ./config.sh ]; then
    source ./config.sh
fi

# Fonction pour afficher IP, RAM, CPU et info utilisateurs/appareils dans un cadre simple
display_system_info() {
    IP=$(curl -s https://api.ipify.org)
    RAM_USAGE=$(free -m | awk 'NR==2{printf "%.2f", $3*100/$2 }')
    CPU_USAGE=$(mpstat 1 1 | awk '/Average/ {printf "%.2f", 100-$12}')

    USER_COUNT=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd | wc -l)
    CONNECTED_DEVICES=$(ss -tn state established '( sport = :8080 )' | tail -n +2 | wc -l)

    echo "+--------------------------------------------+"
    echo "|           K I G H M U   M A N A G E R      |"
    echo "+--------------------------------------------+"
    echo "IP: $IP | RAM: ${RAM_USAGE}% | CPU: ${CPU_USAGE}%"
    echo "Utilisateurs créés : $USER_COUNT | Appareils connectés : $CONNECTED_DEVICES"
    echo ""
}

# Fonction menu principal
main_menu() {
    while true; do
        clear
        display_system_info
        echo "MENU PRINCIPAL:"
        echo "1. Créer un utilisateur"
        echo "2. Créer un test utilisateur"
        echo "3. Voir les utilisateurs en ligne"
        echo "4. Supprimer utilisateur"
        echo "5. Installation de modes spéciaux"
        echo "6. Désinstaller le script"
        echo "7. Blocage de torrents"
        echo "8. Quitter"
        echo ""
        read -p "Entrez votre choix [1-8]: " choice

        case $choice in
            1) bash ./menu1.sh ;;
            2) bash ./menu2.sh ;;
            3) bash ./menu3.sh ;;
            4) bash ./menu4.sh ;;
            5) bash ./menu5.sh ;;      # Modification ici : appel menu5.sh au lieu de install_modes.sh
            6) bash ./menu6.sh ;;
            7) bash ./menu7.sh ;;
            8) echo "Au revoir !"; exit 0 ;;
            *) echo "Choix invalide. Réessayez." ;;
        esac

        echo ""
        read -p "Appuyez sur Entrée pour revenir au menu principal..."
    done
}

# Lancer le menu principal
main_menu
