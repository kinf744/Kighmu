#!/bin/bash
# kighmu_banner_manager.sh - Gestion complète du banner personnalisé SSH / Dropbear

BANNER_DIR="$HOME/.kighmu"
BANNER_FILE="$BANNER_DIR/banner.txt"
SYSTEM_BANNER="/etc/ssh/banner.txt"
DROPBEAR_BANNER="/etc/dropbear/banner.txt"
DROPBEAR_SERVICE="/etc/systemd/system/dropbear.service"

# Couleurs
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

mkdir -p "$BANNER_DIR"

# 🔍 Détection fiable du service SSH
detect_ssh_service() {
    if systemctl list-unit-files | grep -q "^ssh.service"; then
        echo "ssh"
    elif systemctl list-unit-files | grep -q "^sshd.service"; then
        echo "sshd"
    else
        echo ""
    fi
}

show_banner() {
    clear
    if [ -f "$BANNER_FILE" ]; then
        echo -e "${CYAN}+--------------------------------------------------+${RESET}"
        cat "$BANNER_FILE"
        echo -e "${CYAN}+--------------------------------------------------+${RESET}"
    else
        echo -e "${RED}Aucun banner personnalisé trouvé.${RESET}"
    fi
    read -p "Appuyez sur Entrée pour continuer..."
}

create_banner() {
    clear
    echo -e "${YELLOW}Entrez votre banner (ligne vide pour terminer) :${RESET}"

    tmpfile=$(mktemp)
    while true; do
        read -r line
        [ -z "$line" ] && break
        echo "$line" >> "$tmpfile"
    done

    mv "$tmpfile" "$BANNER_FILE"
    echo -e "${GREEN}Banner sauvegardé localement.${RESET}"

    # --- OpenSSH ---
    sudo mkdir -p /etc/ssh
    sudo cp "$BANNER_FILE" "$SYSTEM_BANNER"
    sudo chmod 644 "$SYSTEM_BANNER"
    sudo chown root:root "$SYSTEM_BANNER"

    sshd_conf="/etc/ssh/sshd_config"

    if sudo grep -q "^Banner " "$sshd_conf"; then
        sudo sed -i "s|^Banner .*|Banner $SYSTEM_BANNER|" "$sshd_conf"
    else
        echo "Banner $SYSTEM_BANNER" | sudo tee -a "$sshd_conf" >/dev/null
    fi

    echo -e "${GREEN}Banner configuré pour OpenSSH.${RESET}"

    # --- Dropbear ---
    sudo mkdir -p /etc/dropbear
    sudo cp "$BANNER_FILE" "$DROPBEAR_BANNER"
    sudo chmod 644 "$DROPBEAR_BANNER"
    sudo chown root:root "$DROPBEAR_BANNER"

    # 🔥 Correction PRO :
    # On ajoute -b (banner dropbear) seulement si absent
    if [ -f "$DROPBEAR_SERVICE" ]; then
        if ! grep -q "\-b /etc/dropbear/banner.txt" "$DROPBEAR_SERVICE"; then
            sudo sed -i 's|ExecStart=.*dropbear \(.*\)|ExecStart=/usr/sbin/dropbear \1 -b /etc/dropbear/banner.txt|' "$DROPBEAR_SERVICE"
        fi

        sudo systemctl daemon-reload
        sudo systemctl restart dropbear
        echo -e "${GREEN}Dropbear redémarré.${RESET}"
    fi

    # --- Restart SSH ---
    SSH_SERVICE=$(detect_ssh_service)
    if [ -n "$SSH_SERVICE" ]; then
        sudo systemctl restart "$SSH_SERVICE"
        echo -e "${GREEN}Service SSH redémarré.${RESET}"
    fi

    read -p "Appuyez sur Entrée..."
}

delete_banner() {
    clear

    [ -f "$BANNER_FILE" ] && rm -f "$BANNER_FILE"
    [ -f "$SYSTEM_BANNER" ] && sudo rm -f "$SYSTEM_BANNER"
    [ -f "$DROPBEAR_BANNER" ] && sudo rm -f "$DROPBEAR_BANNER"

    sshd_conf="/etc/ssh/sshd_config"
    if sudo grep -q "^Banner " "$sshd_conf"; then
        sudo sed -i "/^Banner /d" "$sshd_conf"
    fi

    # Nettoyage Dropbear (retire -b sans casser ExecStart)
    if [ -f "$DROPBEAR_SERVICE" ]; then
        sudo sed -i 's| -b /etc/dropbear/banner.txt||g' "$DROPBEAR_SERVICE"
        sudo systemctl daemon-reload
        sudo systemctl restart dropbear
    fi

    SSH_SERVICE=$(detect_ssh_service)
    [ -n "$SSH_SERVICE" ] && sudo systemctl restart "$SSH_SERVICE"

    echo -e "${GREEN}Banner supprimé.${RESET}"
    read -p "Appuyez sur Entrée..."
}

# === MENU ===
while true; do
    clear
    echo -e "${CYAN}+===================== Gestion Banner =====================+${RESET}"
    echo -e "${GREEN}${BOLD}[01]${RESET} ${YELLOW}Afficher le banner${RESET}"
    echo -e "${GREEN}${BOLD}[02]${RESET} ${YELLOW}Créer / Modifier le banner${RESET}"
    echo -e "${GREEN}${BOLD}[03]${RESET} ${YELLOW}Supprimer le banner${RESET}"
    echo -e "${RED}[00] Quitter${RESET}"
    echo -ne "${CYAN}Choix : ${RESET}"
    read -r choix

    case $choix in
        1|01) show_banner ;;
        2|02) create_banner ;;
        3|03) delete_banner ;;
        0|00) exit 0 ;;
        *) echo -e "${RED}Choix invalide${RESET}"; sleep 1 ;;
    esac
done
