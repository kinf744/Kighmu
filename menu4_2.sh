#!/bin/bash
# kighmu_banner_manager.sh - Gestion complète du banner personnalisé SSH / Dropbear

BANNER_DIR="$HOME/.kighmu"
BANNER_FILE="$BANNER_DIR/banner.txt"
SYSTEM_BANNER="/etc/ssh/banner.txt"
DROPBEAR_BANNER="/etc/dropbear/banner.txt"

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

    # Copier la bannière dans OpenSSH
    sudo mkdir -p "$(dirname "$SYSTEM_BANNER")"
    sudo cp "$BANNER_FILE" "$SYSTEM_BANNER"
    sudo chmod 644 "$SYSTEM_BANNER"
    sudo chown root:root "$SYSTEM_BANNER"
    echo -e "${GREEN}Banner copié dans $SYSTEM_BANNER${RESET}"

    # Copier la bannière dans Dropbear (ASCII pur)
    sudo mkdir -p "$(dirname "$DROPBEAR_BANNER")"
    sudo cp "$BANNER_FILE" "$DROPBEAR_BANNER"
    sudo chmod 644 "$DROPBEAR_BANNER"
    sudo chown root:root "$DROPBEAR_BANNER"
    echo -e "${GREEN}Banner copié dans $DROPBEAR_BANNER${RESET}"

    # Configurer OpenSSH
    sshd_conf="/etc/ssh/sshd_config"
    if sudo grep -q "^Banner " "$sshd_conf"; then
        sudo sed -i "s|^Banner .*|Banner $SYSTEM_BANNER|" "$sshd_conf"
    else
        echo "Banner $SYSTEM_BANNER" | sudo tee -a "$sshd_conf" > /dev/null
    fi

    # Configurer Dropbear systemd (port par défaut 109)
    DROPBEAR_SERVICE="/etc/systemd/system/dropbear.service"
    if [ -f "$DROPBEAR_SERVICE" ]; then
        if ! grep -q "\-B" "$DROPBEAR_SERVICE"; then
            sudo sed -i "/ExecStart/ s|$| -B \"$DROPBEAR_BANNER\"|" "$DROPBEAR_SERVICE"
        fi
        sudo systemctl daemon-reload
        sudo systemctl restart dropbear
        echo -e "${GREEN}Dropbear redémarré avec la nouvelle bannière.${RESET}"
    fi

    # Redémarrage du service SSH
    SSH_SERVICE=$(detect_ssh_service)
    if [ -n "$SSH_SERVICE" ]; then
        sudo systemctl restart "$SSH_SERVICE" && \
        echo -e "${GREEN}Service SSH (${SSH_SERVICE}.service) redémarré.${RESET}" || \
        echo -e "${RED}Échec du redémarrage du service SSH.${RESET}"
    fi

    read -p "Appuyez sur Entrée pour continuer..."
}

delete_banner() {
    clear
    [ -f "$BANNER_FILE" ] && rm -f "$BANNER_FILE" && echo -e "${RED}Banner local supprimé.${RESET}"
    [ -f "$SYSTEM_BANNER" ] && sudo rm -f "$SYSTEM_BANNER" && echo -e "${RED}Banner OpenSSH supprimé.${RESET}"
    [ -f "$DROPBEAR_BANNER" ] && sudo rm -f "$DROPBEAR_BANNER" && echo -e "${RED}Banner Dropbear supprimé.${RESET}"

    # Supprimer directive Banner dans sshd_config
    sshd_conf="/etc/ssh/sshd_config"
    if sudo grep -q "^Banner " "$sshd_conf"; then
        sudo sed -i "/^Banner /d" "$sshd_conf"
        echo -e "${GREEN}Directive Banner supprimée dans $sshd_conf${RESET}"
    fi

    # Redémarrage des services
    SSH_SERVICE=$(detect_ssh_service)
    [ -n "$SSH_SERVICE" ] && sudo systemctl restart "$SSH_SERVICE"
    [ -f "/etc/systemd/system/dropbear.service" ] && sudo systemctl restart dropbear

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
