#!/bin/bash
set -euo pipefail

# Config et variables centrales
CONFIG_FILE="/etc/xray/config.json"
USERS_FILE="/etc/xray/users.json"
DOMAIN="${DOMAIN:-}"
DOMAIN_TEMP_FILE="/tmp/.xray_domain"
LOG_PANEL="/var/log/xray_panel.log"

# Codes couleur
RED='e[0;31m'
GREEN='e[0;32m'
YELLOW='e[0;33m'
MAGENTA='e[35m'
CYAN='e[36m'
BOLD='e[1m'
RESET='e[0m'

log() {
  local msg="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') | ${msg}" | tee -a "$LOG_PANEL"
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Ce script doit être exécuté en root.${RESET}" >&2
    exit 1
  fi
}
require_root

# Chargement du domaine si disponible
load_domain() {
  if [[ -f "$DOMAIN_TEMP_FILE" ]]; then
    DOMAIN=$(cat "$DOMAIN_TEMP_FILE")
  fi
  if [[ -z "$DOMAIN" ]]; then
    log "Avertissement: Domaine non enregistré. Le panneau peut s’ouvrir mais les liens seront générés uniquement après installation."
  fi
}
load_domain

# Validation basique des prérequis
validate_env() {
  if [[ -z "$DOMAIN" ]]; then
    log "ATTENTION: Domaine non défini. L’installation devra enregistrer le domaine."
  fi
  if [[ ! -f "$CONFIG_FILE" ]]; then
    log "ERREUR: Fichier de config manquant: $CONFIG_FILE"
  fi
  if [[ ! -f "/etc/xray/xray.crt" || ! -f "/etc/xray/xray.key" ]]; then
    log "ERREUR: Certificats TLS manquants."
  fi
}

# Chargement des données utilisateur existantes
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

# Ecriture atomique
write_json_atomic() {
  local file="$1"
  local content="$2"
  local tmp="${file}.tmp"
  printf "%s" "$content" > "$tmp"
  mv -f "$tmp" "$file"
}

# Add_user : intégration directe dans le même fichier
add_user() {
  local proto="$1"
  local name="$2"
  local days="$3"

  if [[ -z "$DOMAIN" ]]; then
    log "ERREUR: Domaine non défini. Impossible d’ajouter un utilisateur sans domaine."
    return 1
  fi

  local new_uuid path_ws port_tls=8443 port_ntls=80 port_trojan=2083
  local link_tls link_ntls

  case "$proto" in
    vmess)
      path_ws="/vmess-tls"
      new_uuid=$(uuidgen)
      # Vérifie présence inbound TLS VMESS puis add client
      if ! jq -e '.inbounds[] | select(.protocol=="vmess" and .streamSettings.network=="ws" and .streamSettings.security=="tls")' "$CONFIG_FILE" >/dev/null; then
        log "ERREUR: inbound VMESS TLS manquant dans $CONFIG_FILE"
        return 1
      fi
      jq --arg id "$new_uuid" \
        '.inbounds[] | select(.protocol=="vmess" and .streamSettings.network=="ws" and .streamSettings.security=="tls") .settings.clients += [{"id":$id,"alterId":0}]' \
        "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

      if [[ -f "$USERS_FILE" ]]; then
        jq --arg id "$new_uuid" '.vmess_tls=$id' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
      else
        printf '{"vmess_tls":"%s"}' "$new_uuid" > "$USERS_FILE" || true
      fi

      link_tls="vmess://$(echo -n '{"v":"2","ps":"'"$name"'","add":"'"$DOMAIN"'","port":"'$port_tls'","id":"'$new_uuid'","aid":0,"net":"ws","type":"none","host":"'"$DOMAIN"'","path":"'"$path_ws"'","tls":"tls"}' | base64 -w0)"
      link_ntls="vmess://$(echo -n '{"v":"2","ps":"'"$name"'","add":"'"$DOMAIN"'","port":"'$port_ntls'","id":"'$new_uuid'","aid":0,"net":"ws","type":"none","host":"'"$DOMAIN"'","path":"'$path_ws'","tls":""}' | base64 -w0)"
      ;;

    vless)
      path_ws="/vless-tls"
      new_uuid=$(uuidgen)
      if ! jq -e '.inbounds[] | select(.protocol=="vless" and .streamSettings.network=="ws" and .streamSettings.security=="tls")' "$CONFIG_FILE" >/dev/null; then
        log "ERREUR: inbound VLESS TLS manquant dans $CONFIG_FILE"
        return 1
      fi
      jq --arg id "$new_uuid" \
        '.inbounds[] | select(.protocol=="vless" and .streamSettings.network=="ws" and .streamSettings.security=="tls") .settings.clients += [{"id":$id}]' \
        "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

      if [[ -f "$USERS_FILE" ]]; then
        jq --arg id "$new_uuid" '.vless_tls=$id' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
      else
        printf '{"vless_tls":"%s"}' "$new_uuid" > "$USERS_FILE" || true
      fi

      link_tls="vless://$new_uuid@$DOMAIN:$port_tls?path=$path_ws&security=tls&encryption=none&type=ws#$name"
      link_ntls="vless://$new_uuid@$DOMAIN:$port_ntls?path=$path_ws&encryption=none&type=ws#$name"
      ;;

    trojan)
      local tls_pass=$(uuidgen)
      local ntls_pass=$(uuidgen)
      if ! jq -e '.inbounds[] | select(.protocol=="trojan" and .streamSettings.network=="tcp" and .streamSettings.security=="tls")' "$CONFIG_FILE" >/dev/null; then
        log "ERREUR: inbound Trojan TLS manquant dans $CONFIG_FILE"
        return 1
      fi
      jq --arg idtls "$tls_pass" --arg idntl "$ntls_pass" \
        '.trojan_pass=$idtls | .trojan_ntls_pass=$idntl' "$USERS_FILE" > /tmp/users.tmp && mv /tmp/users.tmp "$USERS_FILE"
      link_tls="trojan://$tls_pass@$DOMAIN:$port_trojan?security=tls&type=ws&path=/trojanws#$name"
      link_ntls="trojan://$ntls_pass@$DOMAIN:89?type=ws&path=/trojanws#$name"
      ;;
    *)
      log "ERREUR: Protocole inconnu pour l’ajout."
      return 1
      ;;
  esac

  log "Nouveau tunnel ajout&eacute;: $proto pour $name"
  log "TLS  : $link_tls"
  log "NTLS : $link_ntls"

  # Redémarrage Xray et vérification
  systemctl restart xray
  if systemctl is-active --quiet xray; then
    log "Xray démarré avec succès après ajout."
  else
    log "ERREUR: échec du redémarrage Xray après ajout."
  fi
  # Afficher liens utiles
  echo "Lien TLS  : $link_tls"
  echo "Lien NTLS : $link_ntls"
}

# Ajout d’un utilisateur (wrapper pour VMESS/VLESS/TROJAN)
add_user_wrapper() {
  local proto="$1"
  local name="$2"
  local days="$3"
  add_user "$proto" "$name" "$days"
}

# Affichage des tunnels actifs
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

load_and_run() {
  # Chargement initial et affichage
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
        [[ -f "$DOMAIN_TEMP_FILE" ]] && DOMAIN=$(cat "$DOMAIN_TEMP_FILE")
        load_users
        read -p "Appuyez sur Entrée pour continuer..."
        ;;
      2)
        read -rp "Nom de l'utilisateur VMESS : " conf_name
        read -rp "Durée ( jours ) : " days
        add_user vmess "$conf_name" "$days"
        read -p "Appuyez sur Entrée pour continuer..."
        ;;
      3)
        read -rp "Nom de l'utilisateur VLESS : " conf_name
        read -rp "Durée ( jours ) : " days
        add_user vless "$conf_name" "$days"
        read -p "Appuyez sur Entrée pour continuer..."
        ;;
      4)
        read -rp "Nom de l'utilisateur TROJAN : " conf_name
        read -rp "Durée ( jours ) : " days
        add_user trojan "$conf_name" "$days"
        read -p "Appuyez sur Entrée pour continuer..."
        ;;
      5)
        read -rp "Nom utilisateur à supprimer: " name
        # Suppression fonctionnelle si présente (à adapter)
        log "Suppression non implémentée dans cette version"
        read -p "Appuyez sur Entrée pour continuer..."
        ;;
      6)
        echo -e "${YELLOW}Désinstallation complète de Xray et Trojan-Go en cours...${RESET}"
        systemctl stop xray trojan-go 2>/dev/null || true
        systemctl disable xray trojan-go 2>/dev/null || true
        for port in 89 8443; do
          if command -v lsof >/dev/null 2>&1; then
            lsof -i tcp:$port -t | xargs -r kill -9
          fi
        done
        rm -rf /etc/xray /var/log/xray /usr/local/bin/xray /etc/systemd/system/xray.service
        rm -rf /etc/trojan-go /var/log/trojan-go /usr/local/bin/trojan-go /etc/systemd/system/trojan-go.service
        rm -f /tmp/.xray_domain /tmp/.xray_domain.lock /etc/xray/users_expiry.list /etc/xray/users.json /etc/xray/config.json
        systemctl daemon-reload
        echo -e "${GREEN}Désinstallation terminée.${RESET}"
        read -p "Appuyez sur Entrée pour continuer..."
        ;;
      0)
        echo -e "${RED}Quitter...${RESET}"
        # rm -f "$DOMAIN_TEMP_FILE"
        break
        ;;
      *)
        echo -e "${RED}Choix invalide.${RESET}"
        sleep 2
        ;;
    esac
  done
}

# Point d’entrée
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN_TEMP_FILE="${DOMAIN_TEMP_FILE:-/tmp/.xray_domain}"
load_and_run
