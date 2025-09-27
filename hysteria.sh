#!/usr/bin/env bash
# hysteria.sh
# Intégration Kighmu : Hysteria Server utilisant les utilisateurs créés via menu1.sh
set -euo pipefail

HYST_BIN="/usr/local/bin/hysteria"
HYST_CONFIG_DIR="/etc/hysteria"
SYSTEMD_UNIT_PATH="/etc/systemd/system/hysteria.service"
USER_FILE="/etc/kighmu/users.list"
HYST_PORT=22000
CERT_FILE="$HYST_CONFIG_DIR/server.crt"
KEY_FILE="$HYST_CONFIG_DIR/server.key"

log() { echo "==> $*"; }
err() { echo "ERREUR: $*" >&2; exit 1; }

require_root() {
  if [ "$EUID" -ne 0 ]; then
    err "Ce script doit être exécuté en root (sudo)."
  fi
}

install_prereqs() {
  log "Vérification et installation des paquets prérequis..."
  PKGS=(curl unzip ca-certificates socat jq ufw openssl)
  for pkg in "${PKGS[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      log "Installation du paquet manquant: $pkg"
      apt-get update -y
      apt-get install -y "$pkg"
    fi
  done
}

install_hysteria_binary() {
  if [ -x "$HYST_BIN" ]; then
    log "Binaire Hysteria déjà présent: $HYST_BIN"
    return
  fi
  log "Téléchargement / installation du binaire Hysteria..."
  bash <(curl -fsSL https://get.hy2.sh)
  [ -x "$HYST_BIN" ] || err "Binaire hysteria introuvable après installation."
  log "Installation du binaire Hysteria réussie."
}

generate_self_signed_cert() {
  mkdir -p "$HYST_CONFIG_DIR"
  if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    log "Génération d'un certificat TLS auto-signé..."
    openssl req -newkey rsa:2048 -nodes -keyout "$KEY_FILE" -x509 -days 3650 -out "$CERT_FILE" -subj "/C=FR/ST=State/L=City/O=Org/OU=IT/CN=$(hostname -f)"
    chmod 600 "$CERT_FILE" "$KEY_FILE"
    log "Certificat et clé générés dans $HYST_CONFIG_DIR."
  else
    log "Certificat TLS et clé déjà présents."
  fi
}

write_server_config() {
  log "Écriture de la config Hysteria dans $HYST_CONFIG_DIR/config.yaml"

  local first_password
  first_password=$(awk -F'|' 'NR==1 {print $2}' "$USER_FILE")

  # Utilisation de la variable DOMAIN exportée lors de l'installation
  local proxy_url="https://${DOMAIN:-example.com}"

  cat > "$HYST_CONFIG_DIR/config.yaml" <<EOF
listen: :${HYST_PORT}

tls:
  cert: $CERT_FILE
  key: $KEY_FILE

auth:
  type: password
  password: "${first_password}"

masquerade:
  type: proxy
  proxy:
    url: "$proxy_url"
    rewriteHost: true
    insecure: false

socks5:
  listen: 127.0.0.1:1080
  disableUDP: false

udpIdleTimeout: 60s
disableUDP: false
EOF

  chmod 600 "$HYST_CONFIG_DIR/config.yaml"
  chown root:root "$HYST_CONFIG_DIR/config.yaml"
  log "Configuration Hysteria écrite avec succès."
}

deploy_systemd_unit() {
  if command -v systemctl >/dev/null 2>&1; then
    log "Création ou mise à jour du service systemd hysteria..."
    cat > "$SYSTEMD_UNIT_PATH" <<EOF
[Unit]
Description=Hysteria Server (Kighmu)
After=network.target

[Service]
Type=simple
ExecStart=${HYST_BIN} server -c ${HYST_CONFIG_DIR}/config.yaml
Restart=always
RestartSec=5s
StartLimitBurst=0
StartLimitIntervalSec=0
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now hysteria.service
    log "Service hysteria activé et démarré."
  fi
}

open_firewall_udp() {
  log "Ouverture du port UDP $HYST_PORT via UFW..."
  if command -v ufw >/dev/null 2>&1; then
    ufw allow "${HYST_PORT}/udp" || true
    ufw reload || true
  fi
}

main() {
  require_root
  install_prereqs
  install_hysteria_binary
  generate_self_signed_cert
  write_server_config
  deploy_systemd_unit
  open_firewall_udp
  log "Hysteria (Kighmu) prêt, port $HYST_PORT, utilisateurs issus de $USER_FILE."

  echo "+--------------------------------------------+"
  echo "|             CONFIG HYSTERIA               |"
  echo "+--------------------------------------------+"

  echo "Installation terminée avec succès."
  echo "Pour vérifier les logs: sudo journalctl -u hysteria -f"
}

main "$@"
