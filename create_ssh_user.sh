#!/bin/bash

# Script pour créer un utilisateur SSH avec configuration complète Kighmu

# Charger les infos globales Kighmu
if [ -f ~/.kighmu_info ]; then
    source ~/.kighmu_info
else
    echo "Erreur : fichier ~/.kighmu_info introuvable. Informations globales manquantes."
    exit 1
fi

read -p "Nom utilisateur à créer : " USERNAME

if id "$USERNAME" &>/dev/null; then
    echo "L'utilisateur $USERNAME existe déjà."
    exit 1
fi

# Création de l'utilisateur avec home et shell bash
useradd -m -s /bin/bash "$USERNAME"

# Demander et définir le mot de passe
echo "Définir le mot de passe pour $USERNAME :"
passwd "$USERNAME"

# Création du dossier .ssh avec droits stricts
mkdir -p /home/"$USERNAME"/.ssh
chmod 700 /home/"$USERNAME"/.ssh
chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"/.ssh

# Optionnel : ajouter une clé publique SSH (si fournie)
read -p "Si vous avez une clé publique SSH à ajouter, collez-la maintenant (ou appuyez sur Entrée pour passer) : " PUBKEY

if [ -n "$PUBKEY" ]; then
    echo "$PUBKEY" > /home/"$USERNAME"/.ssh/authorized_keys
    chmod 600 /home/"$USERNAME"/.ssh/authorized_keys
    chown "$USERNAME":"$USERNAME" /home/"$USERNAME"/.ssh/authorized_keys
    echo "Clé publique SSH ajoutée pour $USERNAME."
else
    echo "Aucune clé publique SSH ajoutée."
fi

# Ajout automatique de l'affichage du banner personnalisé au login shell
BANNER_PATH="$HOME/.kighmu/banner.txt"  # Adaptez ce chemin si nécessaire

echo "
# Affichage du banner Kighmu VPS Manager
if [ -f $BANNER_PATH ]; then
    cat $BANNER_PATH
fi
" >> /home/"$USERNAME"/.bashrc

chown "$USERNAME":"$USERNAME" /home/"$USERNAME"/.bashrc

echo
echo "+--------------------------------------------+"
echo "|        UTILISATEUR SSH CRÉÉ AVEC SUCCÈS   |"
echo "+--------------------------------------------+"
echo "Nom de domaine       : $DOMAIN"
echo "Serveur DNS (NS)     : $NS"
echo -e "Clé publique SlowDNS :\n$PUBLIC_KEY"
echo "+--------------------------------------------+"

echo "Utilisateur $USERNAME créé et configuré avec succès."
