#!/bin/bash
# banner_control.sh - Panneau de contrôle simple pour banner SSH très long

BANNER_FILE="/etc/custom_banner.txt"
PROFILE_SCRIPT="/etc/profile.d/custom_banner.sh"

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Ce script doit être lancé avec sudo ou en root.${RESET}"
    exit 1
  fi
}

show_banner() {
  clear
  if [[ -f "$BANNER_FILE" ]]; then
    echo -e "${CYAN}===== BANNER ACTUEL =====${RESET}"
    cat "$BANNER_FILE"
  else
    echo -e "${YELLOW}Aucun banner trouvé.${RESET}"
  fi
  read -p "Appuyez sur Entrée pour continuer..."
}

edit_banner() {
  clear
  echo -e "${YELLOW}Entrez votre banner très long. Terminez par une ligne vide.${RESET}"
  tmpfile=$(mktemp)
  while true; do
    read -r line
    [[ -z "$line" ]] && break
    echo "$line" >> "$tmpfile"
  done
  mv "$tmpfile" "$BANNER_FILE"
  chmod 644 "$BANNER_FILE"
  echo -e "${GREEN}Banner mis à jour.${RESET}"
  setup_profile_script
  restart_sshd
  read -p "Appuyez sur Entrée pour continuer..."
}

delete_banner() {
  clear
  if [[ -f "$BANNER_FILE" ]]; then
    rm -f "$BANNER_FILE"
    echo -e "${RED}Banner supprimé.${RESET}"
  else
    echo -e "${YELLOW}Aucun banner à supprimer.${RESET}"
  fi
  read -p "Appuyez sur Entrée pour continuer..."
}

setup_profile_script() {
  # Crée ou assure que le script d'affichage existe
  cat << 'EOF' > "$PROFILE_SCRIPT"
if [ -f /etc/custom_banner.txt ]; then
  cat /etc/custom_banner.txt
fi
EOF
  chmod +x "$PROFILE_SCRIPT"
}

restart_sshd() {
  systemctl restart sshd
  echo "Service SSH redémarré."
}

main_menu() {
  check_root
  while true; do
    clear
    echo -e "${CYAN}=== Panneau de contrôle Banner SSH VPS ===${RESET}"
    echo -e "${GREEN}1)${RESET} Afficher le banner"
    echo -e "${GREEN}2)${RESET} Créer / Modifier le banner"
    echo -e "${GREEN}3)${RESET} Supprimer le banner"
    echo -e "${RED}0)${RESET} Quitter"
    echo -ne "Choix : "
    read choix
    case $choix in
      1) show_banner ;;
      2) edit_banner ;;
      3) delete_banner ;;
      0) exit 0 ;;
      *) echo -e "${RED}Choix invalide.${RESET}"; sleep 1 ;;
    esac
  done
}

main_menu
