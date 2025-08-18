#!/bin/bash

# Script pour créer un utilisateur SSH avec configuration complète

read -p "Nom utilisateur à créer : " USERNAME

if id "$USERNAME" &>/dev/null; then
    echo "L'utilisateur $USERNAME existe déjà."
    exit 1
fi

# Création de l'utilisateur avec home et shell bash
sudo useradd -m -s /bin/bash "$USERNAME"

# Demander et définir le mot de passe
echo "Définir le mot de passe pour $USERNAME :"
sudo passwd "$USERNAME"

# Création du dossier .ssh avec droits stricts
sudo mkdir -p /home/"$USERNAME"/.ssh
sudo chmod 700 /home/"$USERNAME"/.ssh

# Optionnel : ajouter une clé publique SSH (si fournie)
read -p "Si vous avez une clé publique SSH à ajouter, collez-la maintenant (ou appuyez sur Entrée pour passer) : " PUBKEY

if [ -n "$PUBKEY" ]; then
    echo "$PUBKEY" | sudo tee /home/"$USERNAME"/.ssh/authorized_keys > /dev/null
    sudo chmod 600 /home/"$USERNAME"/.ssh/authorized_keys
    sudo chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"/.ssh
    echo "Clé publique SSH ajoutée pour $USERNAME."
else
    echo "Aucune clé publique SSH ajoutée."
fi

# Finalisation des permissions
sudo chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"/.ssh

echo "Utilisateur $USERNAME créé et configuré avec succès."
