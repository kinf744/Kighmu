#!/bin/bash
# kighmu_banner_manager.sh - Gestion complète du banner personnalisé SSH

BANNER_DIR="$HOME/.kighmu"
BANNER_FILE="$BANNER_DIR/banner.txt"
SYSTEM_BANNER="/etc/ssh/banner.txt"

# Couleurs pour interface
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# Créer le dossier local si inexistant
mkdir -p "$BANNER_DIR"

# 🔍 Détection du bon service SSH
detect_ssh_service() {
    if systemctl list-units --type=service | grep -q "ssh.service"; then
        echo "ssh"
    elif systemctl list-units --type=service | grep -q "sshd.service"; then
        echo "sshd"
    else
        echo ""
    fi
}

show_banner() {
    clear
    if [ -f "$BANNER_FILE" ]; then
        echo -e "${CYAN}+--------------------------------------------------+${RESET}"
        while IFS= read -r line; do
            echo -e "$line"
        done < "$BANNER_FILE"
        echo -e "${CYAN}+--------------------------------------------------+${RESET}"
    else
        echo -e "${RED}Aucun banner personnalisé trouvé. Créez-en un dans ce menu.${RESET}"
    fi
    read -p "Appuyez sur Entrée pour continuer..."
}

create_banner() {
    mkdir -p "$BANNER_DIR"
    clear
    echo -e "${YELLOW}Entrez votre texte de banner. Terminez par une ligne vide :${RESET}"
    tmpfile=$(mktemp)
    while true; do
        read -r line
        [[ -z "$line" ]] && break
        echo "$line" >> "$tmpfile"
    done
    mv "$tmpfile" "$BANNER_FILE"
    echo -e "${GREEN}Banner sauvegardé localement : $BANNER_FILE${RESET}"

    # Copier la bannière dans le fichier système, avec permissions adaptées
    sudo cp "$BANNER_FILE" "$SYSTEM_BANNER"
    sudo chmod 644 "$SYSTEM_BANNER"
    echo -e "${GREEN}Banner copié dans $SYSTEM_BANNER avec permissions 644${RESET}"

    # Configuration du Banner dans sshd_config
    sshd_conf="/etc/ssh/sshd_config"
    if sudo grep -q "^Banner " "$sshd_conf"; then
        sudo sed -i "s|^Banner .*|Banner $SYSTEM_BANNER|" "$sshd_conf"
        echo -e "${GREEN}Configuration SSH mise à jour dans $sshd_conf${RESET}"
    else
        echo "Banner $SYSTEM_BANNER" | sudo tee -a "$sshd_conf" > /dev/null
        echo -e "${GREEN}Ligne Banner ajoutée à $sshd_conf${RESET}"
    fi

    # Redémarrage du service SSH (auto-détection)
    SSH_SERVICE=$(detect_ssh_service)
    if [ -n "$SSH_SERVICE" ]; then
        sudo systemctl restart "$SSH_SERVICE" && \
        echo -e "${GREEN}Service SSH (${SSH_SERVICE}.service) redémarré. Le banner sera affiché à la prochaine connexion.${RESET}" || \
        echo -e "${RED}Échec du redémarrage du service SSH.${RESET}"
    else
        echo -e "${RED}Impossible de détecter le service SSH. Veuillez vérifier l’installation d’OpenSSH.${RESET}"
    fi

    read -p "Appuyez sur Entrée pour continuer..."
}

delete_banner() {
    clear
    if [ -f "$BANNER_FILE" ]; then
        rm -f "$BANNER_FILE"
        echo -e "${RED}Banner local supprimé.${RESET}"
    else
        echo -e "${YELLOW}Aucun banner local à supprimer.${RESET}"
    fi

    # Supprimer fichier de banner système
    if [ -f "$SYSTEM_BANNER" ]; then
        sudo rm -f "$SYSTEM_BANNER"
        echo -e "${RED}Banner système supprimé.${RESET}"
    fi

    # Supprimer directive Banner dans sshd_config
    sshd_conf="/etc/ssh/sshd_config"
    if sudo grep -q "^Banner " "$sshd_conf"; then
        sudo sed -i "/^Banner /d" "$sshd_conf"
        echo -e "${GREEN}Directive Banner supprimée dans $sshd_conf${RESET}"
    fi

    # Redémarrage du service SSH (auto-détection)
    SSH_SERVICE=$(detect_ssh_service)
    if [ -n "$SSH_SERVICE" ]; then
        sudo systemctl restart "$SSH_SERVICE" && \
        echo -e "${GREEN}Service SSH (${SSH_SERVICE}.service) redémarré.${RESET}" || \
        echo -e "${RED}Échec du redémarrage du service SSH.${RESET}"
    else
        echo -e "${RED}Impossible de détecter le service SSH.${RESET}"
    fi

    read -p "Appuyez sur Entrée pour continuer..."
}

# === MENU PRINCIPAL ===
while true; do
    clear
    echo -e "${CYAN}+===================== Gestion Banner =====================+${RESET}"
    echo -e ""
    echo -e "${GREEN}${BOLD}[01]${RESET} ${YELLOW}Afficher le banner${RESET}"
    echo -e "${GREEN}${BOLD}[02]${RESET} ${YELLOW}Créer / Modifier le banner${RESET}"
    echo -e "${GREEN}${BOLD}[03]${RESET} ${YELLOW}Supprimer le banner${RESET}"
    echo -e "${RED}[00]${RESET} Quitter"
    echo -ne "${CYAN}Choix : ${RESET}"
    read -r choix
    case $choix in
        1|01) show_banner ;;
        2|02) create_banner ;;
        3|03) delete_banner ;;
        0|00) exit 0 ;;
        *) echo -e "${RED}Choix invalide, réessayez.${RESET}"; sleep 1 ;;
    esac
done
