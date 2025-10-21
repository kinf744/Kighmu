#!/bin/bash
set -euo pipefail

# Chemins et variables
CONFIG_FILE="/etc/xray/config.json"
USERS_FILE="/etc/xray/users.json"
DOMAIN="${DOMAIN:-}"
DOMAIN_FILE="${DOMAIN_FILE:-/tmp/.xray_domain}"
LOG_PANEL="/var/log/xray_panel.log"

# Couleurs
RED='\u001B[0;31m'
GREEN='\u001B[0;32m'
YELLOW='\u001B[0;33m'
MAGENTA='\u001B[35m'
CYAN='\u001B[36m'
BOLD='\u001B[1m'
RESET='\u001B[0m'

log() {
  local msg="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') | ${msg}" | tee -a "$LOG_PANEL"
}

# Vérifications
require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Ce script doit être exécuté en root.${RESET}" >&2
    exit 1
  fi
}
require_root

# Charge DOMAIN depuis fichier temporaire si disponible
load_domain() {
  if [[ -f "$DOMAIN_FILE" ]]; then
    DOMAIN=$(cat "$DOMAIN_FILE")
  fi
  if [[ -z "$DOMAIN" ]]; then
    log "Avertissement: Domaine non enregistré pour l’installation. Le panneau s’ouvre néanmoins."
  fi
}

validate_env() {
  if [[ -z "$DOMAIN" ]]; then
    log "ATTENTION: Domaine non fourni. L’installation doit fournir DOMAIN avant la configuration finale."
  fi
  if [[ ! -f "$CONFIG_FILE" ]]; then
    log "ERREUR: Fichier de config manquant: $CONFIG_FILE"
  fi
  if [[ ! -f "/etc/xray/xray.crt" || ! -f "/etc/xray/xray.key" ]]; then
    log "ERREUR: Certificats TLS manquants."
  fi
}

load_users() {
  if [[ -f "$USERS_FILE" ]]; then
    VMESS_TLS=$(jq -r '.vmess_tls // empty' "$USERS_FILE")
    VMESS_NTLS=$(jq -r '.vmess_ntls // empty' "$USERS_FILE")
    VLESS_TLS=$(jq -r '.vless_tls // empty' "$USERS_FILE")
    VLESS_NTLS=$(jq -r '.vless_ntls // empty' "$USERS_FILE")
    TROJAN_PASS=$(jq -r '.trojan_pass // empty' "$USERS_FILE")
    TROJAN_NTLS_PASS=$(jq -r '.trojan_ntls_pass // empty' "$USERS_FILE")
  else
    VMESS_TLS=""
    VMESS_NTLS=""
    VLESS_TLS=""
    VLESS_NTLS=""
    TROJAN_PASS=""
    TROJAN_NTLS_PASS=""
  fi
}

print_header() {
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${CYAN}       ${BOLD}${MAGENTA}Xray – Gestion des Tunnels Actifs${RESET}${CYAN}${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

afficher_xray_actifs() {
  if ! systemctl is-active --quiet xray; then
    echo -e "${RED}Service Xray non actif.${RESET}"
    return
  fi
  local ports_tls ports_ntls protos
  ports_tls=$(jq -r '.inbounds[] | select(.streamSettings.security=="tls") | .port' "$CONFIG_FILE" | sort -u | paste -sd ", ")
  ports_ntls=$(jq -r '.inbounds[] | select(.streamSettings.security=="none") | .port' "$CONFIG_FILE" | sort -u | paste -sd ", ")
  protos=$(jq -r '.inbounds[].protocol' "$CONFIG_FILE" | sort -u | paste -sd ", ")
  echo -e "${BOLD}Tunnels actifs :${RESET}"
  [[ -n "$ports_tls" ]] && echo -e " ${GREEN}•${RESET} Port(s) TLS : ${YELLOW}$ports_tls${RESET} – Protocoles [${MAGENTA}$protos${RESET}]"
  [[ -n "$ports_ntls" ]] && echo -e " ${GREEN}•${RESET} Port(s) Non-TLS : ${YELLOW}$ports_ntls${RESET} – Protocoles [${MAGENTA}$protos${RESET}]"
}

show_menu() {
  echo -e "${CYAN}──────────────────────────────────────────────────────────${RESET}"
  echo -e "${BOLD}${YELLOW}[01]${RESET} Installer Xray"
  echo -e "${BOLD}${YELLOW}[02]${RESET} Créer utilisateur VMess"
  echo -e "${BOLD}${YELLOW}[03]${RESET} Créer utilisateur VLESS"
  echo -e "${BOLD}${YELLOW}[04]${RESET} Créer utilisateur Trojan"
  echo -e "${BOLD}${YELLOW}[05]${RESET} Supprimer utilisateur Xray"
  echo -e "${BOLD}${YELLOW}[06]${RESET} Désinstallation complète Xray"
  echo -e "${BOLD}${RED}[00]${RESET} Quitter"
  echo -e "${CYAN}──────────────────────────────────────────────────────────${RESET}"
  echo -ne "${BOLD}${YELLOW}Choix → ${RESET}"
  read -r choice
}

load_user_data() {
  if [[ -f "$USERS_FILE" ]]; then
    VMESS_TLS=$(jq -r '.vmess_tls // empty' "$USERS_FILE")
    VMESS_NTLS=$(jq -r '.vmess_ntls // empty' "$USERS_FILE")
    VLESS_TLS=$(jq -r '.vless_tls // empty' "$USERS_FILE")
    VLESS_NTLS=$(jq -r '.vless_ntls // empty' "$USERS_FILE")
    TROJAN_PASS=$(jq -r '.trojan_pass // empty' "$USERS_FILE")
    TROJAN_NTLS_PASS=$(jq -r '.trojan_ntls_pass // empty' "$USERS_FILE")
  fi
}

# Initialisation
choice=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f /tmp/.xray_domain ]] && DOMAIN=$(cat /tmp/.xray_domain)
load_domain
validate_env
load_users

while true; do
  clear
  print_header
  afficher_xray_actifs
  show_menu
  case $choice in
    1)
      bash "$SCRIPT_DIR/xray_installe.sh"
      [[ -f /tmp/.xray_domain ]] && DOMAIN=$(cat /tmp/.xray_domain)
      load_users
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    2)
      read -rp "Nom de l'utilisateur VMESS : " conf_name
      read -rp "Durée ( jours ) : " days
      [[ -n "$conf_name" && -n "$days" ]] && add_user vmess "$conf_name" "$days"
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    3)
      read -rp "Nom de l'utilisateur VLESS : " conf_name
      read -rp "Durée ( jours ) : " days
      [[ -n "$conf_name" && -n "$days" ]] && add_user vless "$conf_name" "$days"
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    4)
      read -rp "Nom de l'utilisateur TROJAN : " conf_name
      read -rp "Durée ( jours ) : " days
      [[ -n "$conf_name" && -n "$days" ]] && add_user trojan "$conf_name" "$days"
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    5)
      read -rp "Nom utilisateur à supprimer: " name
      remove_user "$name"
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    6)
      echo -e "${YELLOW}Désinstallation complète de Xray et Trojan-Go en cours...${RESET}"
      systemctl stop xray trojan-go 2>/dev/null || true
      systemctl disable xray trojan-go 2>/dev/null || true
      for port in 89 8443; do lsof -i tcp:$port -t | xargs -r kill -9; done
      rm -rf /etc/xray /var/log/xray /usr/local/bin/xray /etc/systemd/system/xray.service
      rm -rf /etc/trojan-go /var/log/trojan-go /usr/local/bin/trojan-go /etc/systemd/system/trojan-go.service
      rm -f /tmp/.xray_domain /tmp/.xray_domain.lock /etc/xray/users_expiry.list /etc/xray/users.json /etc/xray/config.json
      systemctl daemon-reload
      echo -e "${GREEN}Désinstallation terminée.${RESET}"
      read -p "Appuyez sur Entrée pour continuer..."
      ;;
    0)
      echo -e "${RED}Quitter...${RESET}"
      rm -f /tmp/.xray_domain
      break
      ;;
    *)
      echo -e "${RED}Choix invalide.${RESET}"
      sleep 2
      ;;
  esac
done
