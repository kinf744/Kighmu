#!/bin/bash
set -euo pipefail

BANNER_DIR="$HOME/.kighmu"
BANNER_FILE="$BANNER_DIR/banner.txt"
SSHD_CONFIG="/etc/ssh/sshd_config"
ISSUE_NET="/etc/issue.net"
PROFILE_FILE="/etc/profile"

# --- Gestion du banner avec interface console ---
function menu_show_banner() {
  clear
  if [ -f "$BANNER_FILE" ]; then
    echo -e "\e[36m+--------------------------------------------------+\e[0m"
    while IFS= read -r line; do
      echo -e "$line"
    done < "$BANNER_FILE"
    echo -e "\e[36m+--------------------------------------------------+\e[0m"
  else
    echo -e "\e[31mAucun banner personnalisé trouvé. Créez-en un dans ce menu.\e[0m"
  fi
  read -rp "Appuyez sur Entrée pour continuer..."
}

function menu_create_banner() {
  clear
  echo -e "\e[33mEntrez votre texte de banner (supporte séquences ANSI). Terminez par une ligne vide :\e[0m"
  tmpfile=$(mktemp)
  while true; do
    read -r line
    [[ -z "$line" ]] && break
    echo "$line" >> "$tmpfile"
  done
  mv "$tmpfile" "$BANNER_FILE"
  echo -e "\e[32mBanner sauvegardé avec succès : $BANNER_FILE\e[0m"
  read -rp "Appuyez sur Entrée pour continuer..."
}

function menu_delete_banner() {
  clear
  if [ -f "$BANNER_FILE" ]; then
    rm -f "$BANNER_FILE"
    echo -e "\e[31mBanner supprimé avec succès.\e[0m"
  else
    echo -e "\e[33mAucun banner à supprimer.\e[0m"
  fi
  read -rp "Appuyez sur Entrée pour continuer..."
}

function menu_banner() {
  while true; do
    clear
    echo -e "\e[36m+===================== Gestion Banner =====================+\e[0m"
    echo -e "\e[32m\e[1m[01]\e[0m \e[33mAfficher le banner\e[0m"
    echo -e "\e[32m\e[1m[02]\e[0m \e[33mCréer / Modifier le banner\e[0m"
    echo -e "\e[32m\e[1m[03]\e[0m \e[33mSupprimer le banner\e[0m"
    echo -e "\e[31m[00]\e[0m Quitter"
    echo -ne "\e[36mChoix : \e[0m"
    read -r choix
    case $choix in
      1|01) menu_show_banner ;;
      2|02) menu_create_banner ;;
      3|03) menu_delete_banner ;;
      0|00) break ;;
      *) echo -e "\e[31mChoix invalide, réessayez.\e[0m"; sleep 1 ;;
    esac
  done
}

# --- Configuration système for banner display automatisé ---

function setup_system_banner() {
  echo "Configuration du banner SSH et affichage shell automatique..."

  if [ -f "$BANNER_FILE" ]; then
    sudo cp -f "$BANNER_FILE" "$ISSUE_NET"
    echo "Banner personnalisé copié dans $ISSUE_NET"
  else
    echo "Aucun banner personnalisé trouvé dans $BANNER_FILE, aucune copie vers $ISSUE_NET."
  fi

  if ! grep -q "^Banner $ISSUE_NET" "$SSHD_CONFIG"; then
    echo "Banner $ISSUE_NET" | sudo tee -a "$SSHD_CONFIG" > /dev/null
    echo "Directive Banner ajoutée dans $SSHD_CONFIG."
  else
    echo "Directive Banner déjà présente dans $SSHD_CONFIG."
  fi

  sudo systemctl restart sshd
  echo "Service sshd redémarré."

  BANNER_LOAD='if [ -f $HOME/.kighmu/banner.txt ]; then cat $HOME/.kighmu/banner.txt; fi'
  if ! grep -Fxq "$BANNER_LOAD" "$PROFILE_FILE"; then
    echo "" | sudo tee -a "$PROFILE_FILE" > /dev/null
    echo "# Affichage banner Kighmu" | sudo tee -a "$PROFILE_FILE" > /dev/null
    echo "$BANNER_LOAD" | sudo tee -a "$PROFILE_FILE" > /dev/null
    echo "Affichage banner ajouté dans $PROFILE_FILE."
  else
    echo "Affichage banner déjà présent dans $PROFILE_FILE."
  fi
}

# --- Lancement du menu pour gérer le banner ---
menu_banner

# --- Appliquer la configuration système pour actuelle banner ---
setup_system_banner

echo "Terminé. Votre banner s'affichera à chaque connexion SSH et session shell."
