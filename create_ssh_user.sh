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

USER_HOME=$(eval echo "~$USERNAME")

# Création de l'utilisateur avec home et shell bash
useradd -m -s /bin/bash "$USERNAME"

# Demander et définir le mot de passe
echo "Définir le mot de passe pour $USERNAME :"
passwd "$USERNAME"

# Création des dossiers nécessaires avec droits
mkdir -p "$USER_HOME/.ssh" "$USER_HOME/.kighmu"
chmod 700 "$USER_HOME/.ssh"
chown -R "$USERNAME":"$USERNAME" "$USER_HOME/.ssh" "$USER_HOME/.kighmu"

# Optionnel : ajouter une clé publique SSH (si fournie)
read -p "Si vous avez une clé publique SSH à ajouter, collez-la maintenant (ou appuyez sur Entrée pour passer) : " PUBKEY

if [ -n "$PUBKEY" ]; then
    echo "$PUBKEY" > "$USER_HOME/.ssh/authorized_keys"
    chmod 600 "$USER_HOME/.ssh/authorized_keys"
    chown "$USERNAME":"$USERNAME" "$USER_HOME/.ssh/authorized_keys"
    echo "Clé publique SSH ajoutée pour $USERNAME."
else
    echo "Aucune clé publique SSH ajoutée."
fi

# Copier banner global dans dossier utilisateur pour affichage
if [ -f "$HOME/.kighmu/banner.txt" ]; then
    cp "$HOME/.kighmu/banner.txt" "$USER_HOME/.kighmu/banner.txt"
    chown "$USERNAME":"$USERNAME" "$USER_HOME/.kighmu/banner.txt"
else
    echo "Aucun banner global trouvé à copier dans l'espace utilisateur."
fi

# Ajouter affichage banner dans .bashrc utilisateur
echo "
# Affichage du banner Kighmu VPS Manager
if [ -f ~/.kighmu/banner.txt ]; then
    cat ~/.kighmu/banner.txt
fi
" >> "$USER_HOME/.bashrc"
chown "$USERNAME":"$USERNAME" "$USER_HOME/.bashrc"

echo
echo "+--------------------------------------------+"
echo "|        UTILISATEUR SSH CRÉÉ AVEC SUCCÈS   |"
echo "+--------------------------------------------+"
echo "Nom de domaine       : $DOMAIN"
echo "Serveur DNS (NS)     : $NS"
echo -e "Clé publique SlowDNS :\n$PUBLIC_KEY"
echo "+--------------------------------------------+"

echo "Utilisateur $USERNAME créé et configuré avec succès."
