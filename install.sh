# Installer git si pas déjà fait
apt install git -y

# Cloner ton dépôt vide
git clone https://github.com/TON_UTILISATEUR/kighmu.git
cd kighmu

# Copier tes fichiers dans ce dossier
cp /chemin/vers/tes/fichiers/*.sh .

# Ajouter les fichiers
git add .

# Commit
git commit -m "🎉 Première version de KIGHMU MANAGER"

# Envoi vers GitHub
git push origin main
