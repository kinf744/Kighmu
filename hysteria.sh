#!/usr/bin/env bash
# hysteria.sh - Hysteria Server (Kighmu)
# Installation et configuration complète avec certificat auto-signé et systemd
# Version corrigée

set -euo pipefail

HYST_BIN="/usr/local/bin/hysteria"
HYST_CONFIG_DIR="/etc/hysteria"
SYSTEMD_UNIT_PATH="/etc/systemd/system/hysteria.service"
USER_FILE="/etc/kighmu/users.list"
HYST_PORT=22000
CERT_FILE="$HYST_CONFIG_DIR/server.crt"
KEY_FILE="$HYST_CONFIG_DIR/server.key"
GREEN="\e[1;32m"
RESET="\e[0m"

log() { echo "==> $*"; }
err() { echo "ERREUR: $*" >&2; exit 1; }

require_root() {
    if [ "$EUID" -ne 0 ]; then
        err "Ce script doit être exécuté en root."
    fi
}

install_prereqs() {
    log "Vérification et installation des paquets prérequis..."
    PKGS=(curl unzip ca-certificates socat jq openssl)
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
    log "Binaire Hysteria installé avec succès."
}

generate_self_signed_cert() {
    mkdir -p "$HYST_CONFIG_DIR"
    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        log "Génération certificat TLS auto-signé..."
        openssl req -newkey rsa:2048 -nodes -keyout "$KEY_FILE" -x509 -days 3650 -out "$CERT_FILE" \
            -subj "/C=FR/ST=State/L=City/O=Org/OU=IT/CN=$(hostname -f)"
        chmod 600 "$CERT_FILE" "$KEY_FILE"
    fi
    chown -R root:root "$HYST_CONFIG_DIR"
    chmod 700 "$HYST_CONFIG_DIR"
    chmod 600 "$HYST_CONFIG_DIR"/*.key "$HYST_CONFIG_DIR"/*.crt
}

write_server_config() {
    log "Écriture de la config Hysteria..."
    local first_password
    first_password=$(awk -F'|' 'NR==1 {print $2}' "$USER_FILE")
    cat > "$HYST_CONFIG_DIR/config.yaml" <<EOF
listen: :${HYST_PORT}

tls:
  cert: $CERT_FILE
  key: $KEY_FILE

auth:
  type: password
  password: "${first_password}"

masquerade:
  type: direct

socks5:
  listen: 127.0.0.1:1080
  disableUDP: false

udpIdleTimeout: 60s
disableUDP: false
EOF
    chmod 600 "$HYST_CONFIG_DIR/config.yaml"
    chown root:root "$HYST_CONFIG_DIR/config.yaml"
}

cleanup_port() {
    log "Nettoyage du port UDP $HYST_PORT et processus Hysteria existants..."
    local PIDS
    PIDS=$(pgrep -f hysteria || true)
    if [ -n "$PIDS" ]; then
        log "Arrêt des processus Hysteria existants (PID: $PIDS)..."
        kill -15 $PIDS
        sleep 2
        PIDS=$(pgrep -f hysteria || true)
        if [ -n "$PIDS" ]; then
            kill -9 $PIDS
        fi
    fi

    if systemctl list-units --full -all | grep -Fq 'hysteria.service'; then
        log "Arrêt et désactivation du service systemd hysteria..."
        systemctl stop hysteria.service || true
        systemctl disable hysteria.service || true
        rm -f "$SYSTEMD_UNIT_PATH"
        systemctl daemon-reload
    fi

    iptables -D INPUT -p udp --dport $HYST_PORT -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -p udp --sport $HYST_PORT -j ACCEPT 2>/dev/null || true
}

deploy_systemd_unit() {
    log "Création du service systemd hysteria..."
    cat > "$SYSTEMD_UNIT_PATH" <<EOF
[Unit]
Description=Hysteria Server (Kighmu)
After=network.target

[Service]
Type=simple
WorkingDirectory=${HYST_CONFIG_DIR}
ExecStart=${HYST_BIN} server -c ${HYST_CONFIG_DIR}/config.yaml
Restart=always
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now hysteria.service
}

open_port() {
    log "Ouverture du port UDP $HYST_PORT via iptables..."
    iptables -C INPUT -p udp --dport $HYST_PORT -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport $HYST_PORT -j ACCEPT
    iptables -C OUTPUT -p udp --sport $HYST_PORT -j ACCEPT 2>/dev/null || iptables -I OUTPUT -p udp --sport $HYST_PORT -j ACCEPT
}

main() {
    require_root
    install_prereqs
    install_hysteria_binary
    generate_self_signed_cert
    cleanup_port
    write_server_config
    deploy_systemd_unit
    open_port

    log "Hysteria prêt, port UDP $HYST_PORT, utilisateurs issus de $USER_FILE."
    echo -e "${GREEN}[OK] Installation Hysteria terminée.${RESET}"
}

main "$@"
