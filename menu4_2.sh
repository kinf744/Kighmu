#!/bin/bash
# banner_manager.sh - Gestion simple banner SSH global long sur VPS

BANNER_FILE="/etc/motd"

# Couleurs d'affichage
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Ce script doit être lancé en root ou avec sudo.${RESET}"
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
  read -p "Appuyez sur Entrée pour revenir au menu..."
}

create_banner() {
  clear
  echo -e "${YELLOW}Entrez le texte du banner. Finissez par une ligne vide :${RESET}"
  tmpfile=$(mktemp)
  while true; do
    read -r line
    [[ -z "$line" ]] && break
    echo "$line" >> "$tmpfile"
  done
  mv "$tmpfile" "$BANNER_FILE"
  chmod 644 "$BANNER_FILE"
  echo -e "${GREEN}Banner mis à jour dans $BANNER_FILE${RESET}"

  # Assurer que sshd affiche le MOTD
  if ! grep -q "^PrintMotd yes" /etc/ssh/sshd_config; then
    sed -i '/^PrintMotd/d' /etc/ssh/sshd_config
    echo "PrintMotd yes" >> /etc/ssh/sshd_config
  fi

  systemctl restart sshd
  echo -e "${GREEN}Service SSH redémarré.${RESET}"
  read -p "Appuyez sur Entrée pour retourner au menu..."
}

delete_banner() {
  clear
  if [[ -f "$BANNER_FILE" ]]; then
    rm -f "$BANNER_FILE"
    echo -e "${RED}Banner supprimé.${RESET}"
  else
    echo -e "${YELLOW}Aucun banner à supprimer.${RESET}"
  fi
  read -p "Appuyez sur Entrée pour retourner au menu..."
}

main_menu() {
  check_root
  while true; do
    clear
    echo -e "${CYAN}===== GESTION BANNER GLOBAL VPS =====${RESET}"
    echo -e "${GREEN}1)${RESET} Afficher le banner"
    echo -e "${GREEN}2)${RESET} Créer / Modifier le banner"
    echo -e "${GREEN}3)${RESET} Supprimer le banner"
    echo -e "${RED}0)${RESET} Quitter"
    echo -ne "Choix : "
    read choix
    case $choix in
      1) show_banner ;;
      2) create_banner ;;
      3) delete_banner ;;
      0) exit 0 ;;
      *) echo -e "${RED}Choix invalide.${RESET}"; sleep 1 ;;
    esac
  done
}

main_menu
