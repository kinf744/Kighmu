# ~/.bashrc - Configuration personnalisée

# Ajout de /usr/local/bin au PATH si ce n'est pas déjà présent
if [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
    export PATH="$PATH:/usr/local/bin"
fi

# Alias pour lancer le script kighmu
alias kighmu="/usr/local/bin/kighmu"
