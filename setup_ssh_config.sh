#!/bin/bash

# Créer le dossier .ssh si nécessaire
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Ajouter clé publique dans authorized_keys (remplacer la clé)
PUBKEY="ssh-rsa AAAA..."

grep -qxF "$PUBKEY" /root/.ssh/authorized_keys 2>/dev/null || echo "$PUBKEY" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Modifier sshd_config pour autoriser tunneling
SSHD_CONF="/etc/ssh/sshd_config"

grep -q "^PermitTunnel yes" $SSHD_CONF || echo "PermitTunnel yes" >> $SSHD_CONF
grep -q "^AllowTcpForwarding yes" $SSHD_CONF || echo "AllowTcpForwarding yes" >> $SSHD_CONF

# Redémarrer le service SSH
systemctl restart ssh
